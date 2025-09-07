import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// Media player view for displaying photos and videos from scan records
struct MediaPlayerView: View {
    let scanRecord: ScanRecord
    @State private var selectedMediaType: MediaType = .photo
    @State private var showingFullScreenPlayer = false
    @State private var player: AVPlayer?
    @State private var playerItemObserver: NSKeyValueObservation?
    @State private var playerError: String?
    @State private var showControls: Bool = false

    enum MediaType: String, CaseIterable {
        case photo = "Photo"
        case video = "Video"

        var icon: String {
            switch self {
            case .photo: return "photo"
            case .video: return "video"
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Media type selector
            if hasVideo {
                Picker("Media Type", selection: $selectedMediaType) {
                    ForEach(MediaType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
            }

            // Media content
            Group {
                switch selectedMediaType {
                case .photo:
                    photoView
                case .video:
                    videoView
                }
            }
            .frame(height: 320)
            .background(Color.black)
            .cornerRadius(12)
            .clipped()

            // Media info
            mediaInfoView
        }
        .onAppear {
            // Default to Video if available
            if hasVideo { selectedMediaType = .video }
            setupPlayer()
        }
        .onChange(of: selectedMediaType) { _ in
            if selectedMediaType == .video {
                setupPlayer()
            }
        }
        .onChange(of: scanRecord.imageData.videoPath) { _ in
            // If the video becomes available later (record saved after view appears), set up the player
            if selectedMediaType == .video {
                setupPlayer()
            }
        }
        .onDisappear {
            cleanupPlayer()
        }
        .fullScreenCover(isPresented: $showingFullScreenPlayer) {
            if selectedMediaType == .video, let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            }
        }
    }

    // MARK: - Photo View

    private var photoView: some View {
        Group {
            if let image = loadFullImage() {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .onTapGesture {
                        // Could add full-screen photo viewer here
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("Photo not available")
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Video View

    private var videoView: some View {
        Group {
            if hasVideo, let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.isMuted = true
                        player.play()
                    }
                    .onTapGesture {
                        // Toggle play/pause
                        if player.timeControlStatus == .playing {
                            player.pause()
                        } else {
                            player.play()
                        }
                    }
                    .overlay(
                        // Play/Pause overlay that auto-shows on pause and hides on play
                        Group {
                            if player.timeControlStatus != .playing {
                                Button(action: {
                                    if player.timeControlStatus == .playing {
                                        player.pause()
                                    } else {
                                        player.play()
                                    }
                                }) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 56))
                                        .foregroundColor(.white)
                                        .shadow(radius: 6)
                                }
                                .buttonStyle(.plain)
                                .transition(.opacity)
                            }
                        }
                    )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("Video not available")
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Media Info View

    private var mediaInfoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Scan Date", systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(scanRecord.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if selectedMediaType == .video && hasVideo {
                HStack {
                    Label("Duration", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatDuration(scanRecord.scanDuration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Label("Quality", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(scanRecord.qualityIndicator)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let ef = scanRecord.analysisResults.ejectionFraction {
                HStack {
                    Label("EF Result", systemImage: "heart")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(String(format: "%.1f", ef))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }

    // MARK: - Helper Properties

    private var hasVideo: Bool {
        guard let path = scanRecord.imageData.videoPath else { return false }
        let exists = MediaManager.shared.mediaFileExists(path)
        if !exists {
            // Fallback: check if the file exists with or without an accidental double extension
            let url = MediaManager.shared.getMediaURL(for: path)
            let alt1 = url.deletingPathExtension().appendingPathExtension("mp4")
            if FileManager.default.fileExists(atPath: alt1.path) {
                return true
            }
        }
        return exists
    }

    // MARK: - Helper Methods

    private func setupPlayer() {
        guard hasVideo, let videoPath = scanRecord.imageData.videoPath else { return }

        let videoURL = MediaManager.shared.getMediaURL(for: videoPath)
        let size = MediaManager.shared.getFileSize(for: videoPath)
        let asset = AVAsset(url: videoURL)
        let duration = CMTimeGetSeconds(asset.duration)
        let trackCount = asset.tracks(withMediaType: .video).count
        print(
            "📺 MediaPlayerView: Setting up player for \(videoPath), size=\(size) bytes, duration=\(String(format: "%.2f", duration))s, videoTracks=\(trackCount), playable=\(asset.isPlayable)"
        )

        let item = AVPlayerItem(asset: asset)
        playerItemObserver?.invalidate()
        playerItemObserver = item.observe(\.status, options: [.initial, .new]) { item, _ in
            switch item.status {
            case .readyToPlay:
                print("📺 AVPlayerItem: readyToPlay")
                DispatchQueue.main.async {
                    self.player?.isMuted = true
                    self.player?.play()
                }
            case .failed:
                print("❌ AVPlayerItem failed: \(item.error?.localizedDescription ?? "unknown")")
            case .unknown:
                print("⚠️ AVPlayerItem status unknown")
            @unknown default:
                break
            }
        }

        player = AVPlayer(playerItem: item)
        player?.automaticallyWaitsToMinimizeStalling = false

        // Set up player for looping
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,

            queue: .main
        ) { _ in
            self.player?.seek(to: .zero)
            self.player?.play()
        }
    }

    private func cleanupPlayer() {
        player?.pause()
        player = nil
        NotificationCenter.default.removeObserver(self)
    }

    private func loadFullImage() -> UIImage? {
        let imagePath = scanRecord.imageData.fullImagePath
        let imageURL = MediaManager.shared.getMediaURL(for: imagePath)

        guard MediaManager.shared.mediaFileExists(imagePath) else {
            return nil
        }

        return UIImage(contentsOfFile: imageURL.path)
    }

    private func loadThumbnail() -> UIImage? {
        let thumbnailPath = scanRecord.imageData.thumbnailPath
        let thumbnailURL = MediaManager.shared.getMediaURL(for: thumbnailPath)

        guard MediaManager.shared.mediaFileExists(thumbnailPath) else {
            return nil
        }

        return UIImage(contentsOfFile: thumbnailURL.path)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview {
    MediaPlayerView(scanRecord: ScanRecord.sampleRecords.first!)
        .padding()
}
