import ButterflyImagingKit
import SwiftUI

/// Dedicated scanning interface with manual start/stop controls following iOS design guidelines
struct ScanningView: View {
    @ObservedObject var model: Model
    @State private var showingSettings = false
    @State private var showingScanHistory = false
    @State private var availablePresets: [ImagingPreset] = []
    @State private var controlPreset: ImagingPreset?

    // Recording and capture states
    @State private var showingExitConfirmation = false
    @State private var isScanning = false
    @State private var scanDuration: TimeInterval = 0
    @State private var scanTimer: Timer?
    @State private var efTimer: Timer?
    @State private var liveEFPercent: Double?

    @StateObject private var patientSession = PatientSessionManager.shared
    @StateObject private var scanHistory = ScanHistoryManager.shared
    @StateObject private var mediaManager = MediaManager.shared
    @Environment(\.dismiss) private var dismiss

    // Track last captured photo during recording for combined save
    @State private var lastCapturedPhotoData:
        (image: UIImage, imagePaths: (thumbnailPath: String, fullImagePath: String))? = nil
    // Snapshot patient at recording start to ensure we save with the correct patient even if session changes
    @State private var recordingPatient: Patient? = nil

    let imaging = ButterflyImaging.shared

    var body: some View {
        ZStack {
            // Background
            if isScanning {
                // Active Scanning View - Full screen
                activeScanningView
                    .ignoresSafeArea()
            } else {
                // Ready to Scan View - iOS style
                Color(.systemBackground)
                    .ignoresSafeArea()

                readyToScanView
            }

            // UI Overlay
            VStack {
                if isScanning {
                    // Minimal top bar during scanning
                    scanningTopBar

                    Spacer()

                    Spacer()
                } else {
                    // Ready state content with top bar
                    topBar
                    Spacer()
                    readyStateInfo
                    Spacer()
                }

                // Bottom controls with play/pause button
                bottomControls
            }
        }
        .navigationTitle(isScanning ? "" : "Cardiac Scan")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isScanning)
        .toolbar {
            // Always show settings button, both during and before scanning
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Settings") {
                    showingSettings = true
                }
                .foregroundColor(isScanning ? .white : .blue)
            }
        }
        .onAppear {
            setupScanning()
        }
        .onDisappear {
            stopScanningIfActive()
        }
        .onChange(of: model.availablePresets) { _, _ in
            // Update local presets when model presets change
            availablePresets = model.availablePresets
            if controlPreset == nil && !availablePresets.isEmpty {
                // Look for cardiac-related presets first
                let cardiacPreset = availablePresets.first { preset in
                    let name = preset.name.lowercased()
                    return name.contains("cardiac") || name.contains("heart")
                        || name.contains("echo")
                }

                controlPreset = cardiacPreset ?? availablePresets.first
                print("🔧 SCANNING: Auto-selected preset: \(controlPreset?.name ?? "none")")
            }
            print("🔧 SCANNING: Available presets updated: \(availablePresets.count)")
        }
        .onChange(of: model.probe?.state) { _, _ in
            print("🔧 SCANNING: Probe state changed: \(model.probe?.state.description ?? "nil")")
        }
        .onChange(of: model.stage) { oldStage, newStage in
            print("🔧 SCANNING: Model stage changed from \(oldStage) to: \(newStage)")

            if newStage == .imaging && !isScanning {
                print("🔧 SCANNING: Model entered imaging mode, but UI not scanning - syncing...")
                isScanning = true
                scanDuration = 0
                // Start duration timer when model reaches imaging
                scanTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    scanDuration += 0.1
                }
            }

        }
        .fullScreenCover(isPresented: $showingSettings) {
            NavigationView {
                ScanningSettingsView(model: model, isScanning: isScanning)
                    .navigationTitle("Scan Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingSettings = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingScanHistory) {
            NavigationView {
                ScanHistoryView()
                    .navigationTitle("Scan History")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingScanHistory = false
                            }
                        }
                    }
            }
        }
        .alert("Exit Scanning", isPresented: $showingExitConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Exit", role: .destructive) {
                exitScanning()
            }
        } message: {
            Text("Are you sure you want to exit scanning? Any unsaved data will be lost.")
        }
    }

    // MARK: - View Components

    private var activeScanningView: some View {
        ZStack {
            // Ultrasound Image Display
            if let image = model.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .edgesIgnoringSafeArea(.all)
            }

            // Segmentation Overlay
            if let mask = model.segmentationMask {
                Image(uiImage: mask)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(0.7)
                    .edgesIgnoringSafeArea(.all)
                    .accessibilityLabel("Clinical cardiac segmentation overlay")
                    .blendMode(.multiply)
            }
        }
    }

    private var readyToScanView: some View {
        VStack(spacing: 40) {
            // Main status indicator
            VStack(spacing: 20) {
                // Large status icon
                ZStack {
                    Circle()
                        .fill(.blue.opacity(0.1))
                        .frame(width: 120, height: 120)

                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 50, weight: .medium))
                        .foregroundColor(.blue)
                }

                VStack(spacing: 8) {
                    Text("Ready to Scan")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Position probe and tap play to begin")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Device status card
            if let probe = model.probe {
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.blue)

                        Text("Probe Status")
                            .font(.headline)

                        Spacer()

                        HStack(spacing: 6) {
                            Circle()
                                .fill(probeStatusColor(probe.state))
                                .frame(width: 8, height: 8)

                            Text(probeStatusText(probe.state))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(probeStatusColor(probe.state))
                        }
                    }

                    // Home button
                    Button(action: {
                        goToHome()
                    }) {
                        HStack {
                            Image(systemName: "house.fill")
                                .foregroundColor(.white)
                            Text("Go to Home")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Show thermal status if probe has temperature issues
                    let tempStateString = String(describing: probe.temperatureState)
                    if tempStateString.contains("hot") || tempStateString.contains("warm") {
                        HStack {
                            Image(systemName: "thermometer")
                                .foregroundColor(.orange)

                            Text(
                                "Probe temperature: \(String(format: "%.1f", probe.estimatedTemperature))°C - \(String(describing: probe.temperatureState))"
                            )
                            .font(.caption)
                            .foregroundColor(.orange)

                            Spacer()
                        }
                    } else if tempStateString.contains("coldShutdown") {
                        // Cold shutdown - probe needs to warm up
                        HStack {
                            Image(systemName: "thermometer.snowflake")
                                .foregroundColor(.blue)
                            Text("Probe Cooling Down")
                                .foregroundColor(.blue)
                            Spacer()
                        }
                    }

                    if probe.isSimulated {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)

                            Text("Using simulated probe for demonstration")
                                .font(.caption)
                                .foregroundColor(.orange)

                            Spacer()
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
        .padding(.horizontal, 20)
    }

    private var readyStateInfo: some View {
        VStack(spacing: 24) {
            // Patient information card
            if let patient = patientSession.currentPatient {
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)

                        Text("Patient Information")
                            .font(.headline)

                        Spacer()
                    }

                    VStack(spacing: 12) {
                        HStack {
                            Text("Patient ID")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(patient.patientID)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        HStack {
                            Text("Age")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(patient.age) years")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        HStack {
                            Text("Gender")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(patient.gender.rawValue)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
        .padding(.horizontal, 20)
    }

    private var scanningTopBar: some View {
        HStack {
            // Scan duration - moved to left
            if isScanning {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duration")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))

                    Text(formatDuration(scanDuration))
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
            }

            Spacer()

            // Right-side overlay: patient (if any) and live EF
            VStack(alignment: .trailing, spacing: 4) {
                if let patient = patientSession.currentPatient {
                    Text("Patient")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                    Text(patient.patientID)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.9))
                }
                if isScanning {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("EF")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                        Text(
                            liveEFPercent?.isFinite == true
                                ? String(format: "%.1f%%", liveEFPercent!) : "–"
                        )
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .accessibilityLabel("Ejection Fraction")
                    }
                }
            }

            // Control buttons during scanning
            HStack(spacing: 8) {
                // Photo capture button
                Button(action: { capturePhoto() }) {
                    Image(systemName: "camera.fill")
                        .foregroundColor(.white)
                        .font(.title2)
                        .padding(8)
                        .background(.blue.opacity(0.8))
                        .cornerRadius(8)
                }

                // Video recording button
                Button(action: { toggleRecording() }) {
                    Image(
                        systemName: mediaManager.isRecording
                            ? "stop.circle.fill" : "record.circle.fill"
                    )
                    .foregroundColor(mediaManager.isRecording ? .red : .white)
                    .font(.title2)
                    .padding(8)
                    .background(.black.opacity(0.7))
                    .cornerRadius(8)
                }

                // Settings button
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.white)
                        .font(.title2)
                        .padding(8)
                        .background(.black.opacity(0.7))
                        .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {

            // Patient Info Display
            if let patient = patientSession.currentPatient {
                Text("Patient: \(patient.patientID)")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.7))
                    .cornerRadius(4)
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: { showingScanHistory = true }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.white)
                        .font(.title2)
                        .padding(8)
                        .background(.black.opacity(0.7))
                        .cornerRadius(8)
                }

                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.white)
                        .font(.title2)
                        .padding(8)
                        .background(.black.opacity(0.7))
                        .cornerRadius(8)
                }
            }
        }
        .padding(.top)
        .padding(.horizontal)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 20) {
            // Preset selection (only show when not scanning for cleaner UI)
            if !isScanning && !availablePresets.isEmpty {
                VStack(spacing: 12) {
                    HStack {
                        Text("Scan Preset")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }

                    PresetPicker(
                        controlPreset: $controlPreset,
                        availablePresets: $availablePresets
                    )
                    .onChange(of: controlPreset) { _, preset in
                        guard let preset else { return }
                        imaging.setPreset(preset, parameters: nil)
                        print("Changed preset: \(preset.name)")
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 20)
            }

            // Main control buttons
            HStack(spacing: 20) {
                // Save scan button (enabled when an image is available)
                if model.image != nil {
                    Button(action: saveScanToHistory) {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.blue)
                            .cornerRadius(12)
                    }
                }

                // Play/Pause button (iOS style)
                Button(action: toggleScanning) {
                    Image(systemName: isScanning ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 70, height: 70)
                        .background(
                            Circle()
                                .fill(isScanning ? .orange : (canStartScanning ? .green : .gray))
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        )
                }
                .scaleEffect(isScanning ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isScanning)
                .disabled(!canStartScanning && !isScanning)
                .onAppear {
                    print(
                        "🔧 SCAN BUTTON: canStartScanning: \(canStartScanning), isScanning: \(isScanning), disabled: \(!canStartScanning && !isScanning)"
                    )
                }

                // Secondary action button
                if isScanning {
                    Button(action: {
                        stopScanning()
                        dismiss()
                    }) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.red)
                            .cornerRadius(12)
                    }
                } else if model.image != nil {
                    // Show history button when results available
                    Button(action: { showingScanHistory = true }) {
                        Label("History", systemImage: "clock.arrow.circlepath")
                            .font(.headline)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal, 20)

            // Status text
            if !canStartScanning && !isScanning {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)

                    Text("Connect probe to start scanning")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 34)  // Safe area bottom padding
    }

    // MARK: - Setup and Actions

    private func setupScanning() {
        // Don't override imaging.states - just sync with model state
        availablePresets = model.availablePresets

        // Set initial preset if available - prioritize cardiac presets
        if controlPreset == nil && !availablePresets.isEmpty {
            // Look for cardiac-related presets first
            let cardiacPreset = availablePresets.first { preset in
                let name = preset.name.lowercased()
                return name.contains("cardiac") || name.contains("heart") || name.contains("echo")
            }

            controlPreset = cardiacPreset ?? availablePresets.first
            print("🔧 SCANNING SETUP: Selected preset: \(controlPreset?.name ?? "none")")
        }

        print("🔧 SCANNING SETUP: Current model stage: \(model.stage)")
        print(
            "🔧 SCANNING SETUP: Probe state: \(model.probe?.state.description ?? "nil"), Presets: \(availablePresets.count)"
        )
        print("🔧 SCANNING SETUP: Can start scanning: \(canStartScanning)")
    }

    private func toggleScanning() {
        print("🔧 TOGGLE SCANNING: Button pressed! isScanning: \(isScanning)")
        print("🔧 TOGGLE SCANNING: canStartScanning: \(canStartScanning)")

        if isScanning {
            print("🔧 TOGGLE SCANNING: Stopping scanning...")
            stopScanning()
        } else {
            print("🔧 TOGGLE SCANNING: Starting scanning...")
            startScanning()
        }
    }

    private func startScanning() {
        guard canStartScanning else {
            print("🔧 START SCANNING: Cannot start - canStartScanning is false")
            print("🔧 START SCANNING: Probe state: \(model.probe?.state.description ?? "nil")")
            print("🔧 START SCANNING: Available presets: \(availablePresets.count)")
            return
        }

        print("🔧 START SCANNING: Starting scan with preset: \(controlPreset?.name ?? "default")")
        print("🔧 START SCANNING: Current model stage: \(model.stage)")
        print("🔧 START SCANNING: Probe state: \(model.probe?.state.description ?? "nil")")
        print("🔧 START SCANNING: Available presets: \(availablePresets.map { $0.name })")

        // CRITICAL FIX: Actually start imaging if not already started
        if model.stage != .imaging {
            print("🔧 START SCANNING: Model not in imaging mode, starting imaging...")
            model.startImaging(preset: controlPreset)
        } else {
            print("🔧 START SCANNING: Model already in imaging mode")
        }

        isScanning = true
        scanDuration = 0

        // Start the scan timer
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            scanDuration += 0.1
        }

        // Start live EF polling now that scanning has started
        startLiveEFUpdates()

        // Ensure the correct preset is set if needed
        if let preset = controlPreset {
            imaging.setPreset(preset, parameters: nil)
            print("🔧 START SCANNING: Preset set to \(preset.name)")
        }

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }

    private func stopScanning() {
        isScanning = false
        scanTimer?.invalidate()
        scanTimer = nil

        // Stop imaging
        model.stopImaging()

        // Stop EF polling and clear overlay
        stopLiveEFUpdates()
        liveEFPercent = nil

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }

    private func stopScanningIfActive() {
        // Start/stop live EF on manual toggle too
        if isScanning {
            startLiveEFUpdates()
        } else {
            stopLiveEFUpdates()
            liveEFPercent = nil
        }

        if isScanning {
            stopScanning()
        }
    }

    // Live EF updates timer
    private func startLiveEFUpdates() {
        efTimer?.invalidate()
        efTimer = Timer.scheduledTimer(
            withTimeInterval: AppConstants.aiProcessingInterval, repeats: true
        ) { _ in
            guard isScanning, let img = model.image else { return }
            if let ef = MultiOutputModel.shared.predict(image: img)?.efPercent {
                liveEFPercent = ef
            }
        }
    }

    private func stopLiveEFUpdates() {
        efTimer?.invalidate()
        efTimer = nil
    }

    private func saveScanToHistory() {
        guard let image = model.image else { return }

        // Create analysis results exclusively from MultiOutputModel
        let multiOut = model.image.flatMap { MultiOutputModel.shared.predict(image: $0) }

        let analysisResults = ScanRecord.AnalysisResults(
            ejectionFraction: multiOut?.efPercent,
            efConfidence: multiOut?.efPercent != nil ? 0.85 : nil,
            edvMl: multiOut?.edvMl,
            esvMl: multiOut?.esvMl,
            lviddCm: multiOut?.lviddCm,
            lvidsCm: multiOut?.lvidsCm,
            ivsdCm: multiOut?.ivsdCm,
            lvpwdCm: multiOut?.lvpwdCm,
            tapseMm: multiOut?.tapseMm,
            segmentationResults: nil,
            measurements: [],
            aiModelVersion: model.isUsingRealModels ? "v2.1.0" : "simulated",
            processingTime: 2.5
        )

        // Save image to documents directory
        let imageData = image.jpegData(compressionQuality: 0.8) ?? Data()
        let thumbnailData =
            image.resized(to: CGSize(width: 200, height: 150))?.jpegData(compressionQuality: 0.7)
            ?? Data()

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        let scansPath = documentsPath.appendingPathComponent("Scans")

        // Create scans directory if needed
        try? FileManager.default.createDirectory(at: scansPath, withIntermediateDirectories: true)

        let scanId = UUID().uuidString
        let fullImagePath = "scan_full_\(scanId).jpg"
        let thumbnailPath = "scan_thumb_\(scanId).jpg"

        let fullImageURL = scansPath.appendingPathComponent(fullImagePath)
        let thumbnailURL = scansPath.appendingPathComponent(thumbnailPath)

        try? imageData.write(to: fullImageURL)
        try? thumbnailData.write(to: thumbnailURL)

        // Create image data record
        let imageDataRecord = ScanRecord.ImageData(
            thumbnailPath: thumbnailPath,
            fullImagePath: fullImagePath,
            videoPath: nil,
            originalSize: image.size
        )

        // Analyze image quality using real metrics
        let qualityMetrics = ScanRecord.QualityMetrics.analyze(
            image: image,
            modelConfidence: multiOut?.efPercent != nil ? 0.85 : nil,
            segmentationMask: model.segmentationMask,
            processingTime: 2.0  // Approximate processing time for image analysis
        )

        // Create scan record with real quality metrics
        let scanRecord = ScanRecord(
            patient: patientSession.currentPatient,
            analysisResults: analysisResults,
            imageData: imageDataRecord,
            clinicalNotes: "",
            scanDuration: 30.0,
            qualityMetrics: qualityMetrics
        )

        // Save to history
        scanHistory.saveScan(scanRecord)

        print("Scan saved to history: \(scanRecord.id)")
    }

    // MARK: - Helper Functions

    private var canStartScanning: Bool {
        guard let probe = model.probe else {
            print("🔧 CAN START SCANNING: No probe available")
            return false
        }

        // If we're in ScanningView, we're already in imaging mode, so allow scanning
        // even if probe state is not perfect (e.g., temperature warnings)
        let probeUsable =
            probe.state == .connected || probe.state == .ready || probe.state == .notReady
        let hasPresets = !availablePresets.isEmpty
        let canStart = probeUsable && hasPresets

        print(
            "🔧 CAN START SCANNING: Probe state: \(probe.state.description), Usable: \(probeUsable), Has presets: \(hasPresets), Can start: \(canStart)"
        )
        print("🔧 CAN START SCANNING: Model stage: \(model.stage)")
        print("🔧 CAN START SCANNING: Available presets: \(availablePresets.map { $0.name })")
        print("🔧 CAN START SCANNING: Control preset: \(controlPreset?.name ?? "nil")")
        print("🔧 CAN START SCANNING: Is scanning: \(isScanning)")

        return canStart
    }

    private func probeStatusColor(_ state: ProbeState) -> Color {
        // Check thermal state for color override
        if let probe = model.probe {
            let tempStateString = String(describing: probe.temperatureState)
            if tempStateString.contains("hot") {
                return .red  // Hot = red warning
            } else if tempStateString.contains("warm") {
                return .orange  // Warm = orange warning
            } else if tempStateString.contains("coldShutdown") {
                return .blue  // Cold shutdown - show as cooling
            }
        }

        switch state {
        case .connected: return .green
        case .ready: return .green
        case .notReady: return .orange  // Changed from yellow to orange for thermal issues
        case .disconnected: return .red
        case .charging: return .blue
        case .depletedBattery: return .red
        case .hardwareIncompatible, .firmwareIncompatible: return .red
        @unknown default: return .gray
        }
    }

    private func probeStatusText(_ state: ProbeState) -> String {
        // Check for thermal states first
        if let probe = model.probe {
            let tempStateString = String(describing: probe.temperatureState)
            if tempStateString.contains("hot") {
                return "Cooling Down"  // Hot = cooling down
            } else if tempStateString.contains("warm") {
                return "Warming Up"  // Warm = warming up
            } else if tempStateString.contains("coldShutdown") {
                return "Cooling Down"  // Cold shutdown - probe needs to warm up
            }
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

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Recording and Capture Functions

    private func toggleRecording() {
        if mediaManager.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard isScanning else { return }

        // Start video recording using MediaManager
        if mediaManager.startVideoRecording() {
            // Snapshot patient at recording start; use this at stop time
            recordingPatient = patientSession.currentPatient

            print(
                "🎥 Started recording video for patient: \(recordingPatient?.patientID ?? "Unknown")"
            )

            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        } else {
            print("❌ Failed to start video recording")
        }
    }

    private func stopRecording() {
        guard mediaManager.isRecording else { return }

        // Stop video recording using MediaManager
        mediaManager.stopVideoRecording { videoURL, finalDuration in
            guard let videoURL = videoURL else {
                print("❌ Failed to stop video recording")
                return
            }
            print("🎥 Stopped recording video; duration=\(String(format: "%.2f", finalDuration))s")

            // Save combined video + photo record if photo was captured during recording
            if let patient = recordingPatient ?? patientSession.currentPatient {
                if let photoData = lastCapturedPhotoData {
                    saveCombinedVideoAndPhotoRecord(
                        videoURL: videoURL,
                        photoData: photoData,
                        patient: patient
                    )
                    print("💾 Saved combined video + photo record")
                } else {
                    saveVideoWithPatientData(
                        videoURL: videoURL, duration: finalDuration, patient: patient)
                    print("💾 Saved video-only record")
                }
            } else {
                // No patient entered: still save as anonymous so nothing is lost
                if let photoData = lastCapturedPhotoData {
                    let imageData = ScanRecord.ImageData(
                        thumbnailPath: photoData.imagePaths.thumbnailPath,
                        fullImagePath: photoData.imagePaths.fullImagePath,
                        videoPath: videoURL.lastPathComponent,
                        originalSize: photoData.image.size
                    )
                    // Analyze quality using the captured photo
                    let qualityMetrics = ScanRecord.QualityMetrics.analyze(
                        image: photoData.image,
                        modelConfidence: MultiOutputModel.shared.predict(image: photoData.image)?
                            .efPercent != nil ? 0.85 : nil,
                        segmentationMask: model.segmentationMask,
                        processingTime: 0.8
                    )

                    let record = ScanRecord(
                        patient: nil,
                        analysisResults: ScanRecord.AnalysisResults(
                            ejectionFraction: model.image.flatMap {
                                MultiOutputModel.shared.predict(image: $0)?.efPercent
                            },
                            efConfidence: model.image.flatMap {
                                MultiOutputModel.shared.predict(image: $0)?.efPercent
                            } != nil ? 0.85 : nil,
                            edvMl: model.image.flatMap {
                                MultiOutputModel.shared.predict(image: $0)?.edvMl
                            },
                            esvMl: model.image.flatMap {
                                MultiOutputModel.shared.predict(image: $0)?.esvMl
                            },
                            lviddCm: model.image.flatMap {
                                MultiOutputModel.shared.predict(image: $0)?.lviddCm
                            },
                            lvidsCm: model.image.flatMap {
                                MultiOutputModel.shared.predict(image: $0)?.lvidsCm
                            },
                            ivsdCm: model.image.flatMap {
                                MultiOutputModel.shared.predict(image: $0)?.ivsdCm
                            },
                            lvpwdCm: model.image.flatMap {
                                MultiOutputModel.shared.predict(image: $0)?.lvpwdCm
                            },
                            tapseMm: model.image.flatMap {
                                MultiOutputModel.shared.predict(image: $0)?.tapseMm
                            },
                            segmentationResults: nil,
                            measurements: [],
                            aiModelVersion: "v2.1.0",
                            processingTime: 0.8
                        ),
                        imageData: imageData,
                        clinicalNotes: "Anonymous combined video + photo",
                        scanDuration: finalDuration,
                        qualityMetrics: qualityMetrics
                    )
                    scanHistory.saveScan(record)
                    print("💾 Saved combined video + photo record (anonymous)")
                } else {
                    let imageData = ScanRecord.ImageData(
                        thumbnailPath:
                            "video_thumb_\(videoURL.deletingPathExtension().lastPathComponent).jpg",
                        fullImagePath:
                            "video_frame_\(videoURL.deletingPathExtension().lastPathComponent).jpg",
                        videoPath: videoURL.lastPathComponent,
                        originalSize: CGSize(width: 640, height: 480)
                    )
                    let record = ScanRecord(
                        patient: nil,
                        analysisResults: ScanRecord.AnalysisResults(
                            ejectionFraction: model.image.flatMap {
                                MultiOutputModel.shared.predict(image: $0)?.efPercent
                            },
                            efConfidence: model.image.flatMap {
                                MultiOutputModel.shared.predict(image: $0)?.efPercent
                            } != nil ? 0.85 : nil,
                            segmentationResults: nil,
                            measurements: [],
                            aiModelVersion: "v2.1.0",
                            processingTime: 0.4
                        ),
                        imageData: imageData,
                        clinicalNotes: "Anonymous video recording",
                        scanDuration: finalDuration
                    )
                    scanHistory.saveScan(record)
                    print("💾 Saved video-only record (anonymous)")
                }
            }

            // Clear stored photo data and recording patient snapshot
            lastCapturedPhotoData = nil
            recordingPatient = nil

            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
    }

    private func capturePhoto() {
        guard isScanning, let image = model.image else { return }

        // If recording is active, store photo for combined save later
        if mediaManager.isRecording {
            // Save photo files but don't create scan record yet
            if let imagePaths = mediaManager.savePhoto(
                image, patient: patientSession.currentPatient)
            {
                lastCapturedPhotoData = (image: image, imagePaths: imagePaths)
                print("📸 Photo captured during recording - will combine with video on stop")
            }
        } else {
            // Normal photo capture - save immediately
            if let patient = patientSession.currentPatient {
                savePhotoWithPatientData(image: image, patient: patient)
            } else {
                // Save anonymous photo
                savePhotoWithPatientData(image: image, patient: nil)
            }
            print(
                "📸 Captured standalone photo for patient: \(patientSession.currentPatient?.patientID ?? "Unknown")"
            )
        }

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }

    private func saveVideoWithPatientData(videoURL: URL, duration: TimeInterval, patient: Patient) {
        // Extract filename from URL
        let videoFilename = videoURL.lastPathComponent

        // Create analysis results (use multi-output if current image available)
        let mo = model.image.flatMap { MultiOutputModel.shared.predict(image: $0) }
        let analysisResults = ScanRecord.AnalysisResults(
            ejectionFraction: mo?.efPercent,
            efConfidence: mo?.efPercent != nil ? 0.85 : nil,
            edvMl: mo?.edvMl,
            esvMl: mo?.esvMl,
            lviddCm: mo?.lviddCm,
            lvidsCm: mo?.lvidsCm,
            ivsdCm: mo?.ivsdCm,
            lvpwdCm: mo?.lvpwdCm,
            tapseMm: mo?.tapseMm,
            segmentationResults: nil,
            measurements: [],
            aiModelVersion: "v2.1.0",
            processingTime: 0.5
        )

        // Create image data record with video
        let base = URL(fileURLWithPath: videoFilename).deletingPathExtension().lastPathComponent
        let imageData = ScanRecord.ImageData(
            thumbnailPath: "video_thumb_\(base).jpg",
            fullImagePath: "video_frame_\(base).jpg",
            videoPath: videoFilename,
            originalSize: CGSize(width: 640, height: 480)
        )

        // Generate quality metrics from video (use current image if available)
        let qualityMetrics: ScanRecord.QualityMetrics
        if let currentImage = model.image {
            qualityMetrics = ScanRecord.QualityMetrics.analyze(
                image: currentImage,
                modelConfidence: MultiOutputModel.shared.predict(image: currentImage)?.efPercent
                    != nil ? 0.85 : nil,
                segmentationMask: model.segmentationMask,
                processingTime: 0.5
            )
        } else {
            // Fallback to sample metrics if no image available
            qualityMetrics = ScanRecord.QualityMetrics.sample
        }

        // Create scan record
        let scanRecord = ScanRecord(
            patient: patient,
            analysisResults: analysisResults,
            imageData: imageData,
            clinicalNotes: "Video recording captured during scan",
            scanDuration: duration,
            qualityMetrics: qualityMetrics
        )

        // Save to history
        scanHistory.saveScan(scanRecord)

        print("💾 Saved video with patient data: \(patient.patientID)")
    }

    private func savePhotoWithPatientData(image: UIImage, patient: Patient?) {
        // Save photo using MediaManager
        guard let imagePaths = mediaManager.savePhoto(image, patient: patient) else {
            print("❌ Failed to save photo")
            return
        }

        // Create analysis results
        let mo = MultiOutputModel.shared.predict(image: image)
        let analysisResults = ScanRecord.AnalysisResults(
            ejectionFraction: mo?.efPercent,
            efConfidence: mo?.efPercent != nil ? 0.85 : nil,
            segmentationResults: nil,
            measurements: [],
            aiModelVersion: "v2.1.0",
            processingTime: 0.3
        )

        // Create image data record
        let imageData = ScanRecord.ImageData(
            thumbnailPath: imagePaths.thumbnailPath,
            fullImagePath: imagePaths.fullImagePath,
            videoPath: nil,
            originalSize: image.size
        )

        // Analyze image quality using real metrics
        let qualityMetrics = ScanRecord.QualityMetrics.analyze(
            image: image,
            modelConfidence: mo?.efPercent != nil ? 0.85 : nil,
            segmentationMask: model.segmentationMask,
            processingTime: 0.3
        )

        // Create scan record
        let scanRecord = ScanRecord(
            patient: patient,
            analysisResults: analysisResults,
            imageData: imageData,
            clinicalNotes: "Photo captured during scan",
            scanDuration: scanDuration,
            qualityMetrics: qualityMetrics
        )

        // Save to history
        scanHistory.saveScan(scanRecord)

        print("💾 Saved photo with patient data: \(patient?.patientID ?? "anonymous")")
    }

    private func saveCombinedVideoAndPhotoRecord(
        videoURL: URL,
        photoData: (image: UIImage, imagePaths: (thumbnailPath: String, fullImagePath: String)),
        patient: Patient
    ) {
        // Extract video filename from URL
        let videoFilename = videoURL.lastPathComponent

        // Create analysis results with current EF
        let mo = MultiOutputModel.shared.predict(image: photoData.image)
        let analysisResults = ScanRecord.AnalysisResults(
            ejectionFraction: mo?.efPercent,
            efConfidence: mo?.efPercent != nil ? 0.85 : nil,
            segmentationResults: nil,
            measurements: [],
            aiModelVersion: "v2.1.0",
            processingTime: 1.2
        )

        // Create image data record with BOTH video and photo
        let imageData = ScanRecord.ImageData(
            thumbnailPath: photoData.imagePaths.thumbnailPath,  // Use photo thumbnail
            fullImagePath: photoData.imagePaths.fullImagePath,  // Use photo for full image
            videoPath: videoFilename,  // Include video
            originalSize: photoData.image.size
        )

        // Analyze quality using the captured photo (best quality reference)
        let qualityMetrics = ScanRecord.QualityMetrics.analyze(
            image: photoData.image,
            modelConfidence: mo?.efPercent != nil ? 0.85 : nil,
            segmentationMask: model.segmentationMask,
            processingTime: 1.2
        )

        // Create comprehensive scan record
        let scanRecord = ScanRecord(
            patient: patient,
            analysisResults: analysisResults,
            imageData: imageData,
            clinicalNotes: "Combined video recording and photo capture during cardiac scan",
            scanDuration: mediaManager.recordingDuration,
            qualityMetrics: qualityMetrics
        )

        // Save to history
        scanHistory.saveScan(scanRecord)

        print("🎥📸 Saved combined video + photo record for patient: \(patient.patientID)")
    }

    private func exitScanning() {
        // Stop any ongoing recording
        if mediaManager.isRecording {
            stopRecording()
        }

        // Stop scanning
        stopScanningIfActive()

        // Clear current patient session
        PatientSessionManager.shared.clearCurrentPatient()

        // Navigate back to home by setting model stage to ready
        model.stage = .ready

        print("🚪 Exiting scanning mode - returning to home screen")
    }

    private func goToHome() {
        // Stop any ongoing recording
        if mediaManager.isRecording {
            stopRecording()
        }

        // Stop scanning if active
        stopScanningIfActive()

        // Clear current patient session
        PatientSessionManager.shared.clearCurrentPatient()

        // Navigate directly to home by setting model stage to ready
        model.stage = .ready

        print("🏠 Going to home screen from probe status")
    }
}

struct ScanningView_Previews: PreviewProvider {
    static var previews: some View {
        ScanningView(model: Model.shared)
            .preferredColorScheme(.dark)
    }
}
