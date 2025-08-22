//
//  ErrorHandler.swift
//  HeartScanner
//
//  Created by Athanas Shauritanga on 19/08/2025.
//

import Foundation

// MARK: - App-wide Error Types

enum ModelError: Error, LocalizedError {
    case resourceNotFound(String)
    case compilationFailed(String)
    case initializationFailed(String)
    case invalidInput(String)
    case predictionFailed(String)

    var errorDescription: String? {
        switch self {
        case .resourceNotFound(let resource):
            return "Model resource not found: \(resource)"
        case .compilationFailed(let model):
            return "Failed to compile model: \(model)"
        case .initializationFailed(let model):
            return "Failed to initialize model: \(model)"
        case .invalidInput(let details):
            return "Invalid input: \(details)"
        case .predictionFailed(let details):
            return "Prediction failed: \(details)"
        }
    }
}

enum ButterflyError: Error, LocalizedError {
    case connectionFailed
    case probeIncompatible
    case firmwareOutdated
    case licensingError
    case imagingFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to Butterfly probe"
        case .probeIncompatible:
            return "Probe is not compatible with this device"
        case .firmwareOutdated:
            return "Probe firmware needs to be updated"
        case .licensingError:
            return "Butterfly licensing error"
        case .imagingFailed(let details):
            return "Imaging failed: \(details)"
        }
    }
}
