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

    // Frame processing optimization
    static let frameProcessingInterval: TimeInterval = 0.15  // Reduced to 150ms for better responsiveness

    // Image quality settings
    static let imageCompressionQuality: Double = 0.9  // Higher quality for better clarity
    static let enableImageStabilization = true
    static let enableNoiseReduction = true
    static let enableContrastEnhancement = true
    static let frameAveragingCount = 3  // Average 3 frames to reduce motion artifacts
}
