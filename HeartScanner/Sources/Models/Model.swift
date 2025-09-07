import ButterflyImagingKit
import UIKit

@MainActor
class Model: ObservableObject {
    enum Stage {
        case startingUp, ready, updateNeeded, readyToScan, startingImaging, imaging
    }

    @Published var availablePresets: [ImagingPreset] = []
    @Published var colorGain = 0
    @Published var depth = Measurement.centimeters(0)
    @Published var depthBounds = Measurement.centimeters(0)...Measurement.centimeters(0)
    @Published var gain = 0
    @Published var image: UIImage?
    @Published var licenseState: ButterflyImaging.LicenseState = .invalid
    @Published var mode = UltrasoundMode.bMode
    @Published var preset: ImagingPreset?
    @Published var probe: Probe?
    @Published var stage = Stage.startingUp
    @Published var inProgress = false
    @Published var updating = false
    @Published var updateProgress: TimedProgress?
    @Published var probeError: String?
    @Published var alertError: Error? { didSet { showingAlert = (alertError != nil) } }
    @Published var showingAlert: Bool = false
    @Published var segmentationMask: UIImage?
    @Published var isUsingRealModels: Bool = false
    @Published var modelStatus: String = "Checking models..."
    @Published var errorMessage: String?

    private let segmentationModel: HeartSegmentationModel
    private var frameBuffer: [CVPixelBuffer] = []
    private let imaging = ButterflyImaging.shared
    private var frameProcessingQueue = DispatchQueue(label: "frame.processing", qos: .userInitiated)
    private var lastProcessedTime: Date = Date()
    private var lastAIProcessedTime: Date = Date()
    private var aiProcessingInFlight = false  // Prevent overlapping AI work
    // Separate timing for frame display vs AI processing

    // Background AI worker (non-actor) to avoid blocking main thread
    private let aiWorker: AIWorker

    // Lightweight worker to serialize AI tasks off the main actor
    private final class AIWorker {
        private let queue = DispatchQueue(label: "ai.worker.queue", qos: .userInitiated)
        func run(_ block: @escaping () async -> Void) {
            queue.async {
                Task { await block() }
            }
        }
    }

    // MARK: - Async Factory Method

    static var shared: Model!

    static func initialize() async throws {
        let segmentationModel = try await HeartSegmentationModel()
        shared = Model(segmentationModel: segmentationModel)
        await shared.checkModelAvailability()
    }

    static func create() async throws -> Model {
        if shared == nil {
            try await initialize()
        }
        return shared
    }

    private static func initializeShared() async throws {
        let segmentationModel = try await HeartSegmentationModel()
        shared = Model(segmentationModel: segmentationModel)
    }

