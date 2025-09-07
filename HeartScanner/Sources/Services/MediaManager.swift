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
    private var lastPresentationTime: CMTime?
    private let minFrameStep = CMTime(value: 1, timescale: 600)
    private let appendQueue = DispatchQueue(label: "MediaManager.appendQueue")
    private var appendedFrameCount: Int = 0

    private let documentsDirectory: URL
    private let mediaDirectory: URL

    // Video recording settings
    private let videoWidth = 640
    private let videoHeight = 480
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
        let filename = "scan_video_\(timestamp).mov"
        currentVideoURL = mediaDirectory.appendingPathComponent(filename)

        guard let videoURL = currentVideoURL else {
            print("❌ MediaManager: Failed to create video URL")
            return false
        }

        do {
            // Setup video writer (.mov container is best supported for H.264 on iOS)
            videoWriter = try AVAssetWriter(outputURL: videoURL, fileType: .mov)

            // Setup video input
            var settings = videoSettings
            settings[AVVideoCodecKey] = AVVideoCodecType.h264
            videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            videoWriterInput?.expectsMediaDataInRealTime = true
            videoWriterInput?.mediaTimeScale = CMTimeScale(600)

            // Setup pixel buffer adaptor
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
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
                lastPresentationTime = .zero
                appendedFrameCount = 0

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

    /// Stop video recording (async completion when writing finishes)
    /// - Parameter completion: called with (final video URL, final duration seconds)
    func stopVideoRecording(completion: @escaping (URL?, TimeInterval) -> Void) {
        guard isRecording else {
            print("⚠️ MediaManager: Not currently recording")
            completion(nil, 0)
            return
        }

        // Stop timer
        recordingTimer?.invalidate()
        recordingTimer = nil

        // Snapshot final duration before we nil out state
        let finalDuration: TimeInterval
        if let start = recordingStartTime {
            finalDuration = Date().timeIntervalSince(start)
        } else {
            finalDuration = recordingDuration
        }

        // Prevent more frames from being queued and flush pending appends
        isRecording = false
        appendQueue.sync { /* drain queued frame appends */  }

        // Finish writing
        if let last = lastPresentationTime {
            videoWriter?.endSession(atSourceTime: last)
        }
        videoWriterInput?.markAsFinished()

        videoWriter?.finishWriting { [weak self] in
            guard let self = self else { return }

            let status = self.videoWriter?.status
            let writerError = self.videoWriter?.error
            let finalURL = status == .completed ? self.currentVideoURL : nil

            DispatchQueue.main.async {
                if status == .completed {
                    var size: Int64 = 0
                    var hasTrack = false
                    if let url = finalURL {
                        let name = url.lastPathComponent
                        size = self.getFileSize(for: name)
                        let asset = AVAsset(url: url)
                        hasTrack = !asset.tracks(withMediaType: .video).isEmpty
                    }
                    print(
                        "🎥 MediaManager: Video recording completed successfully (frames=\(self.appendedFrameCount), size=\(size) bytes, hasVideoTrack=\(hasTrack))"
                    )
                } else {
                    print(
                        "❌ MediaManager: Video recording failed: \(writerError?.localizedDescription ?? "Unknown error")"
                    )
                }

                // Reset duration and start time
                self.recordingDuration = 0
                self.recordingStartTime = nil

                // Cleanup internal writer state
                self.cleanup()

                completion(finalURL, finalDuration)
            }
        }
    }

    /// Add frame to video recording
    func addFrameToRecording(_ image: UIImage) {
        appendQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.isRecording,
                let pixelBufferAdaptor = self.pixelBufferAdaptor,
                let videoWriterInput = self.videoWriterInput
            else { return }

            // Only attempt when input is ready; otherwise drop frame to maintain realtime
            guard videoWriterInput.isReadyForMoreMediaData else { return }

            // Convert UIImage to CVPixelBuffer matching writer dimensions
            let targetSize = CGSize(width: self.videoWidth, height: self.videoHeight)
            guard let pixelBuffer = image.toCVPixelBuffer(targetSize: targetSize) else {
                print("⚠️ MediaManager: Failed to convert image to pixel buffer")
                return
            }

            // Calculate monotonically increasing presentation time
            let currentTime = Date()
            let elapsedTime = self.recordingStartTime.map { currentTime.timeIntervalSince($0) } ?? 0
            var presentationTime = CMTime(seconds: elapsedTime, preferredTimescale: 600)
            if let last = self.lastPresentationTime, presentationTime <= last {
                presentationTime = CMTimeAdd(last, self.minFrameStep)
            }

            // Append pixel buffer
            if !pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                let status = self.videoWriter?.status.rawValue ?? -1
                print(
                    "⚠️ MediaManager: Failed to append pixel buffer to video (status=\(status), time=\(CMTimeGetSeconds(presentationTime)))"
                )
            } else {
                self.lastPresentationTime = presentationTime
                self.appendedFrameCount += 1
            }
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

    // MARK: - Video Thumbnails

    /// Generate and save thumbnail (200x150) and a full-size frame (640x480) for a given video URL.
    /// Returns the relative filenames saved into the Media directory.
    func generateThumbnails(for videoURL: URL) -> (thumbnailPath: String, fullImagePath: String)? {
        let base = videoURL.deletingPathExtension().lastPathComponent
        let thumbName = "video_thumb_\(base).jpg"
        let fullName = "video_frame_\(base).jpg"
        let thumbURL = mediaDirectory.appendingPathComponent(thumbName)
        let fullURL = mediaDirectory.appendingPathComponent(fullName)

        let asset = AVAsset(url: videoURL)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 480)

        do {
            // Capture a frame at 0.5s (or at 0 if shorter)
            let duration = CMTimeGetSeconds(asset.duration)
            let captureTime = CMTime(
                seconds: min(0.5, max(0.0, duration * 0.1)), preferredTimescale: 600)
            let cgImage = try gen.copyCGImage(at: captureTime, actualTime: nil)
            let uiImage = UIImage(cgImage: cgImage)

            // Full image 640x480
            let fullTarget = CGSize(width: 640, height: 480)
            let full = uiImage.resized(to: fullTarget) ?? uiImage
            if let data = full.jpegData(compressionQuality: 0.9) {
                try data.write(to: fullURL)
            }

            // Thumbnail 200x150
            let thumbTarget = CGSize(width: 200, height: 150)
            let thumb = uiImage.resized(to: thumbTarget) ?? uiImage
            if let data = thumb.jpegData(compressionQuality: 0.8) {
                try data.write(to: thumbURL)
            }

            print("🖼️ MediaManager: Generated video thumbnails for \(base)")
            return (thumbnailPath: thumbName, fullImagePath: fullName)
        } catch {
            print("❌ MediaManager: Failed to generate thumbnails for video: \(error)")
            return nil
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
