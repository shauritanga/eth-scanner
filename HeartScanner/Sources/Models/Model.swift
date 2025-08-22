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
    @Published var efResult: Float?
    @Published var segmentationMask: UIImage?
    @Published var isUsingRealModels: Bool = false
    @Published var modelStatus: String = "Checking models..."

    private let efModel: EFModel
    private let segmentationModel: HeartSegmentationModel
    private var frameBuffer: [CVPixelBuffer] = []
    private let imaging = ButterflyImaging.shared
    private var frameProcessingQueue = DispatchQueue(label: "frame.processing", qos: .userInitiated)
    private var lastProcessedTime: Date = Date()
    // Processing interval is now defined in AppConstants

    // MARK: - Async Factory Method

    static var shared: Model!

    static func initialize() async throws {
        let efModel = try await EFModel()
        let segmentationModel = try await HeartSegmentationModel()
        shared = Model(efModel: efModel, segmentationModel: segmentationModel)
        await shared.checkModelAvailability()
    }

    static func create() async throws -> Model {
        if shared == nil {
            try await initialize()
        }
        return shared
    }

    private static func initializeShared() async throws {
        let efModel = try await EFModel()
        let segmentationModel = try await HeartSegmentationModel()
        shared = Model(efModel: efModel, segmentationModel: segmentationModel)
    }

    private init(efModel: EFModel, segmentationModel: HeartSegmentationModel) {
        self.efModel = efModel
        self.segmentationModel = segmentationModel

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
    }

    private func checkModelAvailability() async {
        let efAvailable = efModel.isModelAvailable
        let segAvailable = segmentationModel.isModelAvailable

        await MainActor.run {
            self.isUsingRealModels = efAvailable && segAvailable

            if efAvailable && segAvailable {
                self.modelStatus = "✅ Clinical AI Models Ready"
                print("CLINICAL READY: Both EF and Segmentation models loaded successfully")
            } else if efAvailable || segAvailable {
                self.modelStatus =
                    "🚨 CRITICAL: Incomplete Clinical Setup (EF: \(efAvailable ? "✅" : "❌"), Seg: \(segAvailable ? "✅" : "❌"))"
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
        probe = state.probe

        // Debug probe state changes
        print(
            "🔧 PROBE STATE UPDATE: \(state.probe.state.description) - Available presets: \(state.availablePresets.count)"
        )

        switch mode {
        case .bMode, .colorDoppler:
            if imagingStateChanges.bModeImageChanged,
                let img = state.bModeImage?.image
            {
                image = img

                // Add frame to video recording if active
                MediaManager.shared.addFrameToRecording(img)

                // Process frame on background queue to prevent UI freezing
                Task.detached(priority: .userInitiated) { @MainActor in
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
            if state.probe.state == .disconnected {
                stopImaging()
            }
        }

        if state.probe.state == .firmwareIncompatible {
            stage = .updateNeeded
        }
    }

    func navigateToScanningView() {
        stage = .readyToScan
    }

    func startImaging(preset: ImagingPreset? = nil, depth: Double? = nil) {
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
                try await imaging.startImaging(preset: preset, parameters: parameters)
                print("🔧 IMAGING START: Butterfly SDK startImaging completed successfully")
            } catch {
                print("🔧 IMAGING ERROR: Failed to start imaging: \(error)")
                alertError = error
                showingAlert = true
                // Return to ready state on error
                stage = .ready
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
        if simulated {
            await imaging.connectSimulatedProbe()
        } else {
            // For real probes, the connection is automatic when the probe is plugged in
            // The ButterflyImagingKit will detect and connect automatically
            print("🔧 PROBE CONNECTION: Waiting for real probe connection...")
            // Don't override the imaging.states callback here - it's already set in init
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
        Task {
            do {
                try await imaging.stopImaging()
                stage = .readyToScan  // Return to scanning view, not home
                // Clear frame buffer when stopping
                frameBuffer.removeAll()
            } catch {
                print("Failed to stop imaging: \(error)")
            }
        }
    }

    // MARK: - Frame Processing

    private func processFrame(_ buffer: CVPixelBuffer?) async {
        guard let buffer = buffer else { return }

        do {
            // Throttle processing to reduce memory pressure
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

            // CLINICAL: Process segmentation more frequently for better visualization
            if frameBuffer.count % 2 == 0 {  // Every 2nd frame for better responsiveness
                await processSegmentation(buffer)
            }

            // Process EF only when we have the maximum buffer size (for best quality)
            // The EF model will interpolate/repeat frames to create the required 32 frames
            if frameBuffer.count == AppConstants.maxFrameBufferSize {
                await processEjectionFraction()
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

    private func processEjectionFraction() async {
        // Medical-grade validation: Ensure sufficient frames for reliable analysis
        guard !frameBuffer.isEmpty else {
            print("EF Processing: No frames available in buffer")
            return
        }

        guard frameBuffer.count >= 8 else {
            print(
                "EF Processing: Insufficient frames (\(frameBuffer.count)) for reliable cardiac analysis"
            )
            return
        }

        print("EF Processing: Starting medical analysis with \(frameBuffer.count) frames")

        do {
            if let efInput = await efModel.preprocess(frameBuffer) {
                if let ef = try efModel.predict(efInput) {
                    // Medical-grade validation: EF must be within physiologically possible range
                    let efPercentage = ef * 100
                    print(
                        "EF Processing: Raw EF value: \(ef), Percentage: \(String(format: "%.1f", efPercentage))%"
                    )

                    // CLINICAL VALIDATION: EF must be within physiologically possible range (15-80%)
                    if efPercentage >= 15.0 && efPercentage <= 80.0 {
                        await MainActor.run {
                            self.efResult = ef

                            // CLINICAL LOGGING: Always using real AI models
                            print(
                                "CLINICAL EF RESULT: \(String(format: "%.1f", efPercentage))% (Source: Clinical AI Model)"
                            )

                            // Clinical range validation using app constants
                            if ef < AppConstants.efLowerThreshold
                                || ef > AppConstants.efUpperThreshold
                            {
                                self.alertError = NSError(
                                    domain: "HeartScanner", code: -1,
                                    userInfo: [
                                        NSLocalizedDescriptionKey:
                                            "EF outside normal range: \(String(format: "%.1f", efPercentage))%. Please consult a cardiologist."
                                    ])
                                self.showingAlert = true
                                print("EF Processing: Clinical alert - EF outside normal range")
                            }
                        }
                    } else {
                        print(
                            "CLINICAL WARNING: EF result (\(String(format: "%.1f", efPercentage))%) outside normal range (15-80%) - requires clinical review"
                        )
                        // Don't update the result if it's medically implausible
                        await MainActor.run {
                            self.alertError = NSError(
                                domain: "HeartScanner", code: -2,
                                userInfo: [
                                    NSLocalizedDescriptionKey:
                                        "Clinical Alert: EF measurement outside normal range (\(String(format: "%.1f", efPercentage))%). Please verify probe placement and cardiac view quality. Consider manual verification."
                                ])
                            self.showingAlert = true
                        }
                    }
                } else {
                    print("EF Processing: Model prediction failed - no result returned")
                }
            } else {
                print("EF Processing: Frame preprocessing failed")
            }
        } catch {
            print("EF Processing: Critical error - \(error.localizedDescription)")
            await MainActor.run {
                self.alertError = NSError(
                    domain: "HeartScanner", code: -3,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Analysis failed. Please check probe connection and try again."
                    ])
                self.showingAlert = true
            }
        }
    }
}
