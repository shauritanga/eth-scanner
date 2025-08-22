import AVFoundation
import AVKit
import SwiftUI

/// Media player view for displaying photos and videos from scan records
struct MediaPlayerView: View {
    let scanRecord: ScanRecord
    @State private var selectedMediaType: MediaType = .photo
    @State private var showingFullScreenPlayer = false
    @State private var player: AVPlayer?
    
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
            .frame(maxHeight: 400)
            .background(Color.black)
            .cornerRadius(12)
            .clipped()
            
            // Media info
            mediaInfoView
        }
        .onAppear {
            setupPlayer()
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
                    .onTapGesture {
                        showingFullScreenPlayer = true
                    }
                    .overlay(
                        // Play button overlay
                        Button(action: {
                            if player.timeControlStatus == .playing {
                                player.pause()
                            } else {
                                player.play()
                            }
                        }) {
                            Image(systemName: player.timeControlStatus == .playing ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .opacity(player.timeControlStatus == .playing ? 0 : 1)
                        .animation(.easeInOut(duration: 0.3), value: player.timeControlStatus)
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
        return scanRecord.imageData.videoPath != nil && 
               MediaManager.shared.mediaFileExists(scanRecord.imageData.videoPath!)
    }
    
    // MARK: - Helper Methods
    
    private func setupPlayer() {
        guard hasVideo, let videoPath = scanRecord.imageData.videoPath else { return }
        
        let videoURL = MediaManager.shared.getMediaURL(for: videoPath)
        player = AVPlayer(url: videoURL)
        
        // Set up player for looping
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            player?.seek(to: .zero)
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
