import ButterflyImagingKit
import SwiftUI

// MARK: - Navigation Enum
enum HomeDestination: Hashable {
    case newScan
    case scanHistory
    case scanDetail(id: String)  // hashable ID for ScanRecord
}

// MARK: - HomeView
struct HomeView: View {
    @ObservedObject var model: Model
    @State private var availablePresets: [ImagingPreset] = []
    @State private var selectedPreset: ImagingPreset?
    @State private var canStartScanning = false

    @StateObject private var patientSession = PatientSessionManager.shared
    @StateObject private var scanHistory = ScanHistoryManager.shared

    var body: some View {
        NavigationStack {
            List {
                // Device & AI Status
                Section {
                    deviceAndAIStatusCard
                } header: {
                    Text("Device & AI Status")
                }

                // Navigation Links
                Section {
                    NavigationLink(value: HomeDestination.newScan) {
                        ListActionRow(
                            icon: "plus.circle.fill",
                            title: "New Scan",
                            subtitle: "Start cardiac scanning",
                            color: .blue,
                            isEnabled: true
                        )
                    }

                    NavigationLink(value: HomeDestination.scanHistory) {
                        ListActionRow(
                            icon: "clock.arrow.circlepath",
                            title: "Scan History",
                            subtitle: "\(scanHistory.scanRecords.count) scans available",
                            color: .purple,
                            isEnabled: true
                        )
                    }
                }

                // Recent Scans
                Section {
                    if scanHistory.scanRecords.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "heart.text.square")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Text("No scans yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Start your first scan to see results here")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(Array(scanHistory.scanRecords.prefix(3)), id: \.id) { scan in
                            NavigationLink(
                                value: HomeDestination.scanDetail(id: String(describing: scan.id))
                            ) {
                                recentScanRow(scan)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        if scanHistory.scanRecords.count > 3 {
                            NavigationLink(value: HomeDestination.scanHistory) {
                                HStack {
                                    Text("View All").foregroundColor(.blue)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                } header: {
                    Text("Recent Scans")
                }
            }
            .navigationTitle("HeartScanner")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await refreshDeviceStatus() }
            .onAppear { setupHomeView() }
            .onChange(of: model.probe?.state) { _ in updateCanStartScanning() }
            .onChange(of: model.availablePresets) { _ in
                availablePresets = model.availablePresets
                updateCanStartScanning()
            }
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .newScan:
                    PatientEntryView()
                case .scanHistory:
                    ScanHistoryView()
                case .scanDetail(let id):
                    if let record = scanHistory.scanRecords.first(where: {
                        String(describing: $0.id) == id
                    }) {
                        ScanDetailView(scanRecord: record)
                    } else {
                        Text("Scan not found").foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Device & AI Status Card
    private var deviceAndAIStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "stethoscope")
                    .font(.title2)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(systemStatusTitle).font(.headline).fontWeight(.semibold)
                    Text(systemStatusSubtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Circle()
                    .fill(systemStatusColor)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(systemStatusColor.opacity(0.3), lineWidth: 4)
                            .scaleEffect(1.5)
                    )
            }
            Divider()
            VStack(spacing: 8) {
                statusRow(
                    "Butterfly Probe", value: probeConnectionStatus, color: probeConnectionColor)
                statusRow("AI Models", value: aiModelStatus, color: aiModelColor)
                statusRow("License", value: licenseStatusText, color: licenseStatusColor)
                if !availablePresets.isEmpty {
                    statusRow(
                        "Imaging Presets", value: "\(availablePresets.count) available",
                        color: .blue)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func statusRow(_ title: String, value: String, color: Color) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.medium).foregroundColor(color)
        }
    }

    private func recentScanRow(_ scan: ScanRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(scan.patient?.patientID ?? "Anonymous")
                    .font(.headline).fontWeight(.medium)
                Text(scan.scanDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if let ef = scan.analysisResults.ejectionFraction {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("EF").font(.caption2).foregroundColor(.secondary)
                    Text("\(String(format: "%.1f", ef))%")
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Computed Status
    private var systemStatusTitle: String {
        if canStartScanning {
            "System Ready"
        } else if model.probe?.state == .disconnected {
            "Probe Disconnected"
        } else {
            "System Starting"
        }
    }

    private var systemStatusSubtitle: String {
        if canStartScanning {
            "Ready for cardiac scanning"
        } else if model.probe?.state == .disconnected {
            "Connect Butterfly probe"
        } else {
            "Initializing components..."
        }
    }

    private var systemStatusColor: Color {
        if canStartScanning {
            .green
        } else if model.probe?.state == .disconnected {
            .red
        } else {
            .orange
        }
    }

    private var aiModelStatus: String {
        model.isUsingRealModels ? "Clinical Ready" : "Simulation Mode"
    }
    private var aiModelColor: Color { model.isUsingRealModels ? .green : .orange }

    private var probeConnectionStatus: String {
        guard let probe = model.probe else { return "No Probe" }
        switch probe.state {
        case .connected: return probe.isSimulated ? "Simulated" : "Connected"
        case .disconnected: return "Disconnected"
        case .hardwareIncompatible: return "Incompatible"
        case .firmwareIncompatible: return "Update Required"
        default: return "Unknown"
        }
    }

    private var probeConnectionColor: Color {
        guard let probe = model.probe else { return .red }
        switch probe.state {
        case .connected: return probe.isSimulated ? .orange : .green
        case .disconnected: return .red
        case .hardwareIncompatible, .firmwareIncompatible: return .red
        default: return .gray
        }
    }

    private var licenseStatusText: String {
        switch model.licenseState {
        case .valid: return "Valid"
        case .invalid: return "Invalid"
        case .validUntil(_): return "Valid"
        @unknown default: return "Unknown"
        }
    }

    private var licenseStatusColor: Color {
        switch model.licenseState {
        case .valid: return .green
        case .invalid: return .red
        case .validUntil(_): return .green
        @unknown default: return .gray
        }
    }

    // MARK: - Actions
    private func setupHomeView() {
        availablePresets = model.availablePresets
        if selectedPreset == nil && !availablePresets.isEmpty {
            selectedPreset = availablePresets.first
        }
        updateCanStartScanning()
    }

    private func updateCanStartScanning() {
        canStartScanning = model.probe?.state == .connected
    }

    private func refreshDeviceStatus() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView(model: Model.shared)
    }
}
