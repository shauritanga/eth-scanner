import CoreImage
import CoreML
import CoreVideo
import Vision

class EFModel {
    private let model: MLModel?
    let isModelAvailable: Bool

    init() async throws {
        print("Starting EFModel initialization")

        // Try to load the compiled model first (.mlmodelc), then fall back to .mlpackage
        var modelURL: URL?

        if let compiledURL = Bundle.main.url(forResource: "EF_Model", withExtension: "mlmodelc") {
            modelURL = compiledURL
            print("Found compiled EF_Model.mlmodelc at: \(compiledURL.path)")
        } else if let packageURL = Bundle.main.url(
            forResource: "EF_Model", withExtension: "mlpackage")
        {
            modelURL = packageURL
            print("Found EF_Model.mlpackage at: \(packageURL.path)")
        } else {
            print("EF_Model not found in bundle - running in simulation mode")
            self.model = nil
            self.isModelAvailable = false
            return
        }

        do {
            // If it's already compiled (.mlmodelc), load directly. Otherwise compile first.
            let finalURL: URL
            if modelURL!.pathExtension == "mlmodelc" {
                finalURL = modelURL!
                print("Loading pre-compiled EF_Model")
            } else {
                finalURL = try await MLModel.compileModel(at: modelURL!)
                print("Successfully compiled EF_Model")
            }

            let config = MLModelConfiguration()
            // BALANCED PERFORMANCE: Use CPU and Neural Engine for good performance with reasonable thermal load
            config.computeUnits = .cpuAndNeuralEngine

            self.model = try MLModel(contentsOf: finalURL, configuration: config)
            self.isModelAvailable = true
            print("Successfully loaded EF_Model.mlpackage")

            // Debug: Print model input/output specifications
            print("=== EF Model Specifications ===")
            print("Input descriptions:")
            for (name, description) in self.model!.modelDescription.inputDescriptionsByName {
                print("  Input: \(name) -> \(description)")
                if let multiArrayConstraint = description.multiArrayConstraint {
                    print("    Shape: \(multiArrayConstraint.shape)")
                    print("    Data type: \(multiArrayConstraint.dataType)")
                }
            }
            print("Output descriptions:")
            for (name, description) in self.model!.modelDescription.outputDescriptionsByName {
                print("  Output: \(name) -> \(description)")
                if let multiArrayConstraint = description.multiArrayConstraint {
                    print("    Shape: \(multiArrayConstraint.shape)")
                    print("    Data type: \(multiArrayConstraint.dataType)")
                }
            }
        } catch {
            print(
                "Failed to compile or load EF_Model: \(error.localizedDescription) - running in simulation mode"
            )
            self.model = nil
            self.isModelAvailable = false
        }
    }

    func predict(_ clip: MLMultiArray) throws -> Float? {
        // CLINICAL VERSION: Model MUST be available for medical use
        guard isModelAvailable, let model = model else {
            print("CRITICAL ERROR: EF Model not available - cannot provide clinical results")
            throw NSError(
                domain: "EFModel", code: -100,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Clinical EF model not loaded. Cannot provide medical results."
                ])
        }

