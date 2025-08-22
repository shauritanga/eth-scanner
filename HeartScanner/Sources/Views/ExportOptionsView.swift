import SwiftUI
import PDFKit

/// Professional export options for scan records
struct ExportOptionsView: View {
    let scans: [ScanRecord]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .pdf
    @State private var includePatientInfo = true
    @State private var includeImages = true
    @State private var includeAnalysis = true
    @State private var includeNotes = true
    @State private var isExporting = false
    @State private var exportError: String?
    
    enum ExportFormat: String, CaseIterable {
        case pdf = "PDF Report"
        case images = "Images Only"
        case csv = "CSV Data"
        case json = "JSON Data"
        
        var icon: String {
            switch self {
            case .pdf: return "doc.richtext"
            case .images: return "photo.stack"
            case .csv: return "tablecells"
            case .json: return "curlybraces"
            }
        }
        
        var description: String {
            switch self {
            case .pdf: return "Complete medical report with images and analysis"
            case .images: return "Scan images and thumbnails"
            case .csv: return "Analysis data in spreadsheet format"
            case .json: return "Raw data in JSON format"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Export format selection
                Section("Export Format") {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        HStack {
                            Image(systemName: format.icon)
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.rawValue)
                                    .font(.headline)
                                
                                Text(format.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedFormat == format {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedFormat = format
                        }
                    }
                }
                
                // Content options
                if selectedFormat == .pdf {
                    Section("Include in Report") {
                        Toggle("Patient Information", isOn: $includePatientInfo)
                        Toggle("Scan Images", isOn: $includeImages)
                        Toggle("Analysis Results", isOn: $includeAnalysis)
                        Toggle("Clinical Notes", isOn: $includeNotes)
                    }
                }
                
                // Scan summary
                Section("Export Summary") {
                    HStack {
                        Text("Scans to Export")
                        Spacer()
                        Text("\(scans.count)")
                            .fontWeight(.medium)
                    }
                    
                    if scans.count == 1 {
                        Text(scans.first?.displayTitle ?? "Unknown")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Multiple scans selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Export button
                Section {
                    Button(action: exportScans) {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Exporting...")
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export \(selectedFormat.rawValue)")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isExporting)
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Export Error", isPresented: .constant(exportError != nil)) {
                Button("OK") {
                    exportError = nil
                }
            } message: {
                Text(exportError ?? "")
            }
        }
    }
    
    // MARK: - Export Functions
    
    private func exportScans() {
        isExporting = true
        
        Task {
            do {
                switch selectedFormat {
                case .pdf:
                    try await exportAsPDF()
                case .images:
                    try await exportAsImages()
                case .csv:
                    try await exportAsCSV()
                case .json:
                    try await exportAsJSON()
                }
                
                await MainActor.run {
                    isExporting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                }
            }
        }
    }
    
    private func exportAsPDF() async throws {
        let pdfData = try await PDFExporter.generateReport(
            scans: scans,
            includePatientInfo: includePatientInfo,
            includeImages: includeImages,
            includeAnalysis: includeAnalysis,
            includeNotes: includeNotes
        )
        
        try await shareFile(data: pdfData, filename: "HeartScanner_Report.pdf", type: "application/pdf")
    }
    
    private func exportAsImages() async throws {
        // Export scan images as a zip file
        let imageData = try await ImageExporter.exportImages(scans: scans)
        try await shareFile(data: imageData, filename: "HeartScanner_Images.zip", type: "application/zip")
    }
    
    private func exportAsCSV() async throws {
        let csvData = try await CSVExporter.exportData(scans: scans)
        try await shareFile(data: csvData, filename: "HeartScanner_Data.csv", type: "text/csv")
    }
    
    private func exportAsJSON() async throws {
        let jsonData = try await JSONExporter.exportData(scans: scans)
        try await shareFile(data: jsonData, filename: "HeartScanner_Data.json", type: "application/json")
    }
    
    @MainActor
    private func shareFile(data: Data, filename: String, type: String) async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: tempURL)
        
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
}

// MARK: - Export Services

struct PDFExporter {
    static func generateReport(
        scans: [ScanRecord],
        includePatientInfo: Bool,
        includeImages: Bool,
        includeAnalysis: Bool,
        includeNotes: Bool
    ) async throws -> Data {
        // Create PDF document
        let pdfMetaData = [
            kCGPDFContextCreator: "HeartScanner",
            kCGPDFContextAuthor: "HeartScanner App",
            kCGPDFContextTitle: "Cardiac Scan Report"
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter size
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let data = renderer.pdfData { context in
            for (index, scan) in scans.enumerated() {
                context.beginPage()
                
                var yPosition: CGFloat = 50
                
                // Header
                yPosition = drawHeader(in: context.cgContext, at: yPosition, pageRect: pageRect, scanIndex: index + 1, totalScans: scans.count)
                
                // Patient info
                if includePatientInfo, let patient = scan.patient {
                    yPosition = drawPatientInfo(in: context.cgContext, at: yPosition, patient: patient)
                }
                
                // Scan info
                yPosition = drawScanInfo(in: context.cgContext, at: yPosition, scan: scan)
                
                // Analysis results
                if includeAnalysis {
                    yPosition = drawAnalysisResults(in: context.cgContext, at: yPosition, scan: scan)
                }
                
                // Clinical notes
                if includeNotes && !scan.clinicalNotes.isEmpty {
                    yPosition = drawClinicalNotes(in: context.cgContext, at: yPosition, notes: scan.clinicalNotes)
                }
                
                // Footer
                drawFooter(in: context.cgContext, pageRect: pageRect)
            }
        }
        
        return data
    }
    
    private static func drawHeader(in context: CGContext, at yPosition: CGFloat, pageRect: CGRect, scanIndex: Int, totalScans: Int) -> CGFloat {
        let title = "HeartScanner Cardiac Analysis Report"
        let subtitle = "Scan \(scanIndex) of \(totalScans)"
        
        // Title
        let titleFont = UIFont.boldSystemFont(ofSize: 20)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ]
        
        let titleSize = title.size(withAttributes: titleAttributes)
        let titleRect = CGRect(x: (pageRect.width - titleSize.width) / 2, y: yPosition, width: titleSize.width, height: titleSize.height)
        title.draw(in: titleRect, withAttributes: titleAttributes)
        
        // Subtitle
        let subtitleFont = UIFont.systemFont(ofSize: 14)
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: UIColor.gray
        ]
        
        let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
        let subtitleRect = CGRect(x: (pageRect.width - subtitleSize.width) / 2, y: yPosition + 30, width: subtitleSize.width, height: subtitleSize.height)
        subtitle.draw(in: subtitleRect, withAttributes: subtitleAttributes)
        
        return yPosition + 70
    }
    
    private static func drawPatientInfo(in context: CGContext, at yPosition: CGFloat, patient: Patient) -> CGFloat {
        let sectionTitle = "Patient Information"
        let font = UIFont.boldSystemFont(ofSize: 16)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        
        sectionTitle.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: attributes)
        
        let infoFont = UIFont.systemFont(ofSize: 12)
        let infoAttributes: [NSAttributedString.Key: Any] = [.font: infoFont, .foregroundColor: UIColor.black]
        
        let patientInfo = [
            "Patient ID: \(patient.patientID)",
            "Age: \(patient.age) years",
            "Gender: \(patient.gender.displayName)",
            "Weight: \(String(format: "%.1f", patient.weight)) kg",
            "Height: \(String(format: "%.0f", patient.height)) cm",
            "BMI: \(String(format: "%.1f", patient.bmi)) (\(patient.bmiCategory))"
        ]
        
        var currentY = yPosition + 25
        for info in patientInfo {
            info.draw(at: CGPoint(x: 70, y: currentY), withAttributes: infoAttributes)
            currentY += 15
        }
        
        return currentY + 20
    }
    
