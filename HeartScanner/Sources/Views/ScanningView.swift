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
    @StateObject private var patientSession = PatientSessionManager.shared
    @StateObject private var scanHistory = ScanHistoryManager.shared
    @StateObject private var mediaManager = MediaManager.shared
    @Environment(\.dismiss) private var dismiss

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

                    // EF Results Display during scanning
                    if let ef = model.efResult {
                        efResultsDisplay(ef)
                    }

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
                controlPreset = availablePresets.first
            }
            print("🔧 SCANNING: Available presets updated: \(availablePresets.count)")
        }
        .onChange(of: model.probe?.state) { _, _ in
            print("🔧 SCANNING: Probe state changed: \(model.probe?.state.description ?? "nil")")
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

            // Patient info (if available)
            if let patient = patientSession.currentPatient {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Patient")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                    Text(patient.patientID)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.9))
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

                // Exit scanning button
                if isScanning {
                    Button(action: { showingExitConfirmation = true }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white)
                            .font(.title2)
                            .padding(8)
                            .background(.red.opacity(0.8))
                            .cornerRadius(8)
                    }
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

    // MARK: - EF Results Display

    private func efResultsDisplay(_ ef: Float) -> some View {
        VStack(spacing: 4) {
            Text("Ejection Fraction: \(String(format: "%.1f", ef * 100))%")
                .font(.title2)
                .foregroundColor(.white)

            Text(model.isUsingRealModels ? "AI Prediction" : "Simulated")
                .font(.caption)
                .foregroundColor(model.isUsingRealModels ? .green : .orange)
        }
        .padding()
        .background(.black.opacity(0.7))
        .cornerRadius(12)
        .accessibilityLabel("Ejection Fraction: \(ef * 100)%")
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
                // Save scan button (only show when has results)
                if model.efResult != nil || model.image != nil {
                    Button(action: saveScanToHistory) {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.blue)
                            .cornerRadius(12)
                    }
                    .disabled(model.efResult == nil && model.image == nil)
                }

                // Play/Pause button (iOS style)
                Button(action: toggleScanning) {
                    Image(systemName: isScanning ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 70, height: 70)
                        .background(
                            Circle()
                                .fill(isScanning ? .orange : .green)
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        )
                }
                .scaleEffect(isScanning ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isScanning)
                .disabled(!canStartScanning && !isScanning)

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
                } else if model.efResult != nil || model.image != nil {
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

        // Set initial preset if available
        if controlPreset == nil && !availablePresets.isEmpty {
            controlPreset = availablePresets.first
        }

        print(
            "🔧 SCANNING SETUP: Probe state: \(model.probe?.state.description ?? "nil"), Presets: \(availablePresets.count)"
        )
    }

    private func toggleScanning() {
        if isScanning {
            stopScanning()
        } else {
            startScanning()
        }
    }

    private func startScanning() {
        guard canStartScanning else {
            print("🔧 START SCANNING: Cannot start - canStartScanning is false")
            return
        }

        print("🔧 START SCANNING: Starting scan with preset: \(controlPreset?.name ?? "default")")

        isScanning = true
        scanDuration = 0

        // Start the scan timer
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            scanDuration += 0.1
        }

        // Don't call model.startImaging() - we're already in imaging mode!
        // Just ensure the correct preset is set if needed
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

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }

    private func stopScanningIfActive() {
        if isScanning {
            stopScanning()
        }
    }

    private func saveScanToHistory() {
        guard let image = model.image else { return }

        // Create analysis results
        var measurements: [ScanRecord.AnalysisResults.Measurement] = []
        if let ef = model.efResult {
            let efMeasurement = ScanRecord.AnalysisResults.Measurement(
                type: .ejectionFraction,
                value: Double(ef * 100),
                unit: "%"
            )
            measurements.append(efMeasurement)
        }

        let analysisResults = ScanRecord.AnalysisResults(
            ejectionFraction: model.efResult != nil ? Double(model.efResult! * 100) : nil,
            efConfidence: model.isUsingRealModels ? 0.85 : 0.5,
            segmentationResults: nil,
            measurements: measurements,
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

        // Create scan record
        let scanRecord = ScanRecord(
            patient: patientSession.currentPatient,
            analysisResults: analysisResults,
            imageData: imageDataRecord,
            clinicalNotes: "",
            scanDuration: 30.0
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

        return canStart
    }

    private func probeStatusColor(_ state: ProbeState) -> Color {
        switch state {
        case .connected: return .green
        case .disconnected: return .red
        case .hardwareIncompatible, .firmwareIncompatible: return .red
        default: return .gray
        }
    }

    private func probeStatusText(_ state: ProbeState) -> String {
        switch state {
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .hardwareIncompatible: return "Incompatible"
        case .firmwareIncompatible: return "Update Required"
        default: return "Unknown"
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
            print(
                "🎥 Started recording video for patient: \(patientSession.currentPatient?.patientID ?? "Unknown")"
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
        if let videoURL = mediaManager.stopVideoRecording() {
            print("🎥 Stopped recording video")

            // Save video with patient data
            if let patient = patientSession.currentPatient {
                saveVideoWithPatientData(videoURL: videoURL, patient: patient)
            }

            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        } else {
            print("❌ Failed to stop video recording")
        }
    }

    private func capturePhoto() {
        guard isScanning, let image = model.image else { return }

        // Capture current ultrasound image using MediaManager
        if let patient = patientSession.currentPatient {
            savePhotoWithPatientData(image: image, patient: patient)
        } else {
            // Save anonymous photo
            savePhotoWithPatientData(image: image, patient: nil)
        }

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        print(
            "📸 Captured photo for patient: \(patientSession.currentPatient?.patientID ?? "Unknown")"
        )
    }

    private func saveVideoWithPatientData(videoURL: URL, patient: Patient) {
        // Extract filename from URL
        let videoFilename = videoURL.lastPathComponent

        // Create analysis results (basic for video)
        let analysisResults = ScanRecord.AnalysisResults(
            ejectionFraction: model.efResult.map { Double($0 * 100) },
            efConfidence: model.efResult != nil ? 0.85 : nil,
            segmentationResults: nil,
            measurements: [],
            aiModelVersion: "v2.1.0",
            processingTime: 0.5
        )

        // Create image data record with video
        let imageData = ScanRecord.ImageData(
            thumbnailPath: "video_thumb_\(videoFilename).jpg",
            fullImagePath: "video_frame_\(videoFilename).jpg",
            videoPath: videoFilename,
            originalSize: CGSize(width: 640, height: 480)
        )

        // Create scan record
        let scanRecord = ScanRecord(
            patient: patient,
            analysisResults: analysisResults,
            imageData: imageData,
            clinicalNotes: "Video recording captured during scan",
            scanDuration: mediaManager.recordingDuration
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
        let analysisResults = ScanRecord.AnalysisResults(
            ejectionFraction: model.efResult.map { Double($0 * 100) },
            efConfidence: model.efResult != nil ? 0.85 : nil,
            segmentationResults: nil,
            measurements: model.efResult != nil
                ? [
                    ScanRecord.AnalysisResults.Measurement(
                        type: .ejectionFraction,
                        value: Double(model.efResult! * 100),
                        unit: "%"
                    )
                ] : [],
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

        // Create scan record
        let scanRecord = ScanRecord(
            patient: patient,
            analysisResults: analysisResults,
            imageData: imageData,
            clinicalNotes: "Photo captured during scan",
            scanDuration: scanDuration
        )

        // Save to history
        scanHistory.saveScan(scanRecord)

        print("💾 Saved photo with patient data: \(patient?.patientID ?? "anonymous")")
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
}

struct ScanningView_Previews: PreviewProvider {
    static var previews: some View {
        ScanningView(model: Model.shared)
            .preferredColorScheme(.dark)
    }
}
