//
//  Constants.swift
//  HeartScanner
//
//  Created by Athanas Shauritanga on 19/08/2025.
//

import Foundation

// MARK: - Butterfly iQ Configuration
let clientKey = "E4BEB4-5955BC-CFC9E6-FB5825-EC2974-V3"

// MARK: - App Configuration
struct AppConstants {
    // Reduced from 32 to 16 to save memory (50% reduction)
    static let maxFrameBufferSize = 16
    static let efLowerThreshold: Float = 0.2
    static let efUpperThreshold: Float = 0.8

    // Frame processing optimization - MEDICAL GRADE PERFORMANCE
    static let frameProcessingInterval: TimeInterval = 0.2  // 200ms for smooth medical imaging
    static let aiProcessingInterval: TimeInterval = 0.5  // 500ms for AI models (separate from frame display)

    // Image quality settings
    static let imageCompressionQuality: Double = 0.9  // Higher quality for better clarity
    static let enableImageStabilization = true
    static let enableNoiseReduction = true
    static let enableContrastEnhancement = true
    static let frameAveragingCount = 3  // Average 3 frames to reduce motion artifacts

    // Hidden calibration multipliers for multi-output metrics (adjust after validation)
    struct Calibration {
        static var efPercent: Double = 1.0
        static var edvMl: Double = 1.0
        static var esvMl: Double = 1.0
        static var lviddCm: Double = 1.0
        static var lvidsCm: Double = 1.0
        static var ivsdCm: Double = 1.0
        static var lvpwdCm: Double = 1.0
        static var tapseMm: Double = 1.0
    }

    // Clinical thresholds for UI checks
    struct Clinical {
        static let efPercentRange: ClosedRange<Double> = 15.0...80.0
        static let tapseNormalMinMm: Double = 17.0
    }
}
