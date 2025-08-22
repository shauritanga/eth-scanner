import AVFoundation
import ButterflyImagingKit
import Foundation
import UIKit

/// Manages video recording, photo capture, and media file storage
class MediaManager: NSObject, ObservableObject {
    static let shared = MediaManager()

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0

    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var currentVideoURL: URL?

    private let documentsDirectory: URL
    private let mediaDirectory: URL

    // Video recording settings
    private let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 640,
        AVVideoHeightKey: 480,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 2_000_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
        ],
    ]

    override init() {
        // Setup directories
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        mediaDirectory = documentsDirectory.appendingPathComponent("Media")

        super.init()

        // Create media directory if it doesn't exist
        createMediaDirectoryIfNeeded()
    }

    // MARK: - Directory Management

    private func createMediaDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(
                at: mediaDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            print("📁 MediaManager: Media directory created/verified at \(mediaDirectory.path)")
        } catch {
            print("❌ MediaManager: Failed to create media directory: \(error)")
        }
    }

    // MARK: - Video Recording

    /// Start video recording from ultrasound stream
    func startVideoRecording() -> Bool {
        guard !isRecording else {
            print("⚠️ MediaManager: Already recording")
            return false
        }

        // Generate unique filename
        let timestamp = DateFormatter.filenameDateFormatter.string(from: Date())
        let filename = "scan_video_\(timestamp).mp4"
        currentVideoURL = mediaDirectory.appendingPathComponent(filename)

        guard let videoURL = currentVideoURL else {
            print("❌ MediaManager: Failed to create video URL")
            return false
        }

        do {
            // Setup video writer
            videoWriter = try AVAssetWriter(outputURL: videoURL, fileType: .mp4)

            // Setup video input
            videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoWriterInput?.expectsMediaDataInRealTime = true

            // Setup pixel buffer adaptor
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 640,
                kCVPixelBufferHeightKey as String: 480,
            ]

            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoWriterInput!,
                sourcePixelBufferAttributes: pixelBufferAttributes
            )

            // Add input to writer
            if let input = videoWriterInput, videoWriter?.canAdd(input) == true {
                videoWriter?.add(input)
            } else {
                throw MediaError.failedToAddVideoInput
            }

            // Start writing
            if videoWriter?.startWriting() == true {
                videoWriter?.startSession(atSourceTime: .zero)

                // Update state
                isRecording = true
                recordingStartTime = Date()
                recordingDuration = 0

                // Start timer for duration tracking
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    if let startTime = self.recordingStartTime {
                        self.recordingDuration = Date().timeIntervalSince(startTime)
                    }
                }

                print("🎥 MediaManager: Started video recording to \(filename)")
                return true
            } else {
                throw MediaError.failedToStartWriting
            }

        } catch {
            print("❌ MediaManager: Failed to start video recording: \(error)")
            cleanup()
            return false
        }
    }

    /// Stop video recording
    func stopVideoRecording() -> URL? {
        guard isRecording else {
            print("⚠️ MediaManager: Not currently recording")
            return nil
        }

        // Stop timer
        recordingTimer?.invalidate()
        recordingTimer = nil

        // Finish writing
        videoWriterInput?.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        var finalURL: URL?

        videoWriter?.finishWriting { [weak self] in
            if self?.videoWriter?.status == .completed {
                finalURL = self?.currentVideoURL
                print("🎥 MediaManager: Video recording completed successfully")
            } else {
                print(
                    "❌ MediaManager: Video recording failed: \(self?.videoWriter?.error?.localizedDescription ?? "Unknown error")"
                )
            }
            semaphore.signal()
        }

        // Wait for completion (with timeout)
        _ = semaphore.wait(timeout: .now() + 5.0)

        // Update state
        isRecording = false
        recordingDuration = 0
        recordingStartTime = nil

        // Cleanup
        cleanup()

        return finalURL
    }

    /// Add frame to video recording
    func addFrameToRecording(_ image: UIImage) {
        guard isRecording,
            let pixelBufferAdaptor = pixelBufferAdaptor,
            let videoWriterInput = videoWriterInput,
            videoWriterInput.isReadyForMoreMediaData
        else {
            return
        }

        // Convert UIImage to CVPixelBuffer
        guard let pixelBuffer = image.toCVPixelBuffer() else {
            print("⚠️ MediaManager: Failed to convert image to pixel buffer")
            return
        }

        // Calculate presentation time
        let currentTime = Date()
        let elapsedTime = recordingStartTime.map { currentTime.timeIntervalSince($0) } ?? 0
        let presentationTime = CMTime(seconds: elapsedTime, preferredTimescale: 600)

        // Append pixel buffer
        if !pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            print("⚠️ MediaManager: Failed to append pixel buffer to video")
        }
    }

    private func cleanup() {
        videoWriter = nil
        videoWriterInput = nil
        pixelBufferAdaptor = nil
        currentVideoURL = nil
    }

    // MARK: - Photo Capture

    /// Save photo with patient data
    func savePhoto(_ image: UIImage, patient: Patient?) -> (
        thumbnailPath: String, fullImagePath: String
    )? {
        let timestamp = DateFormatter.filenameDateFormatter.string(from: Date())
        let patientPrefix = patient?.patientID ?? "anonymous"

        let thumbnailFilename = "scan_thumb_\(patientPrefix)_\(timestamp).jpg"
        let fullImageFilename = "scan_full_\(patientPrefix)_\(timestamp).jpg"

        let thumbnailURL = mediaDirectory.appendingPathComponent(thumbnailFilename)
        let fullImageURL = mediaDirectory.appendingPathComponent(fullImageFilename)

        do {
            // Create thumbnail (200x150)
            let thumbnailSize = CGSize(width: 200, height: 150)
            guard let thumbnail = image.resized(to: thumbnailSize) else {
                throw MediaError.failedToCreateThumbnail
            }

            // Save thumbnail
            if let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) {
                try thumbnailData.write(to: thumbnailURL)
            } else {
                throw MediaError.failedToCreateThumbnail
            }

            // Save full image
            if let fullImageData = image.jpegData(compressionQuality: 0.9) {
                try fullImageData.write(to: fullImageURL)
            } else {
                throw MediaError.failedToSaveFullImage
            }

            print("📸 MediaManager: Saved photo for patient \(patientPrefix)")
            return (thumbnailPath: thumbnailFilename, fullImagePath: fullImageFilename)

        } catch {
            print("❌ MediaManager: Failed to save photo: \(error)")
            return nil
        }
    }

    // MARK: - File Management

    /// Get URL for media file
    func getMediaURL(for filename: String) -> URL {
        return mediaDirectory.appendingPathComponent(filename)
    }

    /// Check if media file exists
    func mediaFileExists(_ filename: String) -> Bool {
        let url = getMediaURL(for: filename)
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Delete media file
    func deleteMediaFile(_ filename: String) -> Bool {
        let url = getMediaURL(for: filename)
        do {
            try FileManager.default.removeItem(at: url)
            print("🗑️ MediaManager: Deleted media file \(filename)")
            return true
        } catch {
            print("❌ MediaManager: Failed to delete media file \(filename): \(error)")
            return false
        }
    }

    /// Get file size for media file
    func getFileSize(for filename: String) -> Int64 {
        let url = getMediaURL(for: filename)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
}

// MARK: - Media Errors

enum MediaError: LocalizedError {
    case failedToAddVideoInput
    case failedToStartWriting
    case failedToCreateThumbnail
    case failedToSaveFullImage

    var errorDescription: String? {
        switch self {
        case .failedToAddVideoInput:
            return "Failed to add video input to writer"
        case .failedToStartWriting:
            return "Failed to start video writing"
        case .failedToCreateThumbnail:
            return "Failed to create image thumbnail"
        case .failedToSaveFullImage:
            return "Failed to save full resolution image"
        }
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}
