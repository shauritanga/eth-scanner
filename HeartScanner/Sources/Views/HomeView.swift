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

                // Thermal Diagnostic (only show when probe is in thermal protection)
                if model.probe?.state == .notReady {
                    Section {
                        thermalDiagnosticCard
                    } header: {
                        Text("🔧 Thermal Diagnostic")
                    }
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

        // Check for thermal states first (consistent with ScanningView)
        let tempStateString = String(describing: probe.temperatureState)
        if tempStateString.contains("hot") {
            return "Cooling Down"  // Hot = cooling down
        } else if tempStateString.contains("warm") {
            return "Warming Up"  // Warm = warming up
        } else if tempStateString.contains("coldShutdown") {
            return probe.isSimulated ? "Simulated Ready" : "Ready"  // SDK BUG: coldShutdown at normal temp
        }

        switch probe.state {
        case .connected: return probe.isSimulated ? "Simulated" : "Connected"
        case .ready: return probe.isSimulated ? "Simulated Ready" : "Ready"
        case .notReady: return "Thermal Protection"  // More descriptive for thermal issues
        case .disconnected: return "Disconnected"
        case .charging: return "Charging"
        case .depletedBattery: return "Low Battery"
        case .hardwareIncompatible: return "Incompatible"
        case .firmwareIncompatible: return "Update Required"
        @unknown default: return "Unknown"
        }
    }

    private var probeConnectionColor: Color {
        guard let probe = model.probe else { return .red }

        // Check thermal state for color override (consistent with ScanningView)
        let tempStateString = String(describing: probe.temperatureState)
        if tempStateString.contains("hot") {
            return .red  // Hot = red warning
        } else if tempStateString.contains("warm") {
            return .orange  // Warm = orange warning
        } else if tempStateString.contains("coldShutdown") {
            return probe.isSimulated ? .orange : .green  // SDK BUG: coldShutdown at normal temp
        }

        switch probe.state {
        case .connected: return probe.isSimulated ? .orange : .green
        case .ready: return probe.isSimulated ? .orange : .green
        case .notReady: return .orange  // Thermal protection
        case .disconnected: return .red
        case .charging: return .blue
        case .depletedBattery: return .red
        case .hardwareIncompatible, .firmwareIncompatible: return .red
        @unknown default: return .gray
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
        guard let probe = model.probe else {
            print("🔧 HOME CAN START: No probe available")
            canStartScanning = false
            return
        }

        // Match the logic from ScanningView - allow connected, ready, or notReady states
        let probeUsable =
            probe.state == .connected || probe.state == .ready || probe.state == .notReady
        let hasPresets = !availablePresets.isEmpty
        canStartScanning = probeUsable && hasPresets

        print(
            "🔧 HOME CAN START: Probe state: \(probe.state.description), Usable: \(probeUsable), Has presets: \(hasPresets), Can start: \(canStartScanning)"
        )
    }

    private func refreshDeviceStatus() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }

    // MARK: - Thermal Diagnostic Functions

    private var thermalDiagnosticCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "thermometer.medium")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("Thermal Protection Active")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            if let probe = model.probe {
                VStack(alignment: .leading, spacing: 8) {
                    diagnosticRow("Probe State", value: String(describing: probe.state))
                    diagnosticRow(
                        "Temperature State", value: String(describing: probe.temperatureState))
                    diagnosticRow(
                        "Current Temperature",
                        value: String(format: "%.1f°C", probe.estimatedTemperature))
                    diagnosticRow(
                        "Battery Level",
                        value: String(format: "%.0f%%", probe.batteryPercentage * 100))
                    diagnosticRow("Serial Number", value: probe.serialNumber)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Button("🔄 Force Refresh Probe Status") {
                        refreshProbeStatus()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.blue)

                    Button("📋 Print Full Diagnostic") {
                        printThermalDiagnostic()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func diagnosticRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption).fontWeight(.medium)
        }
    }

    private func refreshProbeStatus() {
        print("🔄 FORCE REFRESH: Manually refreshing probe status...")
        // Force a refresh by accessing probe properties
        if let probe = model.probe {
            print(
                "🔧 PROBE REFRESH: State=\(probe.state), Temp=\(probe.estimatedTemperature)°C, TempState=\(probe.temperatureState)"
            )
        }
    }

    private func printThermalDiagnostic() {
        print("=== 🔧 THERMAL DIAGNOSTIC REPORT ===")
        print("Timestamp: \(Date())")

        if let probe = model.probe {
            print("📱 PROBE INFORMATION:")
            print("  - State: \(probe.state)")
            print("  - Temperature State: \(probe.temperatureState)")
            print("  - Current Temperature: \(probe.estimatedTemperature)°C")
            print("  - Unit Relative Temperature: \(probe.unitRelativeTemperature)")
            print("  - Battery: \(String(format: "%.0f%%", probe.batteryPercentage * 100))")
            print("  - Battery State: \(probe.batteryState)")
            print("  - Serial Number: \(probe.serialNumber)")
            print("  - Type: \(probe.type)")
            print("  - Is Simulated: \(probe.isSimulated)")

            print("🔍 THERMAL ANALYSIS:")
            let tempStateString = String(describing: probe.temperatureState)
            if tempStateString.contains("hot") {
                print("  - Status: OVERHEATED - Probe is too hot")
                print("  - Action: Wait for cooling (5-15 minutes)")
            } else if tempStateString.contains("warm") {
                print("  - Status: WARMING - Probe is getting warm")
                print("  - Action: Monitor temperature, consider breaks")
            } else if tempStateString.contains("coldShutdown") {
                print("  - Status: COLD SHUTDOWN - Known SDK bug or cooling recovery")
                print("  - Action: This may be a false positive - try disconnecting/reconnecting")
            } else {
                print("  - Status: NORMAL - Temperature state appears normal")
                print("  - Issue: Probe state is notReady but temperature seems fine")
            }

            print("💡 RECOMMENDATIONS:")
            if probe.estimatedTemperature > 40.0 {
                print(
                    "  - Temperature is high (\(probe.estimatedTemperature)°C) - genuine thermal protection"
                )
                print("  - Disconnect probe and let it cool for 10-15 minutes")
            } else if probe.estimatedTemperature < 35.0 {
                print(
                    "  - Temperature is normal (\(probe.estimatedTemperature)°C) - possible SDK bug"
                )
                print(
                    "  - Try: 1) Disconnect/reconnect probe 2) Restart app 3) Update to SDK 2.0.0")
            } else {
                print("  - Temperature is borderline (\(probe.estimatedTemperature)°C)")
                print("  - Wait 5 minutes and check again")
            }
        } else {
            print("❌ NO PROBE DETECTED")
        }

        print("🔧 APP STATE:")
        print("  - Model Stage: \(model.stage)")
        print("  - License State: \(model.licenseState)")
        print("  - Available Presets: \(model.availablePresets.count)")

        print("=== END DIAGNOSTIC REPORT ===")
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView(model: Model.shared)
    }
}
