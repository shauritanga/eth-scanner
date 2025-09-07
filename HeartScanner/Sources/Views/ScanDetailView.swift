import SwiftUI
import UIKit

/// Detailed view for individual scan records
struct ScanDetailView: View {
    let scanRecord: ScanRecord
    @Environment(\.dismiss) private var dismiss
    @State private var showingExportOptions = false
    @State private var editingNotes = false
    @State private var clinicalNotes: String
    // Lazy metrics populated on appear if missing from stored record
    @State private var lazyMultiOut: MultiOutputModel.Outputs? = nil

    // Computed display results combining stored and lazy-inferred metrics
    private var displayResults: ScanRecord.AnalysisResults {
        mergeResults(scanRecord.analysisResults, with: lazyMultiOut)
    }

    // Helpers
    private var needsLazyMetrics: Bool {
        let r = scanRecord.analysisResults
        return r.ejectionFraction == nil
            || [r.edvMl, r.esvMl, r.lviddCm, r.lvidsCm, r.ivsdCm, r.lvpwdCm, r.tapseMm].allSatisfy {
                $0 == nil
            }
    }

    private func loadFullImage() -> UIImage? {
        let url = MediaManager.shared.getMediaURL(for: scanRecord.imageData.fullImagePath)
        return UIImage(contentsOfFile: url.path)
    }

    private func mergeResults(
        _ base: ScanRecord.AnalysisResults, with lazy: MultiOutputModel.Outputs?
    ) -> ScanRecord.AnalysisResults {
        guard let lazy = lazy else { return base }
        return ScanRecord.AnalysisResults(
            ejectionFraction: base.ejectionFraction ?? lazy.efPercent,
            efConfidence: base.efConfidence,
            edvMl: base.edvMl ?? lazy.edvMl,
            esvMl: base.esvMl ?? lazy.esvMl,
            lviddCm: base.lviddCm ?? lazy.lviddCm,
            lvidsCm: base.lvidsCm ?? lazy.lvidsCm,
            ivsdCm: base.ivsdCm ?? lazy.ivsdCm,
            lvpwdCm: base.lvpwdCm ?? lazy.lvpwdCm,
            tapseMm: base.tapseMm ?? lazy.tapseMm,
            segmentationResults: base.segmentationResults,
            measurements: base.measurements,
            aiModelVersion: base.aiModelVersion,
            processingTime: base.processingTime
        )
    }

