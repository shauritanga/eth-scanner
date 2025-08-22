import Foundation

/// Patient information model for medical records
struct Patient: Codable, Identifiable, Equatable {
    let id: String
    let patientID: String
    let age: Int
    let gender: Gender
    let weight: Double // in kg
    let height: Double // in cm
    let createdAt: Date
    let updatedAt: Date
    
    enum Gender: String, CaseIterable, Codable {
        case male = "Male"
        case female = "Female"
        case other = "Other"
        case notSpecified = "Not Specified"
        
        var displayName: String {
            return self.rawValue
        }
        
        var medicalAbbreviation: String {
            switch self {
            case .male: return "M"
            case .female: return "F"
            case .other: return "O"
            case .notSpecified: return "NS"
            }
        }
    }
    
    init(patientID: String, age: Int, gender: Gender, weight: Double, height: Double) {
        self.id = UUID().uuidString
        self.patientID = patientID
        self.age = age
        self.gender = gender
        self.weight = weight
        self.height = height
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    /// Body Mass Index calculation
    var bmi: Double {
        let heightInMeters = height / 100.0
        return weight / (heightInMeters * heightInMeters)
    }
    
    /// BMI category for clinical reference
    var bmiCategory: String {
        switch bmi {
        case ..<18.5:
            return "Underweight"
        case 18.5..<25.0:
            return "Normal"
        case 25.0..<30.0:
            return "Overweight"
        case 30.0...:
            return "Obese"
        default:
            return "Unknown"
        }
    }
    
    /// Formatted display for medical records
    var displaySummary: String {
        return "\(patientID) • \(age)y \(gender.medicalAbbreviation) • BMI: \(String(format: "%.1f", bmi))"
    }
    
    /// Update patient information
    func updated(age: Int? = nil, gender: Gender? = nil, weight: Double? = nil, height: Double? = nil) -> Patient {
        var updated = self
        if let age = age { updated = Patient(patientID: updated.patientID, age: age, gender: updated.gender, weight: updated.weight, height: updated.height) }
        if let gender = gender { updated = Patient(patientID: updated.patientID, age: updated.age, gender: gender, weight: updated.weight, height: updated.height) }
        if let weight = weight { updated = Patient(patientID: updated.patientID, age: updated.age, gender: updated.gender, weight: weight, height: updated.height) }
        if let height = height { updated = Patient(patientID: updated.patientID, age: updated.age, gender: updated.gender, weight: updated.weight, height: height) }
        return updated
    }
}

// MARK: - Validation
extension Patient {
    /// Validate patient data for medical compliance
    var isValid: Bool {
        return !patientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               age > 0 && age < 150 &&
               weight > 0 && weight < 1000 &&
               height > 0 && height < 300
    }
    
    /// Validation errors for user feedback
    var validationErrors: [String] {
        var errors: [String] = []
        
        if patientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Patient ID is required")
        }
        
        if age <= 0 || age >= 150 {
            errors.append("Age must be between 1 and 149 years")
        }
        
        if weight <= 0 || weight >= 1000 {
            errors.append("Weight must be between 1 and 999 kg")
        }
        
        if height <= 0 || height >= 300 {
            errors.append("Height must be between 1 and 299 cm")
        }
        
        return errors
    }
}

// MARK: - Sample Data
extension Patient {
    /// Sample patient data for testing and previews
    static let samplePatients: [Patient] = [
        Patient(patientID: "P001", age: 45, gender: .male, weight: 75.0, height: 175.0),
        Patient(patientID: "P002", age: 32, gender: .female, weight: 62.0, height: 165.0),
        Patient(patientID: "P003", age: 67, gender: .male, weight: 82.0, height: 180.0),
        Patient(patientID: "P004", age: 28, gender: .female, weight: 58.0, height: 160.0)
    ]
    
    static var sample: Patient {
        return samplePatients[0]
    }
}
