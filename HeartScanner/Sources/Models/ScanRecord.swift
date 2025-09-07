import CoreML
import Foundation
import UIKit

/// Comprehensive scan record for cardiac analysis
struct ScanRecord: Codable, Identifiable, Equatable {
    let id: String
    let patient: Patient?
    let scanDate: Date
    let scanDuration: TimeInterval
    let deviceInfo: DeviceInfo
    let analysisResults: AnalysisResults
    let imageData: ImageData
    let clinicalNotes: String
    let qualityMetrics: QualityMetrics
    let exportHistory: [ExportRecord]

    struct DeviceInfo: Codable, Equatable {
        let deviceName: String
        let probeType: String
        let firmwareVersion: String
        let appVersion: String
        let operatorID: String?

        static var current: DeviceInfo {
            return DeviceInfo(
                deviceName: UIDevice.current.name,
                probeType: "Butterfly iQ",
                firmwareVersion: "Unknown",
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    ?? "1.0",
                operatorID: nil
            )
        }
    }

    struct AnalysisResults: Codable, Equatable {
        // Primary EF and confidence
        let ejectionFraction: Double?  // %
        let efConfidence: Double?
        // Multi-output metrics (optional)
        let edvMl: Double?
        let esvMl: Double?
        let lviddCm: Double?
        let lvidsCm: Double?
        let ivsdCm: Double?
        let lvpwdCm: Double?
        let tapseMm: Double?

        let segmentationResults: SegmentationData?
        let measurements: [Measurement]
        let aiModelVersion: String
        let processingTime: TimeInterval

        init(
            ejectionFraction: Double?,
            efConfidence: Double?,
            edvMl: Double? = nil,
            esvMl: Double? = nil,
            lviddCm: Double? = nil,
            lvidsCm: Double? = nil,
            ivsdCm: Double? = nil,
            lvpwdCm: Double? = nil,
            tapseMm: Double? = nil,
            segmentationResults: SegmentationData?,
            measurements: [Measurement],
            aiModelVersion: String,
            processingTime: TimeInterval
        ) {
            self.ejectionFraction = ejectionFraction
            self.efConfidence = efConfidence
            self.edvMl = edvMl
            self.esvMl = esvMl
            self.lviddCm = lviddCm
            self.lvidsCm = lvidsCm
            self.ivsdCm = ivsdCm
            self.lvpwdCm = lvpwdCm
            self.tapseMm = tapseMm
            self.segmentationResults = segmentationResults
            self.measurements = measurements
            self.aiModelVersion = aiModelVersion
            self.processingTime = processingTime
        }

        struct SegmentationData: Codable, Equatable {
            let leftVentricleArea: Double?
            let rightVentricleArea: Double?
            let atriumArea: Double?
            let confidence: Double
        }

        struct Measurement: Codable, Equatable, Identifiable {
            let id: String
            let type: MeasurementType
            let value: Double
            let unit: String
            let timestamp: Date

            enum MeasurementType: String, Codable, CaseIterable {
                case ejectionFraction = "EF"
                case leftVentricleVolume = "LV Volume"
                case strokeVolume = "Stroke Volume"
                case cardiacOutput = "Cardiac Output"
                case heartRate = "Heart Rate"

                var displayName: String {
                    return self.rawValue
                }
            }

            init(type: MeasurementType, value: Double, unit: String) {
                self.id = UUID().uuidString
                self.type = type
                self.value = value
                self.unit = unit
                self.timestamp = Date()
            }
        }
    }

    struct ImageData: Codable, Equatable {
        let thumbnailPath: String
        let fullImagePath: String
        let videoPath: String?
        let originalImageSize: CGSize
        let compressionQuality: Double

        init(
            thumbnailPath: String, fullImagePath: String, videoPath: String? = nil,
            originalSize: CGSize = CGSize(width: 640, height: 480)
        ) {
            self.thumbnailPath = thumbnailPath
            self.fullImagePath = fullImagePath
            self.videoPath = videoPath
            self.originalImageSize = originalSize
            self.compressionQuality = 0.8
        }
    }

    struct QualityMetrics: Codable, Equatable {
        let imageClarity: Double  // 0.0 - 1.0
        let modelConfidence: Double  // 0.0 - 1.0
        let signalToNoise: Double
        let overallQuality: QualityRating

        enum QualityRating: String, Codable, CaseIterable {
            case excellent = "Excellent"
            case good = "Good"
            case fair = "Fair"
            case poor = "Poor"

            var color: String {
                switch self {
                case .excellent: return "green"
                case .good: return "blue"
                case .fair: return "orange"
                case .poor: return "red"
                }
            }
        }

        /// Generate real quality metrics from image analysis
        static func analyze(
            image: UIImage,
            modelConfidence: Double? = nil,
            segmentationMask: UIImage? = nil,
            processingTime: TimeInterval? = nil
        ) -> QualityMetrics {
            return QualityAnalyzer.shared.analyzeQuality(
                image: image,
                modelConfidence: modelConfidence,
                segmentationMask: segmentationMask,
                processingTime: processingTime
            )
        }

        /// Fallback sample data for previews and testing
        static var sample: QualityMetrics {
            return QualityMetrics(
                imageClarity: 0.85,
                modelConfidence: 0.92,
                signalToNoise: 0.78,
                overallQuality: .good
            )
        }
    }

