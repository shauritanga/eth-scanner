import CoreImage
import CoreML
import UIKit

extension UIImage {
    func toCVPixelBuffer() -> CVPixelBuffer? {
        guard let cgImage = self.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height

        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )

        guard let cgContext = context else { return nil }
        cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }

    func resized(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

extension CVPixelBuffer {
    func resize(to size: CGSize) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: self)
        let context = CIContext()
        let scaleX = size.width / CGFloat(CVPixelBufferGetWidth(self))
        let scaleY = size.height / CGFloat(CVPixelBufferGetHeight(self))
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        var newPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &newPixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = newPixelBuffer else {
            return nil
        }
        context.render(scaledImage, to: pixelBuffer)
        return pixelBuffer
    }

    func normalize() -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: self)
        let filter = CIFilter(name: "CIColorMatrix")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(x: 1 / 255, y: 1 / 255, z: 1 / 255, w: 1), forKey: "inputRVector")
        filter?.setValue(CIVector(x: 1 / 255, y: 1 / 255, z: 1 / 255, w: 1), forKey: "inputGVector")
        filter?.setValue(CIVector(x: 1 / 255, y: 1 / 255, z: 1 / 255, w: 1), forKey: "inputBVector")
        filter?.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
        guard let outputImage = filter?.outputImage else { return nil }
        let context = CIContext()
        var newPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            CVPixelBufferGetWidth(self),
            CVPixelBufferGetHeight(self),
            kCVPixelFormatType_32BGRA,
            nil,
            &newPixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = newPixelBuffer else { return nil }
        context.render(outputImage, to: pixelBuffer)
        return pixelBuffer
    }

    func pixelData() -> [[Float]]? {
        CVPixelBufferLockBaseAddress(self, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(self) else { return nil }
        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(self)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var rgbData: [[Float]] = [[Float]](
            repeating: [Float](repeating: 0, count: width * height), count: 3)
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * bytesPerRow + x * 4
                rgbData[0][y * width + x] = Float(buffer[pixelIndex + 2]) / 255.0  // Red
                rgbData[1][y * width + x] = Float(buffer[pixelIndex + 1]) / 255.0  // Green
                rgbData[2][y * width + x] = Float(buffer[pixelIndex]) / 255.0  // Blue
            }
        }
        return rgbData
    }
}

extension MLMultiArray {
    func toUIImage() -> UIImage? {
        var pixels = [UInt8](repeating: 0, count: 112 * 112 * 4)
        for y in 0..<112 {
            for x in 0..<112 {
                let value = self[[0, 0, y, x] as [NSNumber]].floatValue
                let index = (y * 112 + x) * 4

                // Clamp value to [0, 1] range before converting to UInt8
                let clampedValue = max(0.0, min(1.0, value))
                let pixelValue = UInt8(clampedValue * 255)

                pixels[index] = pixelValue  // Red channel
                pixels[index + 1] = 0  // Green
                pixels[index + 2] = 0  // Blue
                pixels[index + 3] = UInt8(clampedValue > 0.5 ? 255 : 128)  // Alpha
            }
        }
        let provider = CGDataProvider(data: NSData(bytes: pixels, length: pixels.count))
        let cgImage = CGImage(
            width: 112,
            height: 112,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 112 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
        return cgImage.map { UIImage(cgImage: $0) }
    }
}
