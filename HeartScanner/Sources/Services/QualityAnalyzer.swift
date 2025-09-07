import UIKit
import CoreImage
import Accelerate

/// Real-time quality analysis for ultrasound images and AI model performance
class QualityAnalyzer {
    static let shared = QualityAnalyzer()
    
    private init() {}
    
    // MARK: - Main Quality Analysis
    
    /// Analyze image quality and model performance to generate real quality metrics
    func analyzeQuality(
        image: UIImage,
        modelConfidence: Double? = nil,
        segmentationMask: UIImage? = nil,
        processingTime: TimeInterval? = nil
    ) -> ScanRecord.QualityMetrics {
        
        let imageClarity = calculateImageClarity(image: image)
        let signalToNoise = calculateSignalToNoise(image: image)
        let modelConf = modelConfidence ?? 0.0
        
        // Enhanced model confidence if we have segmentation data
        let enhancedModelConfidence = enhanceModelConfidence(
            baseConfidence: modelConf,
            segmentationMask: segmentationMask,
            processingTime: processingTime
        )
        
        let overallQuality = determineOverallQuality(
            imageClarity: imageClarity,
            modelConfidence: enhancedModelConfidence,
            signalToNoise: signalToNoise
        )
        
        return ScanRecord.QualityMetrics(
            imageClarity: imageClarity,
            modelConfidence: enhancedModelConfidence,
            signalToNoise: signalToNoise,
            overallQuality: overallQuality
        )
    }
    
    // MARK: - Image Clarity Analysis
    
    /// Calculate image clarity based on edge detection and contrast analysis
    private func calculateImageClarity(image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0.0 }
        
        // Convert to grayscale for analysis
        guard let grayscaleImage = convertToGrayscale(cgImage: cgImage) else { return 0.0 }
        
        // Calculate multiple clarity metrics
        let edgeStrength = calculateEdgeStrength(cgImage: grayscaleImage)
        let contrast = calculateContrast(cgImage: grayscaleImage)
        let sharpness = calculateSharpness(cgImage: grayscaleImage)
        
        // Weighted combination optimized for ultrasound images
        let clarity = (edgeStrength * 0.4) + (contrast * 0.3) + (sharpness * 0.3)
        
        // Normalize to 0-1 range and apply ultrasound-specific adjustments
        let normalizedClarity = min(max(clarity, 0.0), 1.0)
        
        print("🔍 QualityAnalyzer: Image clarity - Edge: \(String(format: "%.3f", edgeStrength)), Contrast: \(String(format: "%.3f", contrast)), Sharpness: \(String(format: "%.3f", sharpness)), Final: \(String(format: "%.3f", normalizedClarity))")
        