    private init(segmentationModel: HeartSegmentationModel) {
        self.segmentationModel = segmentationModel
        self.aiWorker = AIWorker()

        imaging.isClientLoggingEnabled = true
        imaging.licenseStates = { [weak self] in
            self?.licenseState = $0
        }

        imaging.clientLoggingCallback = { message, severity in
            print("[ButterflyImagingKit]: [\(severity)] \(message)")

            // Log diagnostic-related messages for debugging
            if message.contains("diagnostic") || message.contains("test") {
                print("🔧 PROBE DIAGNOSTIC: \(message)")
            }
        }

        imaging.states = { [weak self] state, changes in
            self?.setState(state, imagingStateChanges: changes)
        }
        // Refresh status when MultiOutput model becomes available
        NotificationCenter.default.addObserver(
            forName: .multiOutputModelReady, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.checkModelAvailability() }
        }

    }

    private func checkModelAvailability() async {
        let segAvailable = segmentationModel.isModelAvailable
        let multiOutAvailable = MultiOutputModel.shared.isModelAvailable

        await MainActor.run {
            self.isUsingRealModels = segAvailable && multiOutAvailable

            if segAvailable && multiOutAvailable {
                self.modelStatus = "✅ Clinical AI Models Ready"
                print("CLINICAL READY: Segmentation and Multi-Output models loaded successfully")
            } else if segAvailable || multiOutAvailable {
                self.modelStatus =
                    "🚨 CRITICAL: Incomplete Clinical Setup (MultiOut: \(multiOutAvailable ? "✅" : "❌"), Seg: \(segAvailable ? "✅" : "❌"))"
                print("CLINICAL WARNING: Not all required models are available")
            } else {
                self.modelStatus = "🚨 CRITICAL: No Clinical Models Available"
                print("CLINICAL ERROR: No AI models loaded - application not safe for medical use")
            }
        }

        print("Model Status: \(modelStatus)")
    }

    // MARK: - Imaging Lifecycle

    func setState(_ state: ImagingState, imagingStateChanges: ImagingStateChanges) {
        availablePresets = state.availablePresets
        colorGain = state.colorGain
        depth = state.depth
        depthBounds = state.depthBounds
        gain = state.gain
        mode = state.mode
        preset = state.preset

        // CRITICAL: Proper probe state management
        let previousProbeState = probe?.state
        probe = state.probe

        // Enhanced probe state debugging with timestamp
        let timestamp = DateFormatter().string(from: Date())
        print(
            "🔧 PROBE STATE UPDATE [\(timestamp)]: \(previousProbeState?.description ?? "nil") → \(state.probe.state.description)"
        )
        print(
            "🔧 PROBE INFO: Available presets: \(state.availablePresets.count), Mode: \(state.mode)")
        print("🔧 PROBE DETAILS: isSimulated: \(state.probe.isSimulated)")

        // CRITICAL: Monitor thermal state for overheating
        print(
            "🌡️ THERMAL STATE: \(state.probe.temperatureState), Temp: \(state.probe.estimatedTemperature)°C"
        )

        // Check for thermal issues
        let tempStateString = String(describing: state.probe.temperatureState)
        if tempStateString.contains("hot") || tempStateString.contains("warm") {
            print(
                "🔥 THERMAL WARNING: Probe is getting hot - temperature state: \(state.probe.temperatureState)"
            )
        } else if tempStateString.contains("coldShutdown") {
            print(
                "🧊 COLD SHUTDOWN: Probe temperature sensor indicates cold shutdown - temp: \(state.probe.estimatedTemperature)°C"
            )
        }

        // Handle probe state changes
        if let previousState = previousProbeState, previousState != state.probe.state {
            print(
                "🚨 PROBE STATE CHANGE DETECTED: \(previousState.description) → \(state.probe.state.description)"
            )
            handleProbeStateChange(from: previousState, to: state.probe.state)
        }

        switch mode {
        case .bMode, .colorDoppler:
            if imagingStateChanges.bModeImageChanged,
                let img = state.bModeImage?.image
            {
                image = img

                // Add frame to video recording if active
                MediaManager.shared.addFrameToRecording(img)

                // Process frame asynchronously to prevent UI freezing
                Task {
                    await self.processFrame(img.toCVPixelBuffer())
                }
            }
        case .mMode:
            if imagingStateChanges.mModeImageChanged,
                let img = state.mModeImage?.image
            {
                image = img
            }
        @unknown default:
            break
        }

        switch stage {
        case .startingUp:
            stage = .ready
        case .ready:
            break
        case .updateNeeded:
            if state.probe.state != .firmwareIncompatible {
                stage = .ready
            }
        case .readyToScan:
            // Stay in readyToScan until user explicitly starts imaging
            break
        case .startingImaging:
            if image != nil {
                stage = .imaging
            }
            if state.probe.state == .disconnected {
                stopImaging()
            }
        case .imaging:
            print("🔍 DEBUG: In imaging stage, probe state: \(state.probe.state.description)")
            print("🔍 DEBUG: Temperature state: \(state.probe.temperatureState)")
            print("🔍 DEBUG: Image available: \(state.bModeImage?.image != nil)")

            if state.probe.state == .disconnected {
                print("🛑 IMAGING: Stopping due to probe disconnection")
                stopImaging()
            }

            // Monitor if we stop receiving images (SDK internal stop)
            if state.bModeImage?.image == nil && image != nil {
                print("🚨 IMAGING: No longer receiving images from SDK - possible internal stop")
            }

            // CRITICAL: Handle thermal recovery during imaging
            if state.probe.state == .ready && previousProbeState == .notReady {
                print("✅ THERMAL RECOVERY: Probe cooled down, imaging can continue normally")
                // Clear any thermal warnings (both thermal protection and cold shutdown)
                if let nsError = alertError as? NSError, nsError.code == -3 || nsError.code == -4 {
                    alertError = nil
                    showingAlert = false
                }
            }
        }

        if state.probe.state == .firmwareIncompatible {
            stage = .updateNeeded
        }
    }

    func navigateToScanningView() {
        stage = .readyToScan
    }

    // MARK: - Probe State Management

    private func handleProbeStateChange(from previousState: ProbeState, to newState: ProbeState) {
        print("🔧 PROBE STATE CHANGE: \(previousState.description) → \(newState.description)")

        switch newState {
        case .connected:
            print("✅ PROBE CONNECTED: Ready for imaging")
        // Probe is connected and ready for imaging

        case .disconnected:
            print("❌ PROBE DISCONNECTED: Stopping any active imaging")
            if stage == .imaging || stage == .startingImaging {
                stopImaging()
            }

        case .firmwareIncompatible:
            print("⚠️ PROBE FIRMWARE INCOMPATIBLE: Update required")
            stage = .updateNeeded

        case .ready:
            print(
                "✅ PROBE READY: Probe is ready for imaging - this is the correct state for scanning!"
            )

        case .notReady:
            print("⚠️ PROBE NOT READY: Probe is not ready for use")

            // DEBUG: Let's see what happens if we do NOTHING when probe goes notReady
            if stage == .imaging {
                let tempStateString = String(describing: probe?.temperatureState)
                if tempStateString.contains("coldShutdown") {
                    print(
                        "🧊 COLD SHUTDOWN DETECTED: Probe temp: \(probe?.estimatedTemperature ?? 0)°C"
                    )
                    print("🔍 DEBUG: NOT interfering with SDK - letting it handle cold shutdown")
                    print("🔍 DEBUG: Current imaging stage: \(stage)")
                    print("🔍 DEBUG: Will monitor if SDK stops imaging internally...")

                    // MINIMAL INTERVENTION: Just log, don't change anything
                    DispatchQueue.main.async {
                        self.errorMessage = "Cold shutdown detected - monitoring SDK behavior..."
                    }
                } else {
                    print(
                        "🔥 THERMAL PROTECTION: Probe overheated during imaging"
                    )
                    print(
                        "🔍 DEBUG: NOT interfering with SDK - letting it handle thermal protection")
                }
            }

        case .hardwareIncompatible:
            print("❌ PROBE HARDWARE INCOMPATIBLE: Hardware not supported")

        case .charging:
            print("🔋 PROBE CHARGING: Probe is currently charging")

        case .depletedBattery:
            print("🪫 PROBE BATTERY DEPLETED: Probe battery is depleted")

        @unknown default:
            print("🔧 PROBE STATE: Unknown state \(newState)")
        }
    }

    func startImaging(preset: ImagingPreset? = nil, depth: Double? = nil) {
        // CRITICAL: Validate probe state before starting imaging
        print("🔧 IMAGING START: Current probe state: \(probe?.state.description ?? "nil")")
        print("🔧 IMAGING START: Current stage: \(stage)")
        print("🔧 IMAGING START: Available presets: \(availablePresets.count)")

        // Check if probe is available and connected
        guard let currentProbe = probe else {
            print("❌ IMAGING ERROR: No probe available")
            alertError = NSError(
                domain: "HeartScanner", code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "No probe connected. Please connect a probe first."
                ]
            )
            showingAlert = true
            return
        }

        // Allow imaging if probe is connected or ready
        let isProbeUsable = currentProbe.state == .connected || currentProbe.state == .ready

        if !isProbeUsable {
            print(
                "❌ IMAGING ERROR: Probe not usable. Current state: \(currentProbe.state.description)"
            )
            alertError = NSError(
                domain: "HeartScanner", code: -2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Probe not ready. Current state: \(currentProbe.state.description). Please check probe connection."
                ]
            )
            showingAlert = true
            return
        }

        // Clear any previous results
        segmentationMask = nil
        frameBuffer.removeAll()

        stage = .startingImaging
        var parameters: PresetParameters? = nil

        if let preset, let depth,
            preset.defaultDepth.converted(to: .centimeters).value != depth
        {
            parameters = PresetParameters(depth: .centimeters(depth))
        }

        Task {
            do {
                print(
                    "🔧 IMAGING START: Beginning imaging with preset: \(preset?.name ?? "default")")
                print(
                    "🔧 IMAGING START: Parameters: \(parameters != nil ? "custom depth" : "default")"
                )

                try await imaging.startImaging(preset: preset, parameters: parameters)
                print("✅ IMAGING START: Butterfly SDK startImaging completed successfully")

                // Ensure we transition to imaging state
                await MainActor.run {
                    if self.stage == .startingImaging {
                        print("🔧 IMAGING START: Transitioning to imaging state")
                        self.stage = .imaging
                    }
                }
            } catch {
                print("❌ IMAGING ERROR: Failed to start imaging: \(error)")
                await MainActor.run {
                    self.alertError = error
                    self.showingAlert = true
                    self.stage = .ready
                }
            }
        }
    }

    func connectSimulatedProbe() async {
        inProgress = true
        await imaging.connectSimulatedProbe()
        inProgress = false
    }

    func connectProbe(simulated: Bool) async {
        inProgress = true
        print("🔧 PROBE CONNECTION: Starting connection process (simulated: \(simulated))")

        if simulated {
            print("🔧 PROBE CONNECTION: Connecting simulated probe...")
            await imaging.connectSimulatedProbe()
            print("✅ PROBE CONNECTION: Simulated probe connection initiated")
        } else {
            // For real probes, the connection is automatic when the probe is plugged in
            // The ButterflyImagingKit will detect and connect automatically
            print("🔧 PROBE CONNECTION: Waiting for real probe connection...")
            print("🔧 PROBE CONNECTION: Current probe state: \(probe?.state.description ?? "nil")")

            // The imaging.states callback is already set in init and will handle state changes
            // Just wait a moment to see if the probe connects
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

            if let currentProbe = probe {
                print(
                    "🔧 PROBE CONNECTION: After wait, probe state: \(currentProbe.state.description)"
                )
            } else {
                print("⚠️ PROBE CONNECTION: No probe detected after wait")
            }
        }
        inProgress = false
    }

    func disconnectSimulatedProbe() async {
        inProgress = true
        await imaging.disconnectSimulatedProbe()
        inProgress = false
    }

    func startup(clientKey: String) async throws {
        do {
            print("🔧 BUTTERFLY STARTUP: Starting with client key: \(clientKey)")
            try await imaging.startup(clientKey: clientKey)
            imaging.isClientLoggingEnabled = true
            imaging.clientLoggingCallback = { message, severity in
                print("[ButterflyImagingKit]: [\(severity)] \(message)")

                // Log probe-related messages
                if message.contains("probe") || message.contains("connection") {
                    print("🔧 PROBE LOG: \(message)")
                }
            }
            print("🔧 BUTTERFLY STARTUP: Completed successfully")
        } catch {
            alertError = error
            showingAlert = true
            print("🔧 BUTTERFLY STARTUP ERROR: \(error)")
            throw error
        }
    }

    func updateFirmware() async {
        updating = true
        do {
            for try await progress in imaging.updateFirmware() {
                updateProgress = progress
            }
        } catch {
            print("Update error: \(error)")
            alertError = error
            showingAlert = true
        }
        updating = false
    }

    func clearError() {
        alertError = nil
    }

    func stopImaging() {
        print("🛑 STOP IMAGING CALLED - Investigating who called this...")
        print("🔍 DEBUG: Current stage: \(stage)")
        print("🔍 DEBUG: Probe state: \(probe?.state.description ?? "nil")")
        print("🔍 DEBUG: Temperature state: \(String(describing: probe?.temperatureState))")

        // Print stack trace to see who called stopImaging
        Thread.callStackSymbols.forEach { symbol in
            if symbol.contains("HeartScanner") {
                print("🔍 STACK: \(symbol)")
            }
        }

        Task {
            do {
                try await imaging.stopImaging()
                stage = .readyToScan  // Return to scanning view, not home
                // Clear frame buffer when stopping
                frameBuffer.removeAll()
                print("✅ STOP IMAGING: Successfully stopped imaging")
            } catch {
                print("❌ STOP IMAGING ERROR: Failed to stop imaging: \(error)")
            }
        }
    }

    // MARK: - Frame Processing

    private func processFrame(_ buffer: CVPixelBuffer?) async {
        guard let buffer = buffer else { return }

        do {
            // MEDICAL GRADE: Always process frames for smooth imaging display
            let now = Date()
            guard now.timeIntervalSince(lastProcessedTime) >= AppConstants.frameProcessingInterval
            else {
                return
            }
            lastProcessedTime = now

            // Add to frame buffer with memory management
            frameBuffer.append(buffer)
            if frameBuffer.count > AppConstants.maxFrameBufferSize {
                frameBuffer.removeFirst()
            }

            // SEPARATE AI PROCESSING: Process AI models at different interval for performance
            let shouldProcessAI =
                now.timeIntervalSince(lastAIProcessedTime) >= AppConstants.aiProcessingInterval

            if shouldProcessAI {
                lastAIProcessedTime = now

                // Prevent overlapping AI work to avoid freezes
                guard !aiProcessingInFlight else { return }
                aiProcessingInFlight = true

                aiWorker.run { [weak self] in
                    guard let self = self else { return }
                    defer { self.aiProcessingInFlight = false }

                    // Process segmentation every 2nd frame for good visualization
                    if self.frameBuffer.count % 2 == 0 {
                        await self.processSegmentation(buffer)
                    }

                    // EF processing removed; MultiOutputModel is used downstream for stills
                }
            }
        } catch {
            print("Frame processing error: \(error)")
        }
    }

    private func processSegmentation(_ buffer: CVPixelBuffer) async {
        print("CLINICAL SEGMENTATION: Starting cardiac structure analysis")
        print(
            "CLINICAL SEGMENTATION: Frame size: \(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer))"
        )

        do {
            print("CLINICAL SEGMENTATION: Preprocessing frame...")
            if let segInput = await segmentationModel.preprocess(buffer) {
                print("CLINICAL SEGMENTATION: Frame preprocessed successfully, running AI model...")
                if let mask = try await segmentationModel.predict(segInput) {
                    print(
                        "CLINICAL SEGMENTATION: AI model prediction successful, validating mask...")
                    // Validate segmentation mask quality
                    if await validateSegmentationMask(mask) {
                        await MainActor.run {
                            self.segmentationMask = mask
                            print(
                                "CLINICAL SEGMENTATION: ✅ Valid cardiac segmentation generated and displayed!"
                            )
                        }
                    } else {
                        print(
                            "CLINICAL SEGMENTATION: ❌ Invalid segmentation mask - quality check failed"
                        )
                    }
                } else {
                    print("CLINICAL SEGMENTATION: ❌ Model prediction failed - no mask generated")
                }
            } else {
                print("CLINICAL SEGMENTATION: ❌ Frame preprocessing failed - cannot process")
            }
        } catch {
            print("CLINICAL SEGMENTATION: 🚨 Critical error - \(error.localizedDescription)")
            // Don't crash the app, just log the error
        }
    }

    private func validateSegmentationMask(_ mask: UIImage) async -> Bool {
        // Basic validation to ensure the segmentation mask is reasonable
        guard mask.size.width > 0 && mask.size.height > 0 else {
            print("Segmentation Validation: Invalid mask dimensions")
            return false
        }

        // Additional validation could include:
        // - Checking for reasonable cardiac structure proportions
        // - Validating mask pixel value distribution
        // - Ensuring anatomically plausible segmentation

        print("Segmentation Validation: Mask passed basic quality checks")
        return true
    }

}
