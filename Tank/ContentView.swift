// Developed by Dave Todd with the help of his coding genie, Desiree Amira Todd

import SwiftUI
import Combine
import Charts

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
@Published var entries: [FuelEntry] = [] {
didSet {
recalculateEfficiencies()
save()
}
}

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
}

func deleteEntry(at offsets: IndexSet) {
entries.remove(atOffsets: offsets)
}

private func recalculateEfficiencies() {
guard !entries.isEmpty else { return }

// Sort by date to ensure distance calculation is correct
let sortedEntries = entries.sorted { $0.date < $1.date }
var updatedEntries = [FuelEntry]()
var previousOdometer: Double?

for entry in sortedEntries {
var mutableEntry = entry
if let previous = previousOdometer {
let distance = max(0, mutableEntry.odometer - previous)
mutableEntry.calculatedEfficiency = mutableEntry.efficiency(distanceDriven: distance)
} else {
mutableEntry.calculatedEfficiency = nil
}
updatedEntries.append(mutableEntry)
previousOdometer = mutableEntry.odometer
}

// Prevent infinite recursion by checking if data actually changed
if entries != updatedEntries {
entries = updatedEntries
}
}

private func save() {
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
if let data = try? encoder.encode(entries) { UserDefaults.standard.set(data, forKey: entriesKey) }
if let data = try? encoder.encode(carProfile) { UserDefaults.standard.set(data, forKey: carProfileKey) }
}

private func load() {
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

if let data = UserDefaults.standard.data(forKey: entriesKey),
let decoded = try? decoder.decode([FuelEntry].self, from: data) {
entries = decoded
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

struct FuelChartView: View {
let entries: [FuelEntry]

var body: some View {
VStack {
if entries.count < 2 {
ContentUnavailableView("Need more data", systemImage: "chart.line.uptrend.xyaxis", description: Text("Add at least two fuel entries to see trends."))
} else {
VStack(alignment: .leading) {
Text("Price per Litre").font(.headline).padding(.horizontal)
Chart(entries.sorted { $0.date < $1.date }) { entry in
LineMark(
x: .value("Date", entry.date),
y: .value("Price", entry.pricePerLitre)
)
.foregroundStyle(.blue)
.interpolationMethod(.catmullRom)

PointMark(
x: .value("Date", entry.date),
y: .value("Price", entry.pricePerLitre)
)
.foregroundStyle(.blue)
}
.frame(height: 300)
.padding()
}
}
}
.navigationTitle("Fuel Analytics")
}
}

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
.toolbar {
ToolbarItem(placement: .confirmationAction) {
Button("Save") {
let entry = FuelEntry(
date: date,
odometer: Double(odometerText) ?? 0,
litres: Double(litresText) ?? 0,
pricePerLitre: Double(pricePerLitreText) ?? 0
)
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
