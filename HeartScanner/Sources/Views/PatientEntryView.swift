import Foundation
import SwiftUI

/// Professional patient information entry form
struct PatientEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var patientID = ""
    @State private var age = ""
    @State private var selectedGender: Patient.Gender = .notSpecified
    @State private var weight = ""
    @State private var height = ""
    @State private var showingValidationErrors = false
    @State private var validationErrors: [String] = []
    @State private var isStartingScan = false
    @State private var isFormValid = false
    @State private var cachedBMI: Double? = nil

    // Focus management
    @FocusState private var focusedField: Field?

    enum Field {
        case patientID, age, weight, height
    }

    var body: some View {
        Form {
            // Header section
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)

                    Text("Patient Information")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Enter patient details for cardiac scan")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            // Patient ID section
            Section {
                HStack {
                    Image(systemName: "person.text.rectangle")
                        .foregroundColor(.blue)
                        .frame(width: 24)

                    TextField("Patient ID", text: $patientID)
                        .focused($focusedField, equals: .patientID)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                        .onTapGesture {
                            focusedField = .patientID
                        }
                        .onChange(of: patientID) {
                            updateFormValidation()
                        }
                }
            } header: {
                Text("Patient Identification")
            } footer: {
                Text("Unique identifier for the patient (required)")
                    .font(.caption)
            }

            // Demographics section
            Section {
                // Age
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                        .frame(width: 24)

                    TextField("Age", text: $age)
                        .focused($focusedField, equals: .age)
                        .keyboardType(.numberPad)
                        .onTapGesture {
                            focusedField = .age
                        }
                        .onChange(of: age) {
                            updateFormValidation()
                        }

                    Text("years")
                        .foregroundColor(.secondary)
                }

                // Gender
                HStack {
                    Image(systemName: "person.2")
                        .foregroundColor(.blue)
                        .frame(width: 24)

                    Picker("Gender", selection: $selectedGender) {
                        ForEach(Patient.Gender.allCases, id: \.self) { gender in
                            Text(gender.displayName).tag(gender)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            } header: {
                Text("Demographics")
            }

            // Physical measurements section
            Section {
                // Weight
                HStack {
                    Image(systemName: "scalemass")
                        .foregroundColor(.blue)
                        .frame(width: 24)

                    TextField("Weight", text: $weight)
                        .focused($focusedField, equals: .weight)
                        .keyboardType(.decimalPad)
                        .onTapGesture {
                            focusedField = .weight
                        }
                        .onChange(of: weight) {
                            updateFormValidation()
                            updateBMI()
                        }

                    Text("kg")
                        .foregroundColor(.secondary)
                }

                // Height
                HStack {
                    Image(systemName: "ruler")
                        .foregroundColor(.blue)
                        .frame(width: 24)

                    TextField("Height", text: $height)
                        .focused($focusedField, equals: .height)
                        .keyboardType(.decimalPad)
                        .onTapGesture {
                            focusedField = .height
                        }
                        .onChange(of: height) {
                            updateFormValidation()
                            updateBMI()
                        }

                    Text("cm")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Physical Measurements")
            } footer: {
                if let bmi = cachedBMI {
                    Text("BMI: \(String(format: "%.1f", bmi)) (\(bmiCategory(bmi)))")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            // Action buttons section
            Section {
                VStack(spacing: 12) {
                    // Start scan button
                    Button(action: startScanWithPatient) {
                        HStack {
                            if isStartingScan {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "heart.text.square")
                            }
                            Text(isStartingScan ? "Continuing..." : "Continue")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStartingScan || !isFormValid)

                    // Anonymous scan option
                    Button("Continue Without Patient Info") {
                        startAnonymousScan()
                    }
                    .foregroundColor(.secondary)
                }
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("New Patient")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // ToolbarItem(placement: .navigationBarLeading) {
            //     Button("Cancel") {
            //         dismiss()
            //     }
            // }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save Patient") {
                    savePatientOnly()
                }
                .disabled(!isFormValid)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .alert("Validation Errors", isPresented: $showingValidationErrors) {
            Button("OK") {}
        } message: {
            Text(validationErrors.joined(separator: "\n"))
        }
        .onAppear {
            updateFormValidation()
            updateBMI()
        }
    }

    // MARK: - Computed Properties

    private func calculateBMI() -> Double? {
        guard let weightValue = Double(weight),
            let heightValue = Double(height),
            weightValue > 0,
            heightValue > 0
        else {
            return nil
        }

        let heightInMeters = heightValue / 100.0
        return weightValue / (heightInMeters * heightInMeters)
    }

    private func bmiCategory(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5: return "Underweight"
        case 18.5..<25.0: return "Normal"
        case 25.0..<30.0: return "Overweight"
        case 30.0...: return "Obese"
        default: return "Unknown"
        }
    }

    // MARK: - Validation

    private func validateInputs() -> [String] {
        var errors: [String] = []

        // Patient ID validation
        if patientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Patient ID is required")
        }

        // Age validation
        if let ageValue = Int(age) {
            if ageValue <= 0 || ageValue >= 150 {
                errors.append("Age must be between 1 and 149 years")
            }
        } else if !age.isEmpty {
            errors.append("Age must be a valid number")
        }

        // Weight validation
        if let weightValue = Double(weight) {
            if weightValue <= 0 || weightValue >= 1000 {
                errors.append("Weight must be between 1 and 999 kg")
            }
        } else if !weight.isEmpty {
            errors.append("Weight must be a valid number")
        }

        // Height validation
        if let heightValue = Double(height) {
            if heightValue <= 0 || heightValue >= 300 {
                errors.append("Height must be between 1 and 299 cm")
            }
        } else if !height.isEmpty {
            errors.append("Height must be a valid number")
        }

        return errors
    }

    // MARK: - Form Validation

    private func updateFormValidation() {
        // Debounced validation to improve performance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let hasRequiredFields =
                !patientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !age.isEmpty
                && !weight.isEmpty
                && !height.isEmpty

            let hasValidInputs = validateInputs().isEmpty

            isFormValid = hasRequiredFields && hasValidInputs
        }
    }

    private func updateBMI() {
        // Debounced BMI calculation to improve performance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            cachedBMI = calculateBMI()
        }
    }

    // MARK: - Actions

    private func startScanWithPatient() {
        let errors = validateInputs()
        if !errors.isEmpty {
            validationErrors = errors
            showingValidationErrors = true
            return
        }

        isStartingScan = true

        // Create patient object
        let patient = Patient(
            patientID: patientID.trimmingCharacters(in: .whitespacesAndNewlines),
            age: Int(age) ?? 0,
            gender: selectedGender,
            weight: Double(weight) ?? 0.0,
            height: Double(height) ?? 0.0
        )

        // Store patient for current scan session
        PatientSessionManager.shared.setCurrentPatient(patient)

        // Dismiss and start imaging using the original Model approach
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isStartingScan = false
            dismiss()
            // Start imaging using Model - this will automatically transition to scanning view
            Model.shared.startImaging()
        }
    }

    private func startAnonymousScan() {
        PatientSessionManager.shared.clearCurrentPatient()
        dismiss()
        // Start imaging using Model - this will automatically transition to scanning view
        Model.shared.startImaging()
    }

    private func savePatientOnly() {
        let errors = validateInputs()
        if !errors.isEmpty {
            validationErrors = errors
            showingValidationErrors = true
            return
        }

        let patient = Patient(
            patientID: patientID.trimmingCharacters(in: .whitespacesAndNewlines),
            age: Int(age) ?? 0,
            gender: selectedGender,
            weight: Double(weight) ?? 0.0,
            height: Double(height) ?? 0.0
        )

        // Save patient to history (without scan)
        PatientSessionManager.shared.savePatient(patient)

        dismiss()
    }
}

