import SwiftUI

@main
struct HeartScannerApp: App {
    @State private var model: Model?
    @State private var isLoading = true
    @State private var loadingError: Error?

    var body: some Scene {
        WindowGroup {
            Group {
                if isLoading {
                    SplashView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let model = model {
                    ContentView(model: model)
                        .preferredColorScheme(.dark)
                } else {
                    VStack {
                        Text("Failed to initialize app")
                        if let error = loadingError {
                            Text(error.localizedDescription)
                                .foregroundColor(.red)
                        }
                        Button("Retry") {
                            Task {
                                await initializeModel()
                            }
                        }
                    }
                    .padding()
                }
            }
            .task {
                await initializeModel()
            }
        }
    }

    private func initializeModel() async {
        isLoading = true
        loadingError = nil

        do {
            model = try await Model.create()
            isLoading = false
        } catch {
            loadingError = error
            isLoading = false
            print("Failed to initialize model: \(error)")
        }
    }
}
