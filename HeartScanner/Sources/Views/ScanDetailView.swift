import SwiftUI

/// Detailed view for individual scan records
struct ScanDetailView: View {
    let scanRecord: ScanRecord
    @Environment(\.dismiss) private var dismiss
    @State private var showingExportOptions = false
    @State private var editingNotes = false
    @State private var clinicalNotes: String

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
                // Primary EF result
                if let ef = scanRecord.analysisResults.ejectionFraction {
                    EFResultCard(
                        value: ef,
                        confidence: scanRecord.analysisResults.efConfidence ?? 0.0
                    )
                }

                // Additional measurements
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

                // Processing info
                HStack {
                    Text("AI Model: \(scanRecord.analysisResults.aiModelVersion)")
                    Spacer()
                    Text(
                        "Processing: \(String(format: "%.1fs", scanRecord.analysisResults.processingTime))"
                    )
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
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