    struct ExportRecord: Codable, Equatable, Identifiable {
        let id: String
        let exportDate: Date
        let format: ExportFormat
        let destination: String
        let fileSize: Int64

        enum ExportFormat: String, Codable, CaseIterable {
            case pdf = "PDF"
            case jpeg = "JPEG"
            case png = "PNG"
            case mp4 = "MP4"
            case dicom = "DICOM"

            var fileExtension: String {
                switch self {
                case .pdf: return ".pdf"
                case .jpeg: return ".jpg"
                case .png: return ".png"
                case .mp4: return ".mp4"
                case .dicom: return ".dcm"
                }
            }
        }

        init(format: ExportFormat, destination: String, fileSize: Int64) {
            self.id = UUID().uuidString
            self.exportDate = Date()
            self.format = format
            self.destination = destination
            self.fileSize = fileSize
        }
    }

    init(
        patient: Patient?,
        analysisResults: AnalysisResults,
        imageData: ImageData,
        clinicalNotes: String = "",
        scanDuration: TimeInterval = 0,
        qualityMetrics: QualityMetrics? = nil
    ) {
        self.id = UUID().uuidString
        self.patient = patient
        self.scanDate = Date()
        self.scanDuration = scanDuration
        self.deviceInfo = DeviceInfo.current
        self.analysisResults = analysisResults
        self.imageData = imageData
        self.clinicalNotes = clinicalNotes
        self.qualityMetrics = qualityMetrics ?? QualityMetrics.sample
        self.exportHistory = []
    }
}

// MARK: - Computed Properties
extension ScanRecord {
    /// Display title for the scan
    var displayTitle: String {
        if let patient = patient {
            return "Patient \(patient.patientID)"
        } else {
            return "Anonymous Scan"
        }
    }

    /// Formatted scan date
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: scanDate)
    }

    /// Primary result summary
    var resultSummary: String {
        if let ef = analysisResults.ejectionFraction {
            return "EF: \(String(format: "%.1f", ef))%"
        } else {
            return "Analysis Pending"
        }
    }

    /// Quality indicator for UI
    var qualityIndicator: String {
        return qualityMetrics.overallQuality.rawValue
    }

    /// File size summary - calculates actual file sizes
    var fileSizeDescription: String {
        var totalSize: Int64 = 0

        // Calculate thumbnail size
        let thumbnailURL = MediaManager.shared.getMediaURL(for: imageData.thumbnailPath)
        totalSize += getFileSize(url: thumbnailURL)

        // Calculate full image size
        let fullImageURL = MediaManager.shared.getMediaURL(for: imageData.fullImagePath)
        totalSize += getFileSize(url: fullImageURL)

        // Calculate video size if available
        if let videoPath = imageData.videoPath {
            let videoURL = MediaManager.shared.getMediaURL(for: videoPath)
            totalSize += getFileSize(url: videoURL)
        }

        return formatFileSize(bytes: totalSize)
    }

    /// Get file size for a given URL
    private func getFileSize(url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    /// Format file size in human-readable format
    private func formatFileSize(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Sample Data
extension ScanRecord {
    static var sampleRecords: [ScanRecord] {
        let patients = Patient.samplePatients

        return [
            ScanRecord(
                patient: patients[0],
                analysisResults: AnalysisResults(
                    ejectionFraction: 65.2,
                    efConfidence: 0.94,
                    edvMl: 120,
                    esvMl: 42,
                    lviddCm: 5.0,
                    lvidsCm: 3.1,
                    ivsdCm: 0.9,
                    lvpwdCm: 0.9,
                    tapseMm: 22,
                    segmentationResults: AnalysisResults.SegmentationData(
                        leftVentricleArea: 12.5,
                        rightVentricleArea: 8.3,
                        atriumArea: 15.2,
                        confidence: 0.91
                    ),
                    measurements: [
                        AnalysisResults.Measurement(
                            type: .ejectionFraction, value: 65.2, unit: "%"),
                        AnalysisResults.Measurement(type: .heartRate, value: 72, unit: "bpm"),
                    ],
                    aiModelVersion: "v2.1.0",
                    processingTime: 2.3
                ),
                imageData: ImageData(
                    thumbnailPath: "scan_thumb_001.jpg",
                    fullImagePath: "scan_full_001.jpg",
                    videoPath: "scan_video_001.mp4"
                ),
                clinicalNotes: "Normal cardiac function observed. Good image quality.",
                scanDuration: 45.0
            ),
            ScanRecord(
                patient: patients[1],
                analysisResults: AnalysisResults(
                    ejectionFraction: 58.7,
                    efConfidence: 0.87,
                    edvMl: 110,
                    esvMl: 46,
                    lviddCm: 4.8,
                    lvidsCm: 3.2,
                    ivsdCm: 0.8,
                    lvpwdCm: 0.9,
                    tapseMm: 19,
                    segmentationResults: nil,
                    measurements: [
                        AnalysisResults.Measurement(type: .ejectionFraction, value: 58.7, unit: "%")
                    ],
                    aiModelVersion: "v2.1.0",
                    processingTime: 3.1
                ),
                imageData: ImageData(
                    thumbnailPath: "scan_thumb_002.jpg",
                    fullImagePath: "scan_full_002.jpg"
                ),
                clinicalNotes: "Slightly reduced EF. Recommend follow-up.",
                scanDuration: 62.0
            ),
        ]
    }
}
