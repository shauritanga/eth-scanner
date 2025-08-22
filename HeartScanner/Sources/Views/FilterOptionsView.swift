import SwiftUI

/// Professional filter options for scan history
struct FilterOptionsView: View {
    @ObservedObject var historyManager: ScanHistoryManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Date Range") {
                    ForEach(ScanHistoryManager.DateRange.allCases, id: \.self) { range in
                        HStack {
                            Text(range.rawValue)
                            Spacer()
                            if historyManager.selectedDateRange == range {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            historyManager.selectedDateRange = range
                        }
                    }
                }
                
                Section("Quality Filter") {
                    ForEach(ScanHistoryManager.QualityFilter.allCases, id: \.self) { quality in
                        HStack {
                            HStack(spacing: 8) {
                                if quality != .all {
                                    QualityIndicator(quality: quality)
                                }
                                Text(quality.rawValue)
                            }
                            Spacer()
                            if historyManager.selectedQualityFilter == quality {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            historyManager.selectedQualityFilter = quality
                        }
                    }
                }
                
                Section("Actions") {
                    Button("Clear All Filters") {
                        historyManager.selectedDateRange = .all
                        historyManager.selectedQualityFilter = .all
                        historyManager.searchText = ""
                    }
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("Filter Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct QualityIndicator: View {
    let quality: ScanHistoryManager.QualityFilter
    
    var body: some View {
        Circle()
            .fill(backgroundColor)
            .frame(width: 12, height: 12)
    }
    
    private var backgroundColor: Color {
        switch quality {
        case .all: return .gray
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        }
    }
}

struct FilterOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        FilterOptionsView(historyManager: ScanHistoryManager.shared)
    }
}
