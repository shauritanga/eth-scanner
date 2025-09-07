import CoreML
import Foundation
import UIKit

/// Loader and predictor for EF_Model_multi_output.mlpackage
/// Provides multiple cardiac metrics from a single image input
final class MultiOutputModel {
    static let shared = MultiOutputModel()

    private var model: MLModel?
    private(set) var isModelAvailable: Bool = false

    private init() {
        Task { await self.loadModel() }
    }

    @MainActor
    private func loadModel() async {
        // Locate compiled or package model
        var modelURL: URL?
        if let compiledURL = Bundle.main.url(
            forResource: "EF_Model_multi_output", withExtension: "mlmodelc")
        {
            modelURL = compiledURL
            print("Found compiled EF_Model_multi_output.mlmodelc at: \(compiledURL.path)")
        } else if let packageURL = Bundle.main.url(
            forResource: "EF_Model_multi_output", withExtension: "mlpackage")
        {
            modelURL = packageURL
            print("Found EF_Model_multi_output.mlpackage at: \(packageURL.path)")
        } else {
            print("EF_Model_multi_output not found in bundle")
            self.isModelAvailable = false
            return
        }

        do {
            let finalURL: URL
            if modelURL!.pathExtension == "mlmodelc" {
                finalURL = modelURL!
            } else {
                finalURL = try await MLModel.compileModel(at: modelURL!)
            }

            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            self.model = try MLModel(contentsOf: finalURL, configuration: config)
            self.isModelAvailable = true
            // Notify listeners that MultiOutput model is ready
            NotificationCenter.default.post(name: .multiOutputModelReady, object: nil)

            if let model = self.model {
                print("Successfully loaded EF_Model_multi_output model")
                print("=== Multi-Output Model I/O Specs ===")
                for (name, desc) in model.modelDescription.inputDescriptionsByName {
                    print("Input: \(name) -> \(desc)")
                }
                for (name, desc) in model.modelDescription.outputDescriptionsByName {
                    print("Output: \(name) -> \(desc)")
                }
            }
        } catch {
            print("Failed to load EF_Model_multi_output: \(error.localizedDescription)")
            self.isModelAvailable = false
        }
    }

    struct Outputs {
        var efPercent: Double?
        var edvMl: Double?
        var esvMl: Double?
        var lviddCm: Double?
        var lvidsCm: Double?
        var ivsdCm: Double?
        var lvpwdCm: Double?
        var tapseMm: Double?
    }

    /// Run prediction for a given image. Returns parsed outputs of interest.
    func predict(image: UIImage) -> Outputs? {
        guard isModelAvailable, let model = model else { return nil }
        guard let cgImage = image.cgImage else { return nil }

        // Determine input name and constraints
        guard let inputDesc = model.modelDescription.inputDescriptionsByName.values.first else {
            return nil
        }

        var provider: MLFeatureProvider
        do {
            if let imageConstraint = inputDesc.imageConstraint {
                let options: [MLFeatureValue.ImageOption: Any] = [:]
                let imageValue = try MLFeatureValue(
                    cgImage: cgImage, constraint: imageConstraint, options: options)
                provider = try MLDictionaryFeatureProvider(dictionary: [inputDesc.name: imageValue])
            } else if inputDesc.type == .multiArray, let constraint = inputDesc.multiArrayConstraint
            {
                // Convert UIImage to MLMultiArray matching constraint (basic grayscale normalization)
                guard let array = try? imageToMultiArray(cgImage: cgImage, constraint: constraint)
                else { return nil }
                let fv = MLFeatureValue(multiArray: array)
                provider = try MLDictionaryFeatureProvider(dictionary: [inputDesc.name: fv])
            } else {
                print("Unsupported input type for EF_Model_multi_output: \(inputDesc.type)")
                return nil
            }

            let prediction = try model.prediction(from: provider)
            // Debug: list available outputs once
            print("Multi-Output prediction features: \(prediction.featureNames.sorted())")

            func scalar(_ key: String) -> Double? {
                if let v = prediction.featureValue(for: key) {
                    if v.type == .double { return v.doubleValue }
                    if let ma = v.multiArrayValue { return ma[0].doubleValue }
                    if v.type == .int64 { return Double(v.int64Value) }
                }
                return nil
            }

            var out = Outputs()
            // Apply calibration multipliers from AppConstants
            if let v = scalar("EF_prediction") {
                out.efPercent = (v * AppConstants.Calibration.efPercent).clampedPercent()
            }
            if let v = scalar("LVEDV_prediction") { out.edvMl = v * AppConstants.Calibration.edvMl }
            if let v = scalar("LVESV_prediction") { out.esvMl = v * AppConstants.Calibration.esvMl }
            if let v = scalar("LVIDd_prediction") {
                out.lviddCm = v * AppConstants.Calibration.lviddCm
            }
            if let v = scalar("LVIDs_prediction") {
                out.lvidsCm = v * AppConstants.Calibration.lvidsCm
            }
            if let v = scalar("IVSd_prediction") {
                out.ivsdCm = v * AppConstants.Calibration.ivsdCm
            }
            if let v = scalar("LVPWd_prediction") {
                out.lvpwdCm = v * AppConstants.Calibration.lvpwdCm
            }
            if let v = scalar("TAPSE_prediction") {
                out.tapseMm = v * AppConstants.Calibration.tapseMm
            }
            return out
        } catch {
            print("Multi-Output prediction failed: \(error.localizedDescription)")
            return nil
        }
    }
}

extension Double {
    fileprivate func clampedPercent() -> Double { max(0.0, min(self, 100.0)) }
}

/// Minimal conversion of CGImage to MLMultiArray matching constraint (grayscale, [1,H,W] or [1,1,H,W])
private func imageToMultiArray(cgImage: CGImage, constraint: MLMultiArrayConstraint) throws
    -> MLMultiArray
{
    let shape = constraint.shape.map { $0.intValue }
    // Support common shapes: [1,1,H,W] or [1,H,W]
    let height: Int
    let width: Int
    if shape.count == 4 {
        height = shape[2]
        width = shape[3]
    } else if shape.count == 3 {
        height = shape[1]
        width = shape[2]
    } else {
        throw NSError(
            domain: "MultiOutputModel", code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported input shape \(shape)"])
    }

    let colorSpace = CGColorSpaceCreateDeviceGray()
    guard
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else {
        throw NSError(
            domain: "MultiOutputModel", code: -3,
            userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"])
    }
    ctx.interpolationQuality = .high
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = ctx.data else {
        throw NSError(
            domain: "MultiOutputModel", code: -4,
            userInfo: [NSLocalizedDescriptionKey: "No pixel data"])
    }

    let array = try MLMultiArray(shape: constraint.shape, dataType: constraint.dataType)
    let ptr = data.bindMemory(to: UInt8.self, capacity: width * height)

    // Fill as [1,1,H,W] or [1,H,W]
    var idx = 0
    if shape.count == 4 {
        for y in 0..<height {
            for x in 0..<width {
                let v = Double(ptr[idx]) / 255.0
                array[[0, 0, y, x] as [NSNumber]] = NSNumber(value: v)
                idx += 1
            }
        }
    } else {
        for y in 0..<height {
            for x in 0..<width {
                let v = Double(ptr[idx]) / 255.0
                array[[0, y, x] as [NSNumber]] = NSNumber(value: v)
                idx += 1
            }
        }
    }
    return array
}

extension Notification.Name {
    static let multiOutputModelReady = Notification.Name("MultiOutputModelReady")
}
