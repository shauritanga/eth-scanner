import ButterflyImagingKit
import Foundation
import SwiftUI

/// Main content coordinator with proper iOS navigation and appearance
struct ContentView: View {
    @ObservedObject var model: Model

    var body: some View {
        Group {
            switch model.stage {
            case .startingUp:
                // iOS-style initialization screen
                InitializationView()

            case .ready:
                // Home screen with device status, navigation, and recent scans
                NavigationStack {
                    HomeView(model: model)
                }

            case .updateNeeded:
                // Firmware update interface
                UpdateFirmwareView()
                    .environmentObject(model)

            case .readyToScan:
                // Scanning interface - ready to scan but not yet started
                ScanningView(model: model)

            case .startingImaging:
                // Transition directly to imaging - no preparation screen needed
                ScanningView(model: model)

            case .imaging:
                // Active scanning interface - use the original stage-based approach
                ScanningView(model: model)
            }
        }
        .preferredColorScheme(.dark)
        .tint(.blue)
        .onAppear {
            setupApp()
        }
        .alert(
            "Error",
            isPresented: $model.showingAlert,
            presenting: model.alertError,
            actions: { _ in Button("OK", role: .cancel) { model.clearError() } },
            message: { detail in Text("Error: \(String(describing: detail))") }
        )
    }

    private func setupApp() {
        // Only initialize Butterfly SDK - models are already loaded during app startup
        Task {
            try? await model.startup(clientKey: clientKey)
        }
    }
}

// MARK: - iOS-Style View Components

struct InitializationView: View {
    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // App icon or logo area
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)

            VStack(spacing: 16) {
                Text("HeartScanner")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Professional Cardiac Ultrasound")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)

                Text("Initializing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {

        return ContentView(model: Model.shared)
            .preferredColorScheme(.dark)
    }
}