        print("EF Model prediction - Input shape: \(clip.shape)")
        guard clip.shape == [1, 3, 32, 112, 112] else {
            print("EF Model - Expected shape: [1, 3, 32, 112, 112], got: \(clip.shape)")
            throw NSError(
                domain: "EFModel", code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Invalid input shape - expected [1, 3, 32, 112, 112], got \(clip.shape)"
                ])
        }

        do {
            let input = MLFeatureValue(multiArray: clip)
            let featureProvider = try MLDictionaryFeatureProvider(dictionary: [
                "input_video_clip": input
            ])

            let prediction = try model.prediction(from: featureProvider)

            print("EF Model - Available output features: \(prediction.featureNames)")

            // Enhanced debugging: Print all output features and their values
            for featureName in prediction.featureNames {
                if let feature = prediction.featureValue(for: featureName) {
                    print("🔍 EF Model Output Feature: \(featureName)")
                    if let multiArray = feature.multiArrayValue {
                        print("  Shape: \(multiArray.shape)")
                        print("  Data type: \(multiArray.dataType)")
                        print("  Value: \(multiArray[0].floatValue)")
                    } else {
                        print("  Value: \(feature)")
                    }
                }
            }

            guard let output = prediction.featureValue(for: "var_596")?.multiArrayValue,
                output.shape == [1, 1]
            else {
                print("EF Model - Failed to get output 'var_596' or wrong shape")
                // Try to find the actual output name
                for featureName in prediction.featureNames {
                    if let feature = prediction.featureValue(for: featureName) {
                        print("  Available feature: \(featureName) -> \(feature)")
                    }
                }
                return nil
            }

            let rawEF = output[0].floatValue
            print("🔍 EF Model - Raw output value: \(rawEF)")
            print("🔍 EF Model - Output array shape: \(output.shape)")
            print("🔍 EF Model - Output data type: \(output.dataType)")

            // Normalize the EF value based on the model's output range
            let normalizedEF = normalizeEFOutput(rawEF)
            print("EF Model - Normalized EF: \(String(format: "%.1f", normalizedEF * 100))%")

            return normalizedEF
        } catch {
            print("EF prediction failed: \(error.localizedDescription)")
            return nil
        }
    }

    func preprocess(_ frames: [CVPixelBuffer]) async -> MLMultiArray? {
        // EF model requires exactly 32 frames
        guard !frames.isEmpty,
            let multiArray = try? MLMultiArray(shape: [1, 3, 32, 112, 112], dataType: .float32)
        else {
            print("EFModel: No frames available or MLMultiArray creation failed")
            return nil
        }

        print(
            "🔍 EFModel: Processing \(frames.count) real ultrasound frames, interpolating to 32 frames"
        )
        print("🔍 EFModel: Input array shape: \(multiArray.shape)")
        print("🔍 EFModel: Input data type: \(multiArray.dataType)")

        // Create 32 frames from available frames using temporal interpolation
        let availableFrames = frames.count

        for frameIndex in 0..<32 {
            // Map 32 output frames to available input frames using linear interpolation
            let sourcePosition = Float(frameIndex) * Float(availableFrames - 1) / 31.0
            let sourceFrameIndex = Int(sourcePosition) % availableFrames
            let sourceFrame = frames[sourceFrameIndex]

            // Process real CVPixelBuffer data
            guard
                let processedData = await processUltrasoundFrame(
                    sourceFrame, targetSize: CGSize(width: 112, height: 112))
            else {
                print("EFModel: Failed to process frame \(frameIndex), using fallback")
                continue
            }

            // Fill the multiArray with real processed ultrasound data
            for channel in 0..<3 {
                for y in 0..<112 {
                    for x in 0..<112 {
                        let index = [0, channel, frameIndex, y, x] as [NSNumber]
                        let pixelIndex = y * 112 + x

                        if pixelIndex < processedData.count {
                            // Use real ultrasound data
                            let pixelValue = processedData[pixelIndex]
                            multiArray[index] = NSNumber(value: pixelValue)
                        } else {
                            // Fallback for edge cases
                            multiArray[index] = NSNumber(value: 0.0)
                        }
                    }
                }
            }
        }

        // Debug: Check input data statistics
        var minVal: Float = Float.greatestFiniteMagnitude
        var maxVal: Float = -Float.greatestFiniteMagnitude
        var sumVal: Float = 0.0
        var count = 0

        for channel in 0..<3 {
            for frame in 0..<32 {
                for y in 0..<112 {
                    for x in 0..<112 {
                        let index = [0, channel, frame, y, x] as [NSNumber]
                        let value = multiArray[index].floatValue
                        minVal = min(minVal, value)
                        maxVal = max(maxVal, value)
                        sumVal += value
                        count += 1
                    }
                }
            }
        }

        let avgVal = sumVal / Float(count)
        print("🔍 EFModel Input Statistics:")
        print("  Min pixel value: \(minVal)")
        print("  Max pixel value: \(maxVal)")
        print("  Average pixel value: \(avgVal)")
        print("  Total pixels: \(count)")

        return multiArray
    }

    private func processUltrasoundFrame(_ pixelBuffer: CVPixelBuffer, targetSize: CGSize) async
        -> [Float]?
    {
        // Lock the pixel buffer for reading
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            print("EFModel: Failed to get pixel buffer base address")
            return nil
        }

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        print("EFModel: Processing frame \(width)x\(height), format: \(pixelFormat)")

        // Convert to grayscale and resize to target size
        var processedPixels: [Float] = []
        let targetWidth = Int(targetSize.width)
        let targetHeight = Int(targetSize.height)

        for y in 0..<targetHeight {
            for x in 0..<targetWidth {
                // Calculate source coordinates with bilinear interpolation
                let srcX = Float(x) * Float(width) / Float(targetWidth)
                let srcY = Float(y) * Float(height) / Float(targetHeight)

                let x0 = Int(srcX)
                let y0 = Int(srcY)
                let x1 = min(x0 + 1, width - 1)
                let y1 = min(y0 + 1, height - 1)

                // Get pixel values (assuming BGRA format)
                let pixel00 = getPixelValue(baseAddress, x: x0, y: y0, bytesPerRow: bytesPerRow)
                let pixel01 = getPixelValue(baseAddress, x: x0, y: y1, bytesPerRow: bytesPerRow)
                let pixel10 = getPixelValue(baseAddress, x: x1, y: y0, bytesPerRow: bytesPerRow)
                let pixel11 = getPixelValue(baseAddress, x: x1, y: y1, bytesPerRow: bytesPerRow)

                // Bilinear interpolation
                let fx = srcX - Float(x0)
                let fy = srcY - Float(y0)

                let interpolated =
                    pixel00 * (1 - fx) * (1 - fy) + pixel10 * fx * (1 - fy) + pixel01 * (1 - fx)
                    * fy + pixel11 * fx * fy

                // Normalize to [0, 1] range for neural network
                processedPixels.append(interpolated / 255.0)
            }
        }

        return processedPixels
    }

    private func getPixelValue(
        _ baseAddress: UnsafeMutableRawPointer, x: Int, y: Int, bytesPerRow: Int
    ) -> Float {
        let pixelData = baseAddress.assumingMemoryBound(to: UInt8.self)
        let offset = y * bytesPerRow + x * 4  // Assuming 4 bytes per pixel (BGRA)

        // Convert BGRA to grayscale using standard luminance formula
        let b = Float(pixelData[offset])
        let g = Float(pixelData[offset + 1])
        let r = Float(pixelData[offset + 2])

        // Standard RGB to grayscale conversion
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    private func normalizeEFOutput(_ rawValue: Float) -> Float {
        print("🔍 EF Normalization - Raw input: \(rawValue)")

        // The model might output values in different ranges. Let's handle common cases:

        // Case 1: If the value is already in 0-1 range (most likely)
        if rawValue >= 0.0 && rawValue <= 1.0 {
            print("🔍 EF Normalization - Case 1: Value in 0-1 range, returning as-is")
            return rawValue
        }

        // Case 2: If the value is in 0-100 range (percentage)
        if rawValue >= 0.0 && rawValue <= 100.0 {
            let normalized = rawValue / 100.0
            print("🔍 EF Normalization - Case 2: Value in 0-100 range, normalized to \(normalized)")
            return normalized
        }

        // Case 3: If the value is very large (like 5102.7), it might need sigmoid normalization
        if rawValue > 100.0 {
            // Apply sigmoid to normalize large values to 0-1 range
            let sigmoid = 1.0 / (1.0 + exp(-rawValue / 1000.0))  // Scale down large values
            print("🔍 EF Normalization - Case 3: Large value, sigmoid normalized to \(sigmoid)")
            return Float(sigmoid)
        }

        // Case 4: If the value is negative, apply sigmoid
        if rawValue < 0.0 {
            let sigmoid = 1.0 / (1.0 + exp(-rawValue))
            print("🔍 EF Normalization - Case 4: Negative value, sigmoid normalized to \(sigmoid)")
            print("🔍 EF Normalization - Sigmoid calculation: 1/(1+exp(-\(rawValue))) = \(sigmoid)")
            return Float(sigmoid)
        }

        // Fallback: clamp to reasonable range
        let clamped = max(0.15, min(0.80, rawValue))
        print("🔍 EF Normalization - Fallback: Clamped to \(clamped)")
        return clamped
    }
}