    init(scanRecord: ScanRecord) {
        self.scanRecord = scanRecord
        self._clinicalNotes = State(initialValue: scanRecord.clinicalNotes)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with main image
                headerSection

                // Patient information
                if let patient = scanRecord.patient {
                    patientSection(patient)
                }

                // Analysis results
                analysisSection

                // Quality metrics
                qualitySection

                // Clinical notes
                notesSection

                // Device and technical info
                technicalSection
            }
            .padding()
        }
        .navigationTitle("Scan Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Export") {
                    showingExportOptions = true
                }
            }
        }
        .onAppear {
            // If stored record lacks multi-output metrics or EF, attempt lazy inference on the saved full image
            if needsLazyMetrics, let image = loadFullImage() {
                lazyMultiOut = MultiOutputModel.shared.predict(image: image)
            }
        }

        .sheet(isPresented: $showingExportOptions) {
            ExportOptionsView(scans: [scanRecord])
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Media player for photos and videos
            MediaPlayerView(scanRecord: scanRecord)

            // Scan metadata
            HStack {
                VStack(alignment: .leading) {
                    Text(scanRecord.displayTitle)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(scanRecord.formattedDate)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("Quality: \(scanRecord.qualityIndicator)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(qualityColor.opacity(0.2))
                    .foregroundColor(qualityColor)
                    .cornerRadius(4)
            }
        }
    }

    private var qualityColor: Color {
        switch scanRecord.qualityIndicator.lowercased() {
        case "excellent": return .green
        case "good": return .blue
        case "fair": return .orange
        case "poor": return .red
        default: return .gray
        }
    }

    // MARK: - Patient Section

    private func patientSection(_ patient: Patient) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Patient Information", icon: "person.crop.circle")

            VStack(spacing: 8) {
                InfoRow(label: "Patient ID", value: patient.patientID)
                InfoRow(label: "Age", value: "\(patient.age) years")
                InfoRow(label: "Gender", value: patient.gender.displayName)
                InfoRow(label: "Weight", value: String(format: "%.1f kg", patient.weight))
                InfoRow(label: "Height", value: String(format: "%.0f cm", patient.height))
                InfoRow(
                    label: "BMI",
                    value: String(format: "%.1f (%@)", patient.bmi, patient.bmiCategory))
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: - Analysis Section

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Analysis Results", icon: "chart.line.uptrend.xyaxis")

            VStack(spacing: 12) {
                // Primary EF result (use stored or lazy)
                if let ef = displayResults.ejectionFraction {
                    EFResultCard(
                        value: ef,
                        confidence: scanRecord.analysisResults.efConfidence ?? 0.0
                    )
                }

                // Multi-output metrics section (use stored or lazy)
                MultiOutputMetricsSection(results: displayResults)

                // Additional measurements (legacy)
                if !scanRecord.analysisResults.measurements.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(scanRecord.analysisResults.measurements) { measurement in
                            MeasurementRow(measurement: measurement)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Quality Section

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Quality Metrics", icon: "checkmark.seal")

            VStack(spacing: 8) {
                QualityMetricRow(
                    label: "Image Clarity",
                    value: scanRecord.qualityMetrics.imageClarity,
                    color: .blue
                )

                QualityMetricRow(
                    label: "Model Confidence",
                    value: scanRecord.qualityMetrics.modelConfidence,
                    color: .green
                )

                QualityMetricRow(
                    label: "Signal to Noise",
                    value: scanRecord.qualityMetrics.signalToNoise,
                    color: .orange
                )
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Clinical Notes", icon: "note.text")

            VStack(alignment: .leading, spacing: 8) {
                if editingNotes {
                    TextEditor(text: $clinicalNotes)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color(.systemBackground))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )

                    HStack {
                        Button("Cancel") {
                            clinicalNotes = scanRecord.clinicalNotes
                            editingNotes = false
                        }
                        .foregroundColor(.secondary)

                        Spacer()

                        Button("Save") {
                            ScanHistoryManager.shared.updateClinicalNotes(
                                for: scanRecord.id,
                                notes: clinicalNotes
                            )
                            editingNotes = false
                        }
                        .fontWeight(.medium)
                    }
                } else {
                    Text(clinicalNotes.isEmpty ? "No clinical notes" : clinicalNotes)
                        .font(.body)
                        .foregroundColor(clinicalNotes.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .onTapGesture {
                            editingNotes = true
                        }

                    Button("Edit Notes") {
                        editingNotes = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
    }

    // MARK: - Technical Section

    private var technicalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Technical Information", icon: "gear")

            VStack(spacing: 8) {
                InfoRow(label: "Device", value: scanRecord.deviceInfo.deviceName)
                InfoRow(label: "Probe Type", value: scanRecord.deviceInfo.probeType)
                InfoRow(label: "App Version", value: scanRecord.deviceInfo.appVersion)
                InfoRow(
                    label: "Scan Duration",
                    value: String(format: "%.0f seconds", scanRecord.scanDuration))
                InfoRow(label: "File Size", value: scanRecord.fileSizeDescription)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

// MARK: - Supporting Views

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

struct EFResultCard: View {
    let value: Double
    let confidence: Double

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Ejection Fraction")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("\(String(format: "%.1f", value))%")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(efColor)
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("Confidence")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\(String(format: "%.0f", confidence * 100))%")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var efColor: Color {
        switch value {
        case 55...: return .green
        case 40..<55: return .orange
        default: return .red
        }
    }
}

struct MeasurementRow: View {
    let measurement: ScanRecord.AnalysisResults.Measurement

    var body: some View {
        HStack {
            Text(measurement.type.displayName)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(String(format: "%.1f", measurement.value)) \(measurement.unit)")
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

struct MultiOutputMetricsSection: View {
    let results: ScanRecord.AnalysisResults

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasAnyMetric {
                SectionHeader(title: "Chamber and Function", icon: "heart.text.square")
                VStack(spacing: 8) {
                    metricRow("EDV", value: results.edvMl, unit: "mL")
                    metricRow("ESV", value: results.esvMl, unit: "mL")
                    metricRow("LVIDd", value: results.lviddCm, unit: "cm")
                    metricRow("LVIDs", value: results.lvidsCm, unit: "cm")
                    metricRow("IVSd", value: results.ivsdCm, unit: "cm")
                    metricRow("LVPWd", value: results.lvpwdCm, unit: "cm")
                    metricRow("TAPSE", value: results.tapseMm, unit: "mm")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Consistency checks
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Consistency Checks", icon: "checkmark.seal")
                    ForEach(checksSummary, id: \.title) { check in
                        ValidationRow(
                            title: check.title, status: check.status, description: check.description
                        )
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func metricRow(_ label: String, value: Double?, unit: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value.map { String(format: "%.1f %@", $0, unit) } ?? "–")
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private var hasAnyMetric: Bool {
        [
            results.edvMl, results.esvMl, results.lviddCm, results.lvidsCm, results.ivsdCm,
            results.lvpwdCm, results.tapseMm,
        ]
        .contains { $0 != nil }
    }

    private var efConsistency: Bool? {
        guard let edv = results.edvMl, let esv = results.esvMl, edv > 0 else { return nil }
        let efDerived = (edv - esv) / edv * 100.0
        guard let ef = results.ejectionFraction else { return nil }
        return abs(efDerived - ef) <= 10.0  // 10% tolerance
    }

    private var relationshipsOK: Bool? {
        let lvidCheck: Bool? = {
            if let d = results.lviddCm, let s = results.lvidsCm { return s < d }
            return nil
        }()
        let volCheck: Bool? = {
            if let edv = results.edvMl, let esv = results.esvMl { return edv >= esv && esv >= 0 }
            if let edv = results.edvMl { return edv >= 0 }
            if let esv = results.esvMl { return esv >= 0 }
            return nil
        }()
        switch (lvidCheck, volCheck) {
        case (nil, nil): return nil
        case let (a?, b?): return a && b
        case let (a?, nil): return a
        case let (nil, b?): return b
        }
    }

    private var checksSummary: [(title: String, status: Bool?, description: String)] {
        [
            ("EF Consistency", efConsistency, "(EDV−ESV)/EDV vs EF within 10%"),
            ("Physiologic Relationships", relationshipsOK, "LVIDs < LVIDd; EDV ≥ ESV ≥ 0"),
        ]
    }
}

struct QualityMetricRow: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            HStack(spacing: 8) {
                ProgressView(value: value)
                    .progressViewStyle(LinearProgressViewStyle(tint: color))
                    .frame(width: 60)

                Text("\(Int(value * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(color)
            }
        }
        .font(.subheadline)
    }
}

struct ScanDetailView_Previews: PreviewProvider {
    static var previews: some View {
        ScanDetailView(scanRecord: ScanRecord.sampleRecords[0])
    }
}
