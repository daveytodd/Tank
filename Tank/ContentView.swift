// Developed by Dave Todd with the help of his coding genie, Desiree Amira Todd

import SwiftUI
import Combine
import PhotosUI

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
    var tankCapacity: Double? = nil
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
    var receiptImageData: Data? = nil
    var totalCost: Double { litres * pricePerLitre }
    func efficiency(distanceDriven: Double) -> Double? { litres > 0 && distanceDriven > 0 ? distanceDriven / litres : nil }
}

private enum AppLinks {
    static let tankAppStore = URL(string: "https://apps.apple.com/au/app/tank-fuel-tracker/id6766018177")!
    static let coastFuelAppStore = URL(string: "https://apps.apple.com/au/app/coastfuel/id6820745150")!
    static let coastFuelApp = URL(string: "coastfuel://")!
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
    func updateEntry(_ entry: FuelEntry) { guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }; entries[index] = entry; save() }
    func deleteEntry(at offsets: IndexSet, from shown: [FuelEntry]) {
        let ids = offsets.map { shown[$0].id }; entries.removeAll { ids.contains($0.id) }; recalculateEfficiencies(); save()
    }
    func vehicleHistory(for carId: UUID) -> [FuelEntry] { entries.filter { $0.carId == carId }.sorted { $0.date > $1.date } }
    func priorEntry(for entry: FuelEntry) -> FuelEntry? {
        entries.filter { $0.carId == entry.carId && ($0.date < entry.date || ($0.date == entry.date && $0.id != entry.id)) }.max { $0.date < $1.date }
    }
    func vehicleAverageEfficiency(for carId: UUID) -> Double? {
        let values = entries.filter { $0.carId == carId }.compactMap(\.calculatedEfficiency).filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
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
    @Environment(\.openURL) private var openURL
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
                        Section("Discover CoastFuel") {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Find cheap fuel nearby with CoastFuel", systemImage: "fuelpump.fill").font(.headline)
                                Text("Discover nearby fuel prices with CoastFuel.").font(.subheadline).foregroundStyle(.secondary)
                                Button { openCoastFuel() } label: { Label("Open CoastFuel", systemImage: "arrow.up.right.square") }
                                    .buttonStyle(.borderedProminent)
                            }.padding(.vertical, 6)
                        }
                        if let activeCar = store.activeCar {
                            Section("\(activeCar.carNickname) Fuel Entries") {
                                let shown = store.vehicleHistory(for: activeCar.id)
                                if shown.isEmpty { Text("No entries for this car yet. Tap + to add one.").foregroundStyle(.secondary) }
                                else { ForEach(shown) { entry in NavigationLink { FuelEntryDetailView(entry: entry, store: store) } label: { FuelRow(entry: entry) } }.onDelete { store.deleteEntry(at: $0, from: shown) } }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tank")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: AppLinks.tankAppStore, subject: Text("Tank - Fuel Tracker"), message: Text("Track your fuel with Tank - Fuel Tracker: \(AppLinks.tankAppStore.absoluteString)")) {
                        Image(systemName: "square.and.arrow.up").accessibilityLabel("Share Tank")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { if !store.carProfiles.isEmpty { Button { showingAddEntry = true } label: { Image(systemName: "plus") } } }
            }
            .sheet(isPresented: $showingAddEntry) { FuelEntryView(store: store) }
            .sheet(isPresented: $showingAddCar) { CarEditorView(car: CarProfile(), onSave: store.addCar) }
            .preferredColorScheme(.dark).background(Color.black)
        }
    }
    private func openCoastFuel() {
        UIApplication.shared.open(AppLinks.coastFuelApp) { success in
            if !success { openURL(AppLinks.coastFuelAppStore) }
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
                                VStack(alignment: .leading) { Text(car.carNickname).font(.headline); Text("\(car.make) \(car.model) · \(car.tankCapacity.map { String(format: "%.0f L", $0) } ?? "Tank size not set") · \(car.fuelType.rawValue)").font(.caption).foregroundStyle(.secondary) }
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
    @State private var tankCapacityText: String
    var onSave: (CarProfile) -> Void
    init(car: CarProfile, onSave: @escaping (CarProfile) -> Void) {
        _car = State(initialValue: car)
        _tankCapacityText = State(initialValue: car.tankCapacity.map { String($0) } ?? "")
        self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle Details") {
                    TextField("Nickname", text: $car.carNickname)
                    TextField("Make", text: $car.make)
                    TextField("Model", text: $car.model)
                    TextField("Tank capacity (L)", text: $tankCapacityText, prompt: Text("e.g. 50")).keyboardType(.decimalPad)
                    Picker("Preferred Fuel", selection: $car.fuelType) { ForEach(FuelType.allCases) { Text($0.rawValue).tag($0) } }
                }
            }
            .navigationTitle("Car Profile")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { car.tankCapacity = Double(tankCapacityText); onSave(car); dismiss() } }; ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
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
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Vehicle", selection: $selectedCarId) { ForEach(store.carProfiles) { car in Text(car.carNickname).tag(car.id) } }
                            .onChange(of: selectedCarId) { _, id in selectedFuel = store.carProfiles.first(where: { $0.id == id })?.fuelType ?? .e10 }
                        Button { showingAddCar = true } label: { Label("Add New Car", systemImage: "plus.circle.fill").font(.body.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                            .buttonStyle(.plain).foregroundStyle(.tint)
                    }
                    Picker("Fuel Type", selection: $selectedFuel) { ForEach(FuelType.allCases) { Text($0.rawValue).tag($0) } }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Odometer", text: $odometerText).keyboardType(.decimalPad)
                    TextField("Litres", text: $litresText).keyboardType(.decimalPad)
                    TextField("Price per Litre", text: $pricePerLitreText).keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Add Fuel Entry")
            .sheet(isPresented: $showingAddCar) { CarEditorView(car: CarProfile(), onSave: { car in store.addCar(car); selectedCarId = car.id; selectedFuel = car.fuelType }) }
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

struct FuelEntryDetailView: View {
    let entry: FuelEntry
    @ObservedObject var store: FuelStore
    @State private var photoItem: PhotosPickerItem?
    @State private var showingReceiptPreview = false
    private var car: CarProfile? { store.carProfiles.first { $0.id == entry.carId } }
    private var history: [FuelEntry] { store.vehicleHistory(for: entry.carId) }
    private var prior: FuelEntry? { store.priorEntry(for: entry) }
    private var currentEntry: FuelEntry { store.entries.first(where: { $0.id == entry.id }) ?? entry }
    var body: some View {
        List {
            Section("Fill-up") {
                detailRow("Date", entry.date.formatted(date: .long, time: .omitted))
                detailRow("Vehicle", car?.carNickname ?? "Unknown vehicle")
                detailRow("Fuel Type", entry.fuelType.rawValue)
                detailRow("Litres", String(format: "%.2f L", entry.litres))
                detailRow("Price per Litre", String(format: "$%.3f", entry.pricePerLitre))
                detailRow("Total Cost", String(format: "$%.2f", entry.totalCost))
                detailRow("Odometer", String(format: "%.1f km", entry.odometer))
            }
            Section("Efficiency") {
                if let prior {
                    let distance = max(0, entry.odometer - prior.odometer)
                    detailRow("Distance since prior fill-up", String(format: "%.1f km", distance))
                    if let kmPerLitre = entry.efficiency(distanceDriven: distance) {
                        detailRow("This interval", String(format: "%.2f km/L · %.2f L/100km", kmPerLitre, 100 / kmPerLitre))
                    } else { Text("Efficiency unavailable for this fill-up.").foregroundStyle(.secondary) }
                } else { Text("No prior fill-up with odometer data.").foregroundStyle(.secondary) }
                if let average = store.vehicleAverageEfficiency(for: entry.carId) {
                    detailRow("Vehicle average", String(format: "%.2f km/L · %.2f L/100km", average, 100 / average))
                } else { Text("Vehicle average will appear after a second odometer reading.").foregroundStyle(.secondary) }
            }
            Section("Receipt") {
                if let data = currentEntry.receiptImageData, let image = UIImage(data: data) {
                    Button { showingReceiptPreview = true } label: { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180).frame(maxWidth: .infinity) }
                        .buttonStyle(.plain)
                    PhotosPicker(selection: $photoItem, matching: .images) { Label("Replace Receipt", systemImage: "arrow.triangle.2.circlepath") }
                    Button(role: .destructive) { var updated = currentEntry; updated.receiptImageData = nil; store.updateEntry(updated); photoItem = nil } label: { Label("Delete Receipt", systemImage: "trash") }
                } else {
                    PhotosPicker(selection: $photoItem, matching: .images) { Label("Attach Receipt", systemImage: "plus.circle.fill") }
                }
            }
            Section("Vehicle Fill-up History") {
                ForEach(history) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.date.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                            Text(String(format: "%.1f km · %.2f L · $%.2f", item.odometer, item.litres, item.totalCost)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.id == entry.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                }
            }
        }
        .navigationTitle("Fuel Entry")
        .sheet(isPresented: $showingReceiptPreview) {
            if let data = currentEntry.receiptImageData, let image = UIImage(data: data) {
                ZStack { Color.black.ignoresSafeArea(); Image(uiImage: image).resizable().scaledToFit().onTapGesture { showingReceiptPreview = false } }
            }
        }
        .task(id: photoItem) {
            guard let photoItem, let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
            var updated = currentEntry; updated.receiptImageData = data; store.updateEntry(updated)
        }
        .preferredColorScheme(.dark)
    }
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
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
