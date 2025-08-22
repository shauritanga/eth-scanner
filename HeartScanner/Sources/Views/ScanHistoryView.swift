import Foundation
import SwiftUI

/// Professional medical-grade scan history interface
struct ScanHistoryView: View, Hashable {
    static func == (lhs: ScanHistoryView, rhs: ScanHistoryView) -> Bool {
        return true  // All instances are considered equal for navigation
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine("ScanHistoryView")
    }
    @StateObject private var historyManager = ScanHistoryManager.shared
    @State private var showingExportOptions = false
    @State private var searchText = ""

    var body: some View {
        List {
            // Statistics section
            if !historyManager.scanRecords.isEmpty {
                Section {
                    statisticsCard
                }
            }

            // Scan records section
            Section {
                if filteredScans.isEmpty {
                    emptyStateView
                } else {
                    ForEach(filteredScans, id: \.id) { scan in
                        NavigationLink(destination: ScanDetailView(scanRecord: scan)) {
                            scanRowView(scan)
                        }
                    }
                    .onDelete(perform: deleteScan)
                }
            } header: {
                if !historyManager.scanRecords.isEmpty {
                    Text("Recent Scans")
                }
            }
        }
        .navigationTitle("Scan History")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search scans...")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Export All", systemImage: "square.and.arrow.up") {
                        showingExportOptions = true
                    }

                    Divider()

                    Button("Clear History", systemImage: "trash", role: .destructive) {
                        historyManager.clearAllScans()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingExportOptions) {
            ExportOptionsView(scans: historyManager.scanRecords)
        }
    }

    // MARK: - Computed Properties

    private var filteredScans: [ScanRecord] {
        if searchText.isEmpty {
            return historyManager.scanRecords
        } else {
            return historyManager.scanRecords.filter { scan in
                scan.patient?.patientID.localizedCaseInsensitiveContains(searchText) == true
                    || scan.scanDate.formatted().localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    // MARK: - iOS-Style Views

    private var statisticsCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                StatCard(title: "Total", value: "\(historyManager.scanRecords.count)", color: .blue)
                StatCard(title: "This Week", value: "3", color: .green)
                StatCard(title: "Avg EF", value: "55%", color: .purple)
            }
        }
        .padding(.vertical, 8)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("No Scans Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Start your first scan to see results here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }

    private func scanRowView(_ scan: ScanRecord) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let thumbnail = loadThumbnail(for: scan) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: scan.imageData.videoPath != nil ? "video" : "photo")
                                .foregroundColor(.gray)
                        )
                }
            }
            .frame(width: 60, height: 45)
            .cornerRadius(8)
            .clipped()

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(scan.patient?.patientID ?? "Anonymous")
                        .font(.headline)

                    // Media type indicator
                    if scan.imageData.videoPath != nil {
                        Image(systemName: "video.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }

                    Spacer()
                    Text(scan.scanDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let ef = scan.analysisResults.ejectionFraction {
                    Text("EF: \(Int(ef))%")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }

                // Quality indicator
                Text("Quality: \(scan.qualityIndicator)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadThumbnail(for scan: ScanRecord) -> UIImage? {
        let thumbnailPath = scan.imageData.thumbnailPath
        let thumbnailURL = MediaManager.shared.getMediaURL(for: thumbnailPath)

        guard MediaManager.shared.mediaFileExists(thumbnailPath) else {
            return nil
        }

        return UIImage(contentsOfFile: thumbnailURL.path)
    }

    private func deleteScan(at offsets: IndexSet) {
        for index in offsets {
            let scan = filteredScans[index]
            historyManager.deleteScan(scan)
        }
    }
}

// MARK: - Supporting Views
struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
}

// MARK: - Preview
struct ScanHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ScanHistoryView()
        }
    }
}
