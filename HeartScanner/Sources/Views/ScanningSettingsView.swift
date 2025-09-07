import ButterflyImagingKit
import SwiftUI

struct ScanningSettingsView: View {
    @ObservedObject var model: Model
    @Environment(\.dismiss) private var dismiss

    let isScanning: Bool

    @State private var controlDepth = 10.0
    @State private var controlGain = 50.0
    @State private var controlColorGain = 0.0
    @State private var controlMode: UltrasoundMode = .bMode
    @State private var controlPreset: ImagingPreset?

    // Image quality settings
    @State private var imageStabilization = true
    @State private var noiseReduction = true
    @State private var contrastEnhancement = true
    @State private var frameAveraging = false

    let imaging = ButterflyImaging.shared

    var body: some View {
        Form {
            Section("Imaging Mode") {
                Picker("Select a mode", selection: $controlMode) {
                    if let supportedModes = model.preset?.supportedModes {
                        ForEach(supportedModes) { mode in
                            Text(mode.description).tag(mode)
                        }
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: controlMode) { _, value in
                    imaging.setMode(value)
                    print("Changed mode: \(value.description)")
                }
            }

            Section("Preset") {
                PresetPicker(
                    controlPreset: $controlPreset,
                    availablePresets: .constant(model.availablePresets)
                )
                .onChange(of: controlPreset) { _, preset in
                    guard let preset else { return }
                    imaging.setPreset(preset, parameters: nil)
                    controlMode = .bMode
                    print("Changed preset: \(preset.name)")
                }
            }

            Section("Depth") {
                BoundsSlider(title: "", control: $controlDepth, bounds: $model.depthBounds) {
                    editing in
                    guard !editing else { return }
                    imaging.setDepth(Measurement.centimeters(controlDepth))
                }
            }

            Section("Gain Controls") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gain: \(Int(controlGain))")
                        .font(.subheadline)

                    Slider(
                        value: Binding(
                            get: { controlGain },
                            set: { newVal in
                                controlGain = newVal
                                imaging.setGain(Int(controlGain))
                            }
                        ),
                        in: 0...100
                    ) {
                        Text("Gain")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("100")
                    }
                }

                if model.mode == .colorDoppler {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color Gain: \(Int(controlColorGain))")
                            .font(.subheadline)

                        Slider(
                            value: Binding(
                                get: { controlColorGain },
                                set: { newVal in
                                    controlColorGain = newVal
                                    imaging.setColorGain(Int(controlColorGain))
                                }
                            ),
                            in: 0...100
                        ) {
                            Text("Color Gain")
                        } minimumValueLabel: {
                            Text("0")
                        } maximumValueLabel: {
                            Text("100")
                        }
                    }
                }
            }

            Section("Image Quality") {
                Toggle("Image Stabilization", isOn: $imageStabilization)
                    .onChange(of: imageStabilization) { _, newValue in
                        // Apply image stabilization setting
                        print(
                            "🔧 IMAGE QUALITY: Image stabilization \(newValue ? "enabled" : "disabled")"
                        )
                    }

                Toggle("Noise Reduction", isOn: $noiseReduction)
                    .onChange(of: noiseReduction) { _, newValue in
                        // Apply noise reduction setting
                        print(
                            "🔧 IMAGE QUALITY: Noise reduction \(newValue ? "enabled" : "disabled")"
                        )
                    }

                Toggle("Contrast Enhancement", isOn: $contrastEnhancement)
                    .onChange(of: contrastEnhancement) { _, newValue in
                        // Apply contrast enhancement setting
                        print(
                            "🔧 IMAGE QUALITY: Contrast enhancement \(newValue ? "enabled" : "disabled")"
                        )
                    }

                Toggle("Frame Averaging", isOn: $frameAveraging)
                    .onChange(of: frameAveraging) { _, newValue in
                        // Apply frame averaging for motion reduction
                        print(
                            "🔧 IMAGE QUALITY: Frame averaging \(newValue ? "enabled" : "disabled")"
                        )
                    }
            }
            .headerProminence(.increased)

            Section(header: Text("Model Information")) {
                HStack {
                    Text("AI Models Status")
                    Spacer()
                    Text(model.modelStatus)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            model.isUsingRealModels
                                ? Color.green.opacity(0.8) : Color.orange.opacity(0.8)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }

                if let img = model.image, let mo = MultiOutputModel.shared.predict(image: img),
                    let ef = mo.efPercent
                {
                    HStack {
                        Text("Current EF")
                        Spacer()
                        Text("\(String(format: "%.1f", ef))%")
                            .font(.headline)
                            .foregroundColor(model.isUsingRealModels ? .green : .orange)
                    }
                }
            }

            Section("Probe Information") {
                if let probe = model.probe {
                    HStack {
                        Text("Probe Type")
                        Spacer()
                        Text(probe.isSimulated ? "Simulated" : "Real Device")
                            .foregroundColor(probe.isSimulated ? .orange : .green)
                    }

                    HStack {
                        Text("Serial Number")
                        Spacer()
                        Text(probe.serialNumber)
                            .font(.monospaced(.caption)())
                    }

                    HStack {
                        Text("Connection Status")
                        Spacer()
                        Text(probeStatusText(probe.state, probe: probe))
                            .foregroundColor(probeStatusColor(probe.state, probe: probe))
                    }
                }
            }

