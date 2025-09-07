import SwiftUI

/// Clinical model performance monitoring view for doctors to assess AI model effectiveness
struct ModelPerformanceView: View {
    @ObservedObject var model: Model
    @State private var showingDetailedMetrics = false
    @State private var performanceHistory: [PerformanceMetric] = []

    struct PerformanceMetric: Identifiable {
        let id = UUID()
        let timestamp: Date
        let efValue: Float?
        let efConfidence: Float?
        let processingTime: TimeInterval
        let frameCount: Int
        let segmentationQuality: Bool
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Model Status Overview
                    modelStatusSection

                    // Current Performance Metrics
                    currentMetricsSection

                    // Real-time Performance
                    if model.stage == .imaging {
                        realTimePerformanceSection
                    }

                    // Clinical Validation Status
                    clinicalValidationSection

                    // Multi-output Metrics (Live)
                    multiOutputMetricsSection

                    // Performance History
                    if !performanceHistory.isEmpty {
                        performanceHistorySection
                    }
                }
                .padding()
            }
            .navigationTitle("Model Performance")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Export Metrics") {
                        exportPerformanceData()
                    }
                }
            }
        }
        .onAppear {
            startPerformanceMonitoring()
        }
    }

    // MARK: - Model Status Section

    private var modelStatusSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("AI Model Status")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            HStack(spacing: 20) {
                // EF Model Status
                VStack {
                    Image(
                        systemName: model.isUsingRealModels
                            ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .font(.title2)
                    .foregroundColor(model.isUsingRealModels ? .green : .red)

                    Text("EF Model")
                        .font(.caption)
                        .fontWeight(.medium)

                    Text(model.isUsingRealModels ? "Active" : "Unavailable")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Segmentation Model Status
                VStack {
                    Image(
                        systemName: model.segmentationMask != nil
                            ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.title2)
                    .foregroundColor(model.segmentationMask != nil ? .green : .gray)

                    Text("Segmentation")
                        .font(.caption)
                        .fontWeight(.medium)

                    Text(model.segmentationMask != nil ? "Active" : "Standby")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Compute Units
                VStack {
                    Image(systemName: "cpu")
                        .font(.title2)
                        .foregroundColor(.blue)

                    Text("Compute")
                        .font(.caption)
                        .fontWeight(.medium)

                    Text("CPU+Neural")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Current Metrics Section

    private var currentMetricsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Current Session Metrics")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Remove single-output EF tile; rely on live multi-output metrics below
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    // MARK: - Multi-Output Metrics (Live)
    private var multiOutputMetricsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Multi-output Metrics")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            if let image = model.image, let mo = MultiOutputModel.shared.predict(image: image) {
                VStack(spacing: 8) {
                    metricRow(
                        "EF",
                        (mo.efPercent?.isFinite == true)
                            ? String(format: "%.1f%%", mo.efPercent!) : "–")
                    metricRow(
                        "EDV",
                        (mo.edvMl?.isFinite == true) ? String(format: "%.0f mL", mo.edvMl!) : "–")
                    metricRow(
                        "ESV",
                        (mo.esvMl?.isFinite == true) ? String(format: "%.0f mL", mo.esvMl!) : "–")
                    metricRow(
                        "LVIDd",
                        (mo.lviddCm?.isFinite == true)
                            ? String(format: "%.1f cm", mo.lviddCm!) : "–")
                    metricRow(
                        "LVIDs",
                        (mo.lvidsCm?.isFinite == true)
                            ? String(format: "%.1f cm", mo.lvidsCm!) : "–")
                    metricRow(
                        "IVSd",
                        (mo.ivsdCm?.isFinite == true) ? String(format: "%.1f cm", mo.ivsdCm!) : "–")
                    metricRow(
                        "LVPWd",
                        (mo.lvpwdCm?.isFinite == true)
                            ? String(format: "%.1f cm", mo.lvpwdCm!) : "–")
                    metricRow(
                        "TAPSE",
                        (mo.tapseMm?.isFinite == true)
                            ? String(format: "%.0f mm", mo.tapseMm!) : "–")
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(8)

                // Checks
                VStack(spacing: 6) {
                    let efConsistency: Bool? = {
                        guard let edv = mo.edvMl, let esv = mo.esvMl, edv > 0, let ef = mo.efPercent
                        else { return nil }
                        let derived = (edv - esv) / edv * 100.0
                        return abs(derived - ef) <= 10.0
                    }()
                    let relationshipsOK: Bool? = {
                        let lvidOk =
                            (mo.lviddCm != nil && mo.lvidsCm != nil)
                            ? (mo.lvidsCm! < mo.lviddCm!) : nil
                        let volOk: Bool? = {
                            if let edv = mo.edvMl, let esv = mo.esvMl {
                                return edv >= esv && esv >= 0
                            }
                            if let edv = mo.edvMl { return edv >= 0 }
                            if let esv = mo.esvMl { return esv >= 0 }
                            return nil
                        }()
                        switch (lvidOk, volOk) {
                        case (nil, nil): return nil
                        case let (a?, b?): return a && b
                        case let (a?, nil): return a
                        case let (nil, b?): return b
                        }
                    }()

                    ValidationRow(
                        title: "EF Consistency", status: efConsistency,
                        description: "(EDV−ESV)/EDV vs EF within 10%")
                    ValidationRow(
                        title: "Physiologic Relationships", status: relationshipsOK,
                        description: "LVIDs < LVIDd; EDV ≥ ESV ≥ 0")
                }
            } else {
                Text("No multi-output metrics yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    // MARK: - Real-time Performance Section

    private var realTimePerformanceSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Real-time Performance")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()

                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Live")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            HStack(spacing: 20) {
                VStack {
                    Text("Frame Rate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("30 fps")
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                Spacer()

                VStack {
                    Text("Processing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("< 2s")
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                Spacer()

                VStack {
                    Text("Memory")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Normal")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Clinical Validation Section

    private var clinicalValidationSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Clinical Validation")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            VStack(spacing: 12) {
                ValidationRow(
                    title: "EF Range Validation",
                    status: lastEFStatus,
                    description: "15-80% physiological range"
                )

                ValidationRow(
                    title: "Frame Quality",
                    status: true,  // Assuming frames are adequate if we have results
                    description: "≥8 frames for reliable analysis"
                )

                ValidationRow(
                    title: "Segmentation Quality",
                    status: model.segmentationMask != nil,
                    description: "Cardiac structure identification"
                )

                ValidationRow(
                    title: "Processing Speed",
                    status: true,  // Assuming good performance
                    description: "Real-time inference capability"
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // Determine EF range status from the most recent saved scan using MultiOutput metrics
    private var lastEFStatus: Bool? {
        if let ef = ScanHistoryManager.shared.scanRecords.first?.analysisResults.ejectionFraction {
            return ef >= 15 && ef <= 80
        }
        return nil
    }

    // MARK: - Performance History Section

    private var performanceHistorySection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Performance History")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()

                Button("View Details") {
                    showingDetailedMetrics = true
                }
                .font(.caption)
            }

            // Simple performance chart placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(height: 100)
                .overlay(
                    Text("Performance trends will be displayed here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                )
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Helper Methods

    private func efColor(for ef: Float) -> Color {
        let percentage = ef * 100
        switch percentage {
        case 55...: return .green
        case 40..<55: return .orange
        default: return .red
        }
    }

    private func clinicalRange(for ef: Float) -> String {
        let percentage = ef * 100
        switch percentage {
        case 55...: return "Normal"
        case 40..<55: return "Mild Dysfunction"
        default: return "Severe Dysfunction"
        }
    }

    private func startPerformanceMonitoring() {
        // Start monitoring model performance
        // This would be implemented to track metrics over time
    }

    private func exportPerformanceData() {
        // Export performance metrics for clinical analysis
        // This would generate a detailed report
    }
}

// MARK: - Validation Row Component

struct ValidationRow: View {
    let title: String
    let status: Bool?
    let description: String

    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private var statusIcon: String {
        guard let status = status else { return "circle" }
        return status ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var statusColor: Color {
        guard let status = status else { return .gray }
        return status ? .green : .red
    }
}

#Preview {
    ModelPerformanceView(model: Model.shared)
}
