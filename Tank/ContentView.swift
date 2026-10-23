// Developed by Dave Todd with the help of his coding genie, Desiree Amira Todd

import SwiftUI
import Combine

// MARK: - Models & Enums

enum FuelType: String, Codable, CaseIterable, Identifiable {
    case e10 = "E10/91"
    case fuel95 = "95"
    case fuel98 = "98"
    case diesel = "Diesel"
    case premiumDiesel = "Premium Diesel"
    case lpg = "LPG"
    var id: String { rawValue }
}

struct CarProfile: Codable, Hashable {
    var make: String = ""
    var model: String = ""
    var carNickname: String = "My Car"
    var fuelType: FuelType = .e10
}

struct FuelEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date = Date()
    var odometer: Double
    var litres: Double
    var pricePerLitre: Double
    var calculatedEfficiency: Double? = nil

    var totalCost: Double { litres * pricePerLitre }

    func efficiency(distanceDriven: Double) -> Double? {
        guard litres > 0, distanceDriven > 0 else { return nil }
        return distanceDriven / litres
    }
}

// MARK: - Data Store

final class FuelStore: ObservableObject {
    @Published private(set) var entries: [FuelEntry] = []
    @Published var carProfile: CarProfile = CarProfile() {
        didSet { save() }
    }

    private let entriesKey = "fuelEntries"
    private let carProfileKey = "carProfile"

    init() {
        load()
    }

    func addEntry(_ entry: FuelEntry) {
        entries.append(entry)
        recalculateEfficiencies()
        save()
    }

    func deleteEntry(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        recalculateEfficiencies()
        save()
    }

    private func recalculateEfficiencies() {
        let sortedEntries = entries.sorted { $0.date < $1.date }
        var previousOdometer: Double?
        let updatedEntries = sortedEntries.map { entry -> FuelEntry in
            var updated = entry
            if let previous = previousOdometer {
                let distance = max(0, updated.odometer - previous)
                updated.calculatedEfficiency = updated.efficiency(distanceDriven: distance)
            } else {
                updated.calculatedEfficiency = nil
            }
            previousOdometer = updated.odometer
            return updated
        }
        entries = updatedEntries
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            UserDefaults.standard.set(data, forKey: entriesKey)
        }
        if let data = try? encoder.encode(carProfile) {
            UserDefaults.standard.set(data, forKey: carProfileKey)
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = UserDefaults.standard.data(forKey: entriesKey),
           let decoded = try? decoder.decode([FuelEntry].self, from: data) {
            entries = decoded
            recalculateEfficiencies()
        }
        if let data = UserDefaults.standard.data(forKey: carProfileKey),
           let decoded = try? decoder.decode(CarProfile.self, from: data) {
            carProfile = decoded
        }
    }
}

// MARK: - Main Views

struct ContentView: View {
    @StateObject private var store = FuelStore()
    @State private var showingAddEntry = false

    var body: some View {
        NavigationStack {
            List {
                Section("Dashboard") {
                    NavigationLink {
                        CarProfileView(store: store)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Car Profile").font(.headline)
                            Text(store.carProfile.carNickname).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        FuelChartView(entries: store.entries)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fuel Analytics").font(.headline)
                            Text("View price trends over time").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Fuel Entries") {
                    if store.entries.isEmpty {
                        Text("No entries yet. Tap + to add one.").foregroundStyle(.secondary)
                    } else {
                        ForEach(store.entries.sorted { $0.date > $1.date }) { entry in
                            FuelRow(entry: entry)
                        }
                        .onDelete(perform: store.deleteEntry)
                    }
                }
            }
            .navigationTitle("Tank")
            .toolbar {
                Button { showingAddEntry = true } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $showingAddEntry) {
                FuelEntryView(store: store)
            }
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Components

struct CarProfileView: View {
    @ObservedObject var store: FuelStore
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String = ""
    @State private var selectedFuel: FuelType = .e10

    var body: some View {
        Form {
            Section("Vehicle Details") {
                TextField("Nickname", text: $nickname)
                Picker("Preferred Fuel", selection: $selectedFuel) {
                    ForEach(FuelType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
            }
        }
        .navigationTitle("Car Profile")
        .onAppear {
            nickname = store.carProfile.carNickname
            selectedFuel = store.carProfile.fuelType
        }
        .toolbar {
            Button("Save") {
                store.carProfile.carNickname = nickname
                store.carProfile.fuelType = selectedFuel
                dismiss()
            }
        }
    }
}

struct FuelEntryView: View {
    @ObservedObject var store: FuelStore
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var odometerText = ""
    @State private var litresText = ""
    @State private var pricePerLitreText = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Fuel Details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Odometer", text: $odometerText).keyboardType(.decimalPad)
                    TextField("Litres", text: $litresText).keyboardType(.decimalPad)
                    TextField("Price per Litre", text: $pricePerLitreText).keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Add Fuel Entry")
            .alert("Invalid fuel entry", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("OK", role: .cancel) { validationMessage = nil }
            } message: {
                Text(validationMessage ?? "Please check the entered values.")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let odometer = Double(odometerText), odometer >= 0,
                              let litres = Double(litresText), litres > 0,
                              let pricePerLitre = Double(pricePerLitreText), pricePerLitre > 0 else {
                            validationMessage = "Enter a valid odometer reading, litres greater than zero, and price per litre greater than zero."
                            return
                        }
                        let entry = FuelEntry(date: date, odometer: odometer, litres: litres, pricePerLitre: pricePerLitre)
                        store.addEntry(entry)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct FuelRow: View {
    let entry: FuelEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.date.formatted(date: .abbreviated, time: .omitted)).font(.headline)
            HStack {
                Text(String(format: "%.1f km", entry.odometer))
                Spacer()
                Text(String(format: "$%.2f", entry.totalCost))
            }
            .font(.subheadline).foregroundStyle(.secondary)
            if let efficiency = entry.calculatedEfficiency {
                Text(String(format: "Efficiency: %.2f km/L", efficiency))
                    .font(.caption).foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}