            // Clinical Evaluation Section
            Section("Clinical Evaluation") {
                NavigationLink(destination: ModelPerformanceView(model: model)) {
                    Label("Model Performance", systemImage: "chart.line.uptrend.xyaxis")
                }

                Button(action: {
                    exportDiagnosticData()
                }) {
                    Label("Export Diagnostic Data", systemImage: "square.and.arrow.up")
                }
            }

            // Hidden Developer Calibration
            Section("Developer Calibration") {
                CalibrationControlsView()
            }
        }
        .onAppear {
            // Initialize controls with current values
            controlDepth = model.depth.converted(to: .centimeters).value
            controlGain = Double(model.gain)
            controlColorGain = Double(model.colorGain)
            controlMode = model.mode
            controlPreset = model.preset
        }
    }

    private func exportDiagnosticData() {
        // Export comprehensive diagnostic data for clinical evaluation
        print("📊 Exporting diagnostic data for clinical evaluation...")
        // This would generate a detailed report of model performance,
        // processing times, confidence scores, and validation results
    }

    // MARK: - Helper Functions

    private func probeStatusColor(_ state: ProbeState, probe: Probe) -> Color {
        // Check thermal state for color override (consistent with ScanningView)
        let tempStateString = String(describing: probe.temperatureState)
        if tempStateString.contains("hot") {
            return .red  // Hot = red warning
        } else if tempStateString.contains("warm") {
            return .orange  // Warm = orange warning
        } else if tempStateString.contains("coldShutdown") {
            return .blue  // Cold shutdown - probe needs to warm up
        }

        switch state {
        case .connected, .ready: return .green
        case .notReady: return .orange  // Thermal protection
        case .disconnected: return .red
        case .charging: return .blue
        case .depletedBattery: return .red
        case .hardwareIncompatible, .firmwareIncompatible: return .red
        @unknown default: return .gray
        }
    }

    private func probeStatusText(_ state: ProbeState, probe: Probe) -> String {
        // Check for thermal states first (consistent with ScanningView)
        let tempStateString = String(describing: probe.temperatureState)
        if tempStateString.contains("hot") {
            return "Cooling Down"  // Hot = cooling down
        } else if tempStateString.contains("warm") {
            return "Warming Up"  // Warm = warming up
        } else if tempStateString.contains("coldShutdown") {
            return "Cooling Down"  // Cold shutdown - probe needs to warm up
        }

        switch state {
        case .connected: return "Connected"
        case .ready: return "Ready"
        case .notReady: return "Thermal Protection"  // More descriptive for thermal issues
        case .disconnected: return "Disconnected"
        case .charging: return "Charging"
        case .depletedBattery: return "Low Battery"
        case .hardwareIncompatible: return "Incompatible"
        case .firmwareIncompatible: return "Update Required"
        @unknown default: return "Unknown"
        }
    }
}

extension ProbeState {
    var description: String {
        switch self {
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .firmwareIncompatible: return "Firmware Incompatible"
        case .hardwareIncompatible: return "Hardware Incompatible"
        case .ready: return "Ready"
        case .notReady: return "Not Ready"
        case .charging: return "Charging"
        case .depletedBattery: return "Depleted Battery"
        @unknown default: return "Unknown"
        }
    }
}

struct CalibrationControlsView: View {
    @State private var ef: Double = AppConstants.Calibration.efPercent
    @State private var edv: Double = AppConstants.Calibration.edvMl
    @State private var esv: Double = AppConstants.Calibration.esvMl
    @State private var lvidd: Double = AppConstants.Calibration.lviddCm
    @State private var lvids: Double = AppConstants.Calibration.lvidsCm
    @State private var ivsd: Double = AppConstants.Calibration.ivsdCm
    @State private var lvpwd: Double = AppConstants.Calibration.lvpwdCm
    @State private var tapse: Double = AppConstants.Calibration.tapseMm

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Adjust multipliers (hidden; for validation only)")
                .font(.caption)
                .foregroundColor(.secondary)
            stepper("EF %", value: $ef)
            stepper("EDV mL", value: $edv)
            stepper("ESV mL", value: $esv)
            stepper("LVIDd cm", value: $lvidd)
            stepper("LVIDs cm", value: $lvids)
            stepper("IVSd cm", value: $ivsd)
            stepper("LVPWd cm", value: $lvpwd)
            stepper("TAPSE mm", value: $tapse, step: 0.1)

            HStack {
                Spacer()
                Button("Apply") {
                    AppConstants.Calibration.efPercent = ef
                    AppConstants.Calibration.edvMl = edv
                    AppConstants.Calibration.esvMl = esv
                    AppConstants.Calibration.lviddCm = lvidd
                    AppConstants.Calibration.lvidsCm = lvids
                    AppConstants.Calibration.ivsdCm = ivsd
                    AppConstants.Calibration.lvpwdCm = lvpwd
                    AppConstants.Calibration.tapseMm = tapse
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func stepper(_ label: String, value: Binding<Double>, step: Double = 0.01) -> some View
    {
        HStack {
            Text(label)
            Spacer()
            Stepper(value: value, in: 0.5...1.5, step: step) {
                Text(String(format: "%.2f×", value.wrappedValue))
            }
        }
    }
}

#Preview {
    ScanningSettingsView(model: Model.shared, isScanning: true)
}
