import Foundation
import UIKit
import Combine

/// Manages scan history storage, retrieval, and operations
class ScanHistoryManager: ObservableObject {
    static let shared = ScanHistoryManager()
    
    @Published var scanRecords: [ScanRecord] = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var selectedDateRange: DateRange = .all
    @Published var selectedQualityFilter: QualityFilter = .all
    
    private let userDefaults = UserDefaults.standard
    private let documentsDirectory: URL
    private let scansDirectory: URL
    
    enum DateRange: String, CaseIterable {
        case all = "All Time"
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
        case year = "This Year"
        
        var dateFilter: (Date) -> Bool {
            let calendar = Calendar.current
            let now = Date()
            
            switch self {
            case .all:
                return { _ in true }
            case .today:
                return { calendar.isDate($0, inSameDayAs: now) }
            case .week:
                return { calendar.isDate($0, equalTo: now, toGranularity: .weekOfYear) }
            case .month:
                return { calendar.isDate($0, equalTo: now, toGranularity: .month) }
            case .year:
                return { calendar.isDate($0, equalTo: now, toGranularity: .year) }
            }
        }
    }
    
    enum QualityFilter: String, CaseIterable {
        case all = "All Quality"
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        
        var qualityFilter: (ScanRecord.QualityMetrics.QualityRating) -> Bool {
            switch self {
            case .all:
                return { _ in true }
            case .excellent:
                return { $0 == .excellent }
            case .good:
                return { $0 == .good }
            case .fair:
                return { $0 == .fair }
            case .poor:
                return { $0 == .poor }
            }
        }
    }
    
    private init() {
        // Setup directories
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        scansDirectory = documentsDirectory.appendingPathComponent("Scans")
        
        // Create scans directory if it doesn't exist
        try? FileManager.default.createDirectory(at: scansDirectory, withIntermediateDirectories: true)
        
        // Load existing scans
        loadScanHistory()
        
        // Load sample data for development
        #if DEBUG
        if scanRecords.isEmpty {
            loadSampleData()
        }
        #endif
    }
    
    // MARK: - Core Operations
    
    /// Save a new scan record
    func saveScan(_ scanRecord: ScanRecord) {
        DispatchQueue.main.async {
            self.scanRecords.insert(scanRecord, at: 0) // Insert at beginning for newest first
            self.persistScanHistory()
            print("ScanHistoryManager: Saved scan \(scanRecord.id)")
        }
    }
    
    /// Delete a scan record
    func deleteScan(_ scanRecord: ScanRecord) {
        DispatchQueue.main.async {
            self.scanRecords.removeAll { $0.id == scanRecord.id }
            self.persistScanHistory()
            self.deleteAssociatedFiles(for: scanRecord)
            print("ScanHistoryManager: Deleted scan \(scanRecord.id)")
        }
    }
    
    /// Update clinical notes for a scan
    func updateClinicalNotes(for scanID: String, notes: String) {
        if let index = scanRecords.firstIndex(where: { $0.id == scanID }) {
            var updatedRecord = scanRecords[index]
            // Create new record with updated notes (since ScanRecord is immutable)
            let newRecord = ScanRecord(
                patient: updatedRecord.patient,
                analysisResults: updatedRecord.analysisResults,
                imageData: updatedRecord.imageData,
                clinicalNotes: notes,
                scanDuration: updatedRecord.scanDuration
            )
            scanRecords[index] = newRecord
            persistScanHistory()
        }
    }
    
    // MARK: - Search and Filter
    
    /// Get filtered scan records based on current filters
    var filteredScanRecords: [ScanRecord] {
        return scanRecords.filter { record in
            // Text search
            let matchesSearch = searchText.isEmpty ||
                record.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                record.patient?.patientID.localizedCaseInsensitiveContains(searchText) == true ||
                record.clinicalNotes.localizedCaseInsensitiveContains(searchText)
            
            // Date filter
            let matchesDate = selectedDateRange.dateFilter(record.scanDate)
            
            // Quality filter
            let matchesQuality = selectedQualityFilter.qualityFilter(record.qualityMetrics.overallQuality)
            
            return matchesSearch && matchesDate && matchesQuality
        }
    }
    
    /// Get scans for a specific patient
    func getScansForPatient(_ patientID: String) -> [ScanRecord] {
        return scanRecords.filter { $0.patient?.patientID == patientID }
    }
    
    /// Get scan statistics
    var scanStatistics: ScanStatistics {
        let totalScans = scanRecords.count
        let scansWithPatients = scanRecords.filter { $0.patient != nil }.count
        let averageEF = scanRecords.compactMap { $0.analysisResults.ejectionFraction }.reduce(0, +) / Double(max(1, scanRecords.count))
        let qualityDistribution = Dictionary(grouping: scanRecords) { $0.qualityMetrics.overallQuality }
        
        return ScanStatistics(
            totalScans: totalScans,
            scansWithPatients: scansWithPatients,
            averageEF: averageEF,
            qualityDistribution: qualityDistribution.mapValues { $0.count }
        )
    }
    
    struct ScanStatistics {
        let totalScans: Int
        let scansWithPatients: Int
        let averageEF: Double
        let qualityDistribution: [ScanRecord.QualityMetrics.QualityRating: Int]
    }
    
    // MARK: - Persistence
    
    private func loadScanHistory() {
        isLoading = true
        
        DispatchQueue.global(qos: .background).async {
            do {
                let data = self.userDefaults.data(forKey: "scanHistory") ?? Data()
                if !data.isEmpty {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let records = try decoder.decode([ScanRecord].self, from: data)
                    
                    DispatchQueue.main.async {
                        self.scanRecords = records.sorted { $0.scanDate > $1.scanDate }
                        self.isLoading = false
                        print("ScanHistoryManager: Loaded \(records.count) scan records")
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                }
            } catch {
                print("ScanHistoryManager: Error loading scan history: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func persistScanHistory() {
        DispatchQueue.global(qos: .background).async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(self.scanRecords)
                self.userDefaults.set(data, forKey: "scanHistory")
                print("ScanHistoryManager: Persisted \(self.scanRecords.count) scan records")
            } catch {
                print("ScanHistoryManager: Error persisting scan history: \(error)")
            }
        }
    }
    
    private func deleteAssociatedFiles(for scanRecord: ScanRecord) {
        // Delete thumbnail, full image, and video files
        let filesToDelete = [
            scanRecord.imageData.thumbnailPath,
            scanRecord.imageData.fullImagePath,
            scanRecord.imageData.videoPath
        ].compactMap { $0 }
        
        for fileName in filesToDelete {
            let fileURL = scansDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    // MARK: - Sample Data
    
    private func loadSampleData() {
        scanRecords = ScanRecord.sampleRecords
        persistScanHistory()
        print("ScanHistoryManager: Loaded sample data")
    }
    
    /// Clear all scan history (for testing)
    func clearAllScans() {
        scanRecords.removeAll()
        persistScanHistory()
        
        // Clear scan files directory
        try? FileManager.default.removeItem(at: scansDirectory)
        try? FileManager.default.createDirectory(at: scansDirectory, withIntermediateDirectories: true)
        
        print("ScanHistoryManager: Cleared all scan history")
    }
}
