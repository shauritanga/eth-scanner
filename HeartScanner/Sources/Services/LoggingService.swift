import Foundation

class LoggingService {
    static func log(_ message: String, level: LogLevel = .info) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "[\(timestamp)] [\(level.rawValue)] \(message)"
        print(logEntry) // Replace with file/server logging
    }
    
    enum LogLevel: String {
        case info, warning, error
    }
}

