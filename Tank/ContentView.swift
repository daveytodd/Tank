// Developed by Dave Todd with the help of his coding genie, Desiree Amira Todd

import SwiftUI
import Combine

// MARK: - Models
enum FuelType: String, Codable, CaseIterable, Identifiable {
    case e10 = "E10/91", fuel95 = "95", fuel98 = "98", diesel = "Diesel", premiumDiesel = "Premium Diesel", lpg = "LPG"
    var id: String { rawValue }
}

struct CarProfile: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var make: String = ""
    var model: String = ""
    var carNickname: String = "My Car"
    var tankCapacity: Double = 51
    var fuelType: FuelType = .e10
    var title: String { "\(carNickname) · \(make) \(model)".trimmingCharacters(in: .whitespaces) }
}

struct FuelEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date = Date()
    var odometer: Double
    var litres: Double
    var pricePerLitre: Double
    var carId: UUID = UUID()
    var fuelType: FuelType = .e10
    var calculatedEfficiency: Double? = nil
    var totalCost: Double { litres * pricePerLitre }
    func efficiency(distanceDriven: Double) -> Double? { litres > 0 && distanceDriven > 0 ? distanceDriven / litres : nil }
}

final class FuelStore: ObservableObject {
    @Published private(set) var entries: [FuelEntry] = []
    @Published var carProfiles: [CarProfile] = [] { didSet { save() } }
    @Published var activeCarId: UUID? { didSet { save() } }
    var activeCar: CarProfile? { carProfiles.first(where: { $0.id == activeCarId }) }
    private let entriesKey = "fuelEntries", profilesKey = "carProfiles", activeKey = "activeCarId", legacyKey = "carProfile"
    init() { load() }
    func addCar(_ car: CarProfile) { carProfiles.append(car); activeCarId = car.id }
    func updateCar(_ car: CarProfile) { if let i = carProfiles.firstIndex(where: { $0.id == car.id }) { carProfiles[i] = car } }
    func deleteCar(_ car: CarProfile) {
        guard carProfiles.count > 1 else { return }
        carProfiles.removeAll { $0.id == car.id }
        if activeCarId == car.id { activeCarId = carProfiles[0].id }
    }
    func addEntry(_ entry: FuelEntry) { entries.append(entry); recalculateEfficiencies(); save() }
    func deleteEntry(at offsets: IndexSet, from shown: [FuelEntry]) {
        let ids = offsets.map { shown[$0].id }; entries.removeAll { ids.contains($0.id) }; recalculateEfficiencies(); save()
    }
    private func recalculateEfficiencies() {
        let sorted = entries.sorted { $0.date < $1.date }; var previous: [UUID: Double] = [:]
        entries = sorted.map { entry in
            var item = entry
            if let prior = previous[item.carId] { item.calculatedEfficiency = item.efficiency(distanceDriven: max(0, item.odometer - prior)) }
            else { item.calculatedEfficiency = nil }
            previous[item.carId] = item.odometer; return item
        }
    }
    private func save() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        if let d = try? e.encode(entries) { UserDefaults.standard.set(d, forKey: entriesKey) }
        if let d = try? e.encode(carProfiles) { UserDefaults.standard.set(d, forKey: profilesKey) }
        if let activeCarId { UserDefaults.standard.set(activeCarId.uuidString, forKey: activeKey) } else { UserDefaults.standard.removeObject(forKey: activeKey) }
    }
    private func load() {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        if let data = UserDefaults.standard.data(forKey: entriesKey), let value = try? d.decode([FuelEntry].self, from: data) { entries = value }
        if let data = UserDefaults.standard.data(forKey: profilesKey), let value = try? d.decode([CarProfile].self, from: data) { carProfiles = value }
        else if let data = UserDefaults.standard.data(forKey: legacyKey), let old = try? d.decode(CarProfile.self, from: data) { carProfiles = [old] }
        else { carProfiles = [] }
        activeCarId = UserDefaults.standard.string(forKey: activeKey).flatMap(UUID.init(uuidString:))
        if let activeCarId, !carProfiles.contains(where: { $0.id == activeCarId }) { self.activeCarId = carProfiles.first?.id }
        if activeCarId == nil, let first = carProfiles.first { activeCarId = first.id }
        recalculateEfficiencies(); save()
    }
}

