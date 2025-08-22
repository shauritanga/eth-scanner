import ButterflyImagingKit
import SwiftUI

struct PresetPicker: View {
    @Binding var controlPreset: ImagingPreset?
    @Binding var availablePresets: [ImagingPreset]

    var body: some View {
        HStack {
//            Text("Preset:")
            Picker("Preset", selection: $controlPreset) {
                if controlPreset == nil {
                    Text("---").tag(nil as ImagingPreset?)
                }
                ForEach(availablePresets, id: \.self) {
                    Text($0.name).tag($0 as ImagingPreset?)
                }
            }
        }
    }
}
