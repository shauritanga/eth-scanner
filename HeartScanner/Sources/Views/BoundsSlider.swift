import SwiftUI

struct BoundsSlider: View {
    var title: String
    @Binding var control: Double
    @Binding var bounds: ClosedRange<Measurement<UnitLength>>
    var onEditingChanged: ((Bool) -> Void) = { _ in }

    var body: some View {
        HStack {
//            Text("\(title):")
            Slider(
                value: $control,
                in: bounds.lowerBound.value...bounds.upperBound.value,
                label: {
                    Text("\(title):")
                },
                minimumValueLabel: {
                    Text(bounds.lowerBound.label)
                },
                maximumValueLabel: {
                    Text(bounds.upperBound.label)
                },
                onEditingChanged: onEditingChanged
            )
        }
    }
}