struct ContentView: View {
    @StateObject private var store = FuelStore()
    @State private var showingAddEntry = false
    @State private var showingAddCar = false
    var body: some View {
        NavigationStack {
            Group {
                if store.carProfiles.isEmpty {
                    ContentUnavailableView { Label("No Cars Yet", systemImage: "car.side") } description: { Text("Add a vehicle to start tracking your fuel.") } actions: {
                        Button("Add First Car") { showingAddCar = true }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
                } else {
                    List {
                        Section("Vehicle") {
                            Picker("Active car", selection: Binding(get: { store.activeCarId ?? store.carProfiles[0].id }, set: { store.activeCarId = $0 })) {
                                ForEach(store.carProfiles) { car in Text(car.carNickname).tag(car.id) }
                            }.pickerStyle(.menu)
                            NavigationLink("Manage Car Profiles") { CarProfilesView(store: store) }
                        }
                        Section("Dashboard") {
                            NavigationLink { FuelChartView(entries: store.entries, cars: store.carProfiles) } label: {
                                VStack(alignment: .leading, spacing: 4) { Text("Fuel Analytics").font(.headline); Text("Compare cars and view trends").font(.subheadline).foregroundStyle(.secondary) }
                            }
                        }
                        if let activeCar = store.activeCar {
                            Section("\(activeCar.carNickname) Fuel Entries") {
                                let shown = store.entries.filter { $0.carId == activeCar.id }.sorted { $0.date > $1.date }
                                if shown.isEmpty { Text("No entries for this car yet. Tap + to add one.").foregroundStyle(.secondary) }
                                else { ForEach(shown) { entry in FuelRow(entry: entry) }.onDelete { store.deleteEntry(at: $0, from: shown) } }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tank")
            .toolbar { if !store.carProfiles.isEmpty { Button { showingAddEntry = true } label: { Image(systemName: "plus") } } }
            .sheet(isPresented: $showingAddEntry) { FuelEntryView(store: store) }
            .sheet(isPresented: $showingAddCar) { CarEditorView(car: CarProfile(), onSave: store.addCar) }
            .preferredColorScheme(.dark).background(Color.black)
        }
    }
}

struct CarProfilesView: View {
    @ObservedObject var store: FuelStore
    @State private var editing: CarProfile?
    @State private var adding = false
    var body: some View {
        Group {
            if store.carProfiles.isEmpty {
                ContentUnavailableView { Label("No Car Profiles", systemImage: "car.side") } description: { Text("Create your first profile to get started.") } actions: {
                    Button("Add First Car") { editing = CarProfile(); adding = true }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
            } else {
                List {
                    ForEach(store.carProfiles) { car in
                        HStack {
                            Button { store.activeCarId = car.id } label: {
                                VStack(alignment: .leading) { Text(car.carNickname).font(.headline); Text("\(car.make) \(car.model) · \(car.tankCapacity, specifier: "%.0f") L · \(car.fuelType.rawValue)").font(.caption).foregroundStyle(.secondary) }
                            }.buttonStyle(.plain)
                            Spacer(); Button { editing = car } label: { Image(systemName: "pencil") }
                        }
                    }.onDelete { offsets in offsets.map { store.carProfiles[$0] }.forEach(store.deleteCar) }
                    Button { editing = CarProfile(); adding = true } label: { Label("Add Car", systemImage: "plus") }
                }
            }
        }
        .navigationTitle("Car Profiles")
        .sheet(item: $editing) { car in CarEditorView(car: car, onSave: { updated in
            if adding { store.addCar(updated) } else { store.updateCar(updated) }; adding = false
        }) }
        .preferredColorScheme(.dark).background(Color.black)
    }
}

struct CarEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var car: CarProfile
    var onSave: (CarProfile) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle Details") {
                    TextField("Nickname", text: $car.carNickname)
                    TextField("Make", text: $car.make)
                    TextField("Model", text: $car.model)
                    TextField("Tank capacity (L)", value: $car.tankCapacity, format: .number).keyboardType(.decimalPad)
                    Picker("Preferred Fuel", selection: $car.fuelType) { ForEach(FuelType.allCases) { Text($0.rawValue).tag($0) } }
                }
            }
            .navigationTitle("Car Profile")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(car); dismiss() } }; ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

struct FuelEntryView: View {
    @ObservedObject var store: FuelStore
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var odometerText = ""
    @State private var litresText = ""
    @State private var pricePerLitreText = ""
    @State private var selectedCarId: UUID
    @State private var selectedFuel: FuelType
    @State private var validationMessage: String?
    @State private var showingAddCar = false
    init(store: FuelStore) { self.store = store; _selectedCarId = State(initialValue: store.activeCarId ?? store.carProfiles[0].id); _selectedFuel = State(initialValue: store.activeCar?.fuelType ?? .e10) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Fuel Details") {
                    HStack {
                        Picker("Vehicle", selection: $selectedCarId) {
                            ForEach(store.carProfiles) { car in Text(car.carNickname).tag(car.id) }
                        }
                        Spacer()
                        Button { showingAddCar = true } label: { Label("Add New Car", systemImage: "plus.circle.fill") }
                    }
                    .sheet(isPresented: $showingAddCar) {
                        CarEditorView(car: CarProfile(), onSave: { car in
                            store.addCar(car)
                            selectedCarId = car.id
                            selectedFuel = car.fuelType
                        })
                    }
                    .onChange(of: selectedCarId) { _, id in selectedFuel = store.carProfiles.first(where: { $0.id == id })?.fuelType ?? .e10 }
                    Picker("Fuel Type", selection: $selectedFuel) { ForEach(FuelType.allCases) { Text($0.rawValue).tag($0) } }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Odometer", text: $odometerText).keyboardType(.decimalPad)
                    TextField("Litres", text: $litresText).keyboardType(.decimalPad)
                    TextField("Price per Litre", text: $pricePerLitreText).keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Add Fuel Entry")
            .alert("Invalid fuel entry", isPresented: Binding(get: { validationMessage != nil }, set: { if !$0 { validationMessage = nil } })) { Button("OK", role: .cancel) { validationMessage = nil } } message: { Text(validationMessage ?? "Please check the entered values.") }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    guard let odometer = Double(odometerText), odometer >= 0, let litres = Double(litresText), litres > 0, let price = Double(pricePerLitreText), price > 0 else { validationMessage = "Enter valid odometer, litres, and price values."; return }
                    store.addEntry(FuelEntry(date: date, odometer: odometer, litres: litres, pricePerLitre: price, carId: selectedCarId, fuelType: selectedFuel)); dismiss()
                } }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }.preferredColorScheme(.dark)
    }
}

struct FuelRow: View {
    let entry: FuelEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.date.formatted(date: .abbreviated, time: .omitted)).font(.headline)
            HStack { Text(String(format: "%.1f km · %.1f L · %@", entry.odometer, entry.litres, entry.fuelType.rawValue)); Spacer(); Text(String(format: "$%.2f", entry.totalCost)) }
                .font(.subheadline).foregroundStyle(.secondary)
            if let efficiency = entry.calculatedEfficiency { Text(String(format: "Efficiency: %.2f km/L", efficiency)).font(.caption).foregroundStyle(.blue) }
        }.padding(.vertical, 4)
    }
}
