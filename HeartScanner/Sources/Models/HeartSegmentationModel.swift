import CoreML
import Vision
import UIKit

/// Manages loading and inference for the Segmentation Core ML model.
class HeartSegmentationModel {
    private let model: MLModel
    
    /// Initializes the Segmentation model by loading the Core ML model from the bundle.
    init() {
            guard let modelURL = Bundle.main.url(forResource: "SegmentationModel", withExtension: "mlpackage"), // Updated extension
                  let model = try? MLModel(contentsOf: modelURL) else {
                fatalError("Failed to load SegmentationModel.mlpackage from bundle")
            }
            self.model = model
        }
    
    /// Performs segmentation inference on a single frame.
    /// - Parameter frame: MLMultiArray of shape [1, 3, 112, 112] representing a preprocessed frame.
    /// - Returns: UIImage representing the segmentation mask, or nil if inference fails.
    func predict(_ frame: MLMultiArray) async throws -> UIImage? {
            guard frame.shape == [1, 3, 112, 112] else {
                throw NSError(domain: "HeartSegmentationModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid input shape: Expected [1, 3, 112, 112]"])
            }
            
            let input = MLFeatureValue(multiArray: frame)
            let featureProvider = try MLDictionaryFeatureProvider(dictionary: ["input_frame": input])
        let prediction = try await model.prediction(from: featureProvider)
            
            guard let mask = prediction.featureValue(for: "var_932")?.multiArrayValue,
                  mask.shape == [1, 1, 112, 112] else {
                return nil
            }
            
            return mask.toUIImage()
        }
    
    /// Preprocesses a single frame to match the Segmentation model input requirements.
    /// - Parameter frame: CVPixelBuffer from Butterfly iQ SDK.
    /// - Returns: MLMultiArray of shape [1, 3, 112, 112], or nil if preprocessing fails.
    func preprocess(_ frame: CVPixelBuffer) async -> MLMultiArray? {
        guard let resizedFrame = frame.resize(to: CGSize(width: 112, height: 112)),
              let normalizedFrame = resizedFrame.normalize(),
              let pixelData = normalizedFrame.pixelData(),
              let multiArray = try? MLMultiArray(shape: [1, 3, 112, 112], dataType: .float32) else {
            print("SegmentationModel: Failed to preprocess frame")
            return nil
        }
        
        // Copy pixel data to MLMultiArray
        for channel in 0..<3 {
            for y in 0..<112 {
                for x in 0..<112 {
                    let index = [0, channel, y, x] as [NSNumber]
                    multiArray[index] = NSNumber(value: pixelData[channel][y * 112 + x])
                }
            }
        }
        
        return multiArray
    }
}