// MARK: - Patient Session Manager

class PatientSessionManager: ObservableObject {
    static let shared = PatientSessionManager()

    @Published var currentPatient: Patient?
    private var savedPatients: [Patient] = []

    private init() {
        loadSavedPatients()
    }

    func setCurrentPatient(_ patient: Patient) {
        currentPatient = patient
        savePatient(patient)
    }

    func clearCurrentPatient() {
        currentPatient = nil
    }

    func savePatient(_ patient: Patient) {
        // Remove existing patient with same ID
        savedPatients.removeAll { $0.patientID == patient.patientID }
        savedPatients.append(patient)
        persistPatients()
    }

    func getPatient(by id: String) -> Patient? {
        return savedPatients.first { $0.patientID == id }
    }

    func getAllPatients() -> [Patient] {
        return savedPatients.sorted { $0.createdAt > $1.createdAt }
    }

    private func loadSavedPatients() {
        if let data = UserDefaults.standard.data(forKey: "savedPatients") {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                savedPatients = try decoder.decode([Patient].self, from: data)
            } catch {
                print("Error loading saved patients: \(error)")
            }
        }
    }

    private func persistPatients() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(savedPatients)
            UserDefaults.standard.set(data, forKey: "savedPatients")
        } catch {
            print("Error saving patients: \(error)")
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let startScanWithPatient = Notification.Name("startScanWithPatient")
    static let startAnonymousScan = Notification.Name("startAnonymousScan")
    static let navigateToScanningView = Notification.Name("navigateToScanningView")
    static let navigateToScanning = Notification.Name("navigateToScanning")
}

// MARK: - Preview

struct PatientEntryView_Previews: PreviewProvider {
    static var previews: some View {
        PatientEntryView()
    }
}
