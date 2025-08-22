import SwiftUI

let clientKey = "E4BEB4-5955BC-CFC9E6-FB5825-EC2974-V3"
@main
struct HeartScannerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(model: Model.shared)
                .preferredColorScheme(.dark)
        }
    }
}