    private static func drawScanInfo(in context: CGContext, at yPosition: CGFloat, scan: ScanRecord) -> CGFloat {
        let sectionTitle = "Scan Information"
        let font = UIFont.boldSystemFont(ofSize: 16)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        
        sectionTitle.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: attributes)
        
        let infoFont = UIFont.systemFont(ofSize: 12)
        let infoAttributes: [NSAttributedString.Key: Any] = [.font: infoFont, .foregroundColor: UIColor.black]
        
        let scanInfo = [
            "Date: \(scan.formattedDate)",
            "Duration: \(String(format: "%.0f", scan.scanDuration)) seconds",
            "Device: \(scan.deviceInfo.deviceName)",
            "Probe: \(scan.deviceInfo.probeType)",
            "Quality: \(scan.qualityMetrics.overallQuality.rawValue)"
        ]
        
        var currentY = yPosition + 25
        for info in scanInfo {
            info.draw(at: CGPoint(x: 70, y: currentY), withAttributes: infoAttributes)
            currentY += 15
        }
        
        return currentY + 20
    }
    
    private static func drawAnalysisResults(in context: CGContext, at yPosition: CGFloat, scan: ScanRecord) -> CGFloat {
        let sectionTitle = "Analysis Results"
        let font = UIFont.boldSystemFont(ofSize: 16)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        
        sectionTitle.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: attributes)
        