        return normalizedClarity
    }
    
    /// Calculate edge strength using Sobel operator
    private func calculateEdgeStrength(cgImage: CGImage) -> Double {
        let width = cgImage.width
        let height = cgImage.height
        
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else { return 0.0 }
        
        var edgeSum: Double = 0.0
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        
        // Sobel kernels
        let sobelX: [Int] = [-1, 0, 1, -2, 0, 2, -1, 0, 1]
        let sobelY: [Int] = [-1, -2, -1, 0, 0, 0, 1, 2, 1]
        
        for y in 1..<(height-1) {
            for x in 1..<(width-1) {
                var gx: Double = 0.0
                var gy: Double = 0.0
                
                for ky in -1...1 {
                    for kx in -1...1 {
                        let pixelIndex = ((y + ky) * width + (x + kx)) * bytesPerPixel
                        let pixelValue = Double(bytes[pixelIndex])
                        let kernelIndex = (ky + 1) * 3 + (kx + 1)
                        
                        gx += pixelValue * Double(sobelX[kernelIndex])
                        gy += pixelValue * Double(sobelY[kernelIndex])
                    }
                }
                
                let magnitude = sqrt(gx * gx + gy * gy)
                edgeSum += magnitude
            }
        }
        
        let avgEdgeStrength = edgeSum / Double((width - 2) * (height - 2))
        return min(avgEdgeStrength / 255.0, 1.0) // Normalize to 0-1
    }
    
    /// Calculate image contrast using standard deviation
    private func calculateContrast(cgImage: CGImage) -> Double {
        let width = cgImage.width
        let height = cgImage.height
        
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else { return 0.0 }
        
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let totalPixels = width * height
        
        // Calculate mean
        var sum: Double = 0.0
        for i in stride(from: 0, to: totalPixels * bytesPerPixel, by: bytesPerPixel) {
            sum += Double(bytes[i])
        }
        let mean = sum / Double(totalPixels)
        
        // Calculate standard deviation
        var variance: Double = 0.0
        for i in stride(from: 0, to: totalPixels * bytesPerPixel, by: bytesPerPixel) {
            let diff = Double(bytes[i]) - mean
            variance += diff * diff
        }
        
        let stdDev = sqrt(variance / Double(totalPixels))
        return min(stdDev / 128.0, 1.0) // Normalize to 0-1 (128 is half of 255)
    }
    
    /// Calculate image sharpness using Laplacian variance
    private func calculateSharpness(cgImage: CGImage) -> Double {
        let width = cgImage.width
        let height = cgImage.height
        
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else { return 0.0 }
        
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        
        // Laplacian kernel
        let laplacian: [Int] = [0, -1, 0, -1, 4, -1, 0, -1, 0]
        
        var laplacianSum: Double = 0.0
        var count = 0
        
        for y in 1..<(height-1) {
            for x in 1..<(width-1) {
                var convolution: Double = 0.0
                
                for ky in -1...1 {
                    for kx in -1...1 {
                        let pixelIndex = ((y + ky) * width + (x + kx)) * bytesPerPixel
                        let pixelValue = Double(bytes[pixelIndex])
                        let kernelIndex = (ky + 1) * 3 + (kx + 1)
                        
                        convolution += pixelValue * Double(laplacian[kernelIndex])
                    }
                }
                
                laplacianSum += convolution * convolution
                count += 1
            }
        }
        
        let variance = laplacianSum / Double(count)
        return min(sqrt(variance) / 1000.0, 1.0) // Normalize and cap at 1.0
    }
    
    // MARK: - Signal to Noise Ratio
    
    /// Calculate signal-to-noise ratio for ultrasound images
    private func calculateSignalToNoise(image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0.0 }
        guard let grayscaleImage = convertToGrayscale(cgImage: cgImage) else { return 0.0 }
        
        let width = grayscaleImage.width
        let height = grayscaleImage.height
        
        guard let dataProvider = grayscaleImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else { return 0.0 }
        
        let bytesPerPixel = grayscaleImage.bitsPerPixel / 8
        let totalPixels = width * height
        
        // Calculate signal (mean of bright regions) and noise (std dev of dark regions)
        var brightPixels: [Double] = []
        var darkPixels: [Double] = []
        
        for i in stride(from: 0, to: totalPixels * bytesPerPixel, by: bytesPerPixel) {
            let pixelValue = Double(bytes[i])
            
            if pixelValue > 128 { // Bright regions (signal)
                brightPixels.append(pixelValue)
            } else if pixelValue < 64 { // Dark regions (noise estimation)
                darkPixels.append(pixelValue)
            }
        }
        
        guard !brightPixels.isEmpty && !darkPixels.isEmpty else { return 0.5 }
        
        let signalMean = brightPixels.reduce(0, +) / Double(brightPixels.count)
        
        // Calculate noise as standard deviation of dark regions
        let noiseMean = darkPixels.reduce(0, +) / Double(darkPixels.count)
        let noiseVariance = darkPixels.map { pow($0 - noiseMean, 2) }.reduce(0, +) / Double(darkPixels.count)
        let noiseStdDev = sqrt(noiseVariance)
        
        let snr = noiseStdDev > 0 ? signalMean / noiseStdDev : 1.0
        let normalizedSNR = min(snr / 20.0, 1.0) // Normalize assuming max SNR of 20
        
        print("🔍 QualityAnalyzer: SNR - Signal: \(String(format: "%.1f", signalMean)), Noise: \(String(format: "%.1f", noiseStdDev)), SNR: \(String(format: "%.2f", snr)), Normalized: \(String(format: "%.3f", normalizedSNR))")
        
        return normalizedSNR
    }
    
    // MARK: - Model Confidence Enhancement
    
    /// Enhance model confidence based on additional factors
    private func enhanceModelConfidence(
        baseConfidence: Double,
        segmentationMask: UIImage?,
        processingTime: TimeInterval?
    ) -> Double {
        var enhancedConfidence = baseConfidence
        
        // Boost confidence if segmentation is available and valid
        if let mask = segmentationMask {
            let segmentationQuality = analyzeSegmentationQuality(mask: mask)
            enhancedConfidence = (baseConfidence * 0.7) + (segmentationQuality * 0.3)
        }
        
        // Adjust based on processing time (faster processing often indicates clearer images)
        if let procTime = processingTime {
            let timeBonus = procTime < 2.0 ? 0.05 : (procTime > 5.0 ? -0.05 : 0.0)
            enhancedConfidence = min(enhancedConfidence + timeBonus, 1.0)
        }
        
        return max(min(enhancedConfidence, 1.0), 0.0)
    }
    
    /// Analyze segmentation mask quality
    private func analyzeSegmentationQuality(mask: UIImage) -> Double {
        guard let cgImage = mask.cgImage else { return 0.0 }
        
        let width = cgImage.width
        let height = cgImage.height
        
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else { return 0.0 }
        
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let totalPixels = width * height
        
        var segmentedPixels = 0
        var edgePixels = 0
        
        // Count segmented pixels and edge continuity
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * width + x) * bytesPerPixel
                let pixelValue = bytes[pixelIndex]
                
                if pixelValue > 128 { // Segmented pixel
                    segmentedPixels += 1
                    
                    // Check if it's an edge pixel
                    if x > 0 && x < width-1 && y > 0 && y < height-1 {
                        let neighbors = [
                            bytes[((y-1) * width + x) * bytesPerPixel],
                            bytes[((y+1) * width + x) * bytesPerPixel],
                            bytes[(y * width + (x-1)) * bytesPerPixel],
                            bytes[(y * width + (x+1)) * bytesPerPixel]
                        ]
                        
                        if neighbors.contains(where: { $0 <= 128 }) {
                            edgePixels += 1
                        }
                    }
                }
            }
        }
        
        let segmentationRatio = Double(segmentedPixels) / Double(totalPixels)
        let edgeRatio = segmentedPixels > 0 ? Double(edgePixels) / Double(segmentedPixels) : 0.0
        
        // Good segmentation should have reasonable coverage (5-40%) and good edge definition
        let coverageScore = segmentationRatio > 0.05 && segmentationRatio < 0.4 ? 1.0 : 0.5
        let edgeScore = edgeRatio > 0.1 ? 1.0 : edgeRatio * 10.0
        
        return (coverageScore + edgeScore) / 2.0
    }
    
    // MARK: - Overall Quality Determination
    
    /// Determine overall quality rating based on all metrics
    private func determineOverallQuality(
        imageClarity: Double,
        modelConfidence: Double,
        signalToNoise: Double
    ) -> ScanRecord.QualityMetrics.QualityRating {
        
        // Weighted average with clinical priorities
        let overallScore = (imageClarity * 0.4) + (modelConfidence * 0.4) + (signalToNoise * 0.2)
        
        switch overallScore {
        case 0.85...: return .excellent
        case 0.70..<0.85: return .good
        case 0.50..<0.70: return .fair
        default: return .poor
        }
    }
    
    // MARK: - Helper Methods
    
    /// Convert CGImage to grayscale for analysis
    private func convertToGrayscale(cgImage: CGImage) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }
}
