import SwiftUI

struct UpdateFirmwareView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        VStack {
            Text("⚠️")
                .font(.title)
            Text("Probe firmware is out-of-date")
            if !model.updating {
                Button("Update firmware") {
                    Task {
                        await model.updateFirmware()
                    }
                }
            } else {
                Text("Updating firmware...")
                Text("Please keep the app open and iQ plugged in.")
                    .fontWeight(.bold)
                if let progress = model.updateProgress {
                    Text("\(Int(progress.timeRemaining)) seconds remaining")
                    Text("\(Int(progress.fractionCompleted * 100))%")
                }
                ProgressView()
            }
        }
    }
}