        let infoFont = UIFont.systemFont(ofSize: 12)
        let infoAttributes: [NSAttributedString.Key: Any] = [.font: infoFont, .foregroundColor: UIColor.black]
        
        var analysisInfo: [String] = []
        
        if let ef = scan.analysisResults.ejectionFraction {
            analysisInfo.append("Ejection Fraction: \(String(format: "%.1f", ef))%")
            if let confidence = scan.analysisResults.efConfidence {
                analysisInfo.append("Confidence: \(String(format: "%.0f", confidence * 100))%")
            }
        }
        
        for measurement in scan.analysisResults.measurements {
            analysisInfo.append("\(measurement.type.displayName): \(String(format: "%.1f", measurement.value)) \(measurement.unit)")
        }
        
        analysisInfo.append("AI Model: \(scan.analysisResults.aiModelVersion)")
        analysisInfo.append("Processing Time: \(String(format: "%.1f", scan.analysisResults.processingTime))s")
        
        var currentY = yPosition + 25
        for info in analysisInfo {
            info.draw(at: CGPoint(x: 70, y: currentY), withAttributes: infoAttributes)
            currentY += 15
        }
        
        return currentY + 20
    }
    
    private static func drawClinicalNotes(in context: CGContext, at yPosition: CGFloat, notes: String) -> CGFloat {
        let sectionTitle = "Clinical Notes"
        let font = UIFont.boldSystemFont(ofSize: 16)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        
        sectionTitle.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: attributes)
        
        let notesFont = UIFont.systemFont(ofSize: 12)
        let notesAttributes: [NSAttributedString.Key: Any] = [.font: notesFont, .foregroundColor: UIColor.black]
        
        let notesRect = CGRect(x: 70, y: yPosition + 25, width: 472, height: 100)
        notes.draw(in: notesRect, withAttributes: notesAttributes)
        
        return yPosition + 145
    }
    
    private static func drawFooter(in context: CGContext, pageRect: CGRect) {
        let footer = "Generated by HeartScanner • \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))"
        let font = UIFont.systemFont(ofSize: 10)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.gray]
        
        let footerSize = footer.size(withAttributes: attributes)
        let footerRect = CGRect(x: (pageRect.width - footerSize.width) / 2, y: pageRect.height - 30, width: footerSize.width, height: footerSize.height)
        footer.draw(in: footerRect, withAttributes: attributes)
    }
}

struct ImageExporter {
    static func exportImages(scans: [ScanRecord]) async throws -> Data {
        // For now, return empty data - would implement actual image export
        return Data()
    }
}

struct CSVExporter {
    static func exportData(scans: [ScanRecord]) async throws -> Data {
        var csvContent = "Patient ID,Scan Date,EF,Confidence,Quality,Notes\n"
        
        for scan in scans {
            let patientID = scan.patient?.patientID ?? "Anonymous"
            let scanDate = scan.formattedDate
            let ef = scan.analysisResults.ejectionFraction?.description ?? ""
            let confidence = scan.analysisResults.efConfidence?.description ?? ""
            let quality = scan.qualityMetrics.overallQuality.rawValue
            let notes = scan.clinicalNotes.replacingOccurrences(of: ",", with: ";")
            
            csvContent += "\(patientID),\(scanDate),\(ef),\(confidence),\(quality),\(notes)\n"
        }
        
        return csvContent.data(using: .utf8) ?? Data()
    }
}

struct JSONExporter {
    static func exportData(scans: [ScanRecord]) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(scans)
    }
}

struct ExportOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        ExportOptionsView(scans: ScanRecord.sampleRecords)
    }
}
