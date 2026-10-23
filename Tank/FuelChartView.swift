import SwiftUI
import Charts

struct FuelChartView: View {
var entries: [FuelEntry]
@State private var selectedTab = 0

var body: some View {
VStack {
Picker("Analytics", selection: $selectedTab) {
Text("Total Spend").tag(0)
Text("Best Days").tag(1)
Text("Price Trends").tag(2)
}
.pickerStyle(.segmented)
.padding()

switch selectedTab {
case 0:
spendOverTimeChart
case 1:
dayOfWeekChart
default:
priceTrendChart
}
}
.navigationTitle("Fuel Analytics")
}

// 1. Total Spend Over Time (Area Chart)
var spendOverTimeChart: some View {
Chart(entries) { entry in
AreaMark(
x: .value("Date", entry.date, unit: .day),
y: .value("Spend ($)", entry.totalCost)
)
.foregroundStyle(.blue.opacity(0.3))

LineMark(
x: .value("Date", entry.date, unit: .day),
y: .value("Spend ($)", entry.totalCost)
)
.foregroundStyle(.blue)
.symbol(Circle())
}
.padding()
}

// 2. Cost Per Day of Week (Bar Chart)
var dayOfWeekData: [(day: String, avgPrice: Double)] {
let calendar = Calendar.current
let grouped = Dictionary(grouping: entries) { entry in
calendar.component(.weekday, from: entry.date)
}

let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
return (1...7).map { dayNum in
let dayEntries = grouped[dayNum] ?? []
let avg = dayEntries.isEmpty ? 0 : dayEntries.map { $0.pricePerLitre }.reduce(0, +) / Double(dayEntries.count)
return (day: days[dayNum - 1], avgPrice: avg)
}
}

var dayOfWeekChart: some View {
Chart(dayOfWeekData, id: \.day) { data in
BarMark(
x: .value("Day", data.day),
y: .value("Avg Price", data.avgPrice)
)
.foregroundStyle(.green)
.annotation(position: .top) {
if data.avgPrice > 0 {
Text(String(format: "$%.2f", data.avgPrice))
.font(.caption2)
.foregroundColor(.gray)
}
}
}
.padding()
}

// 3. Price Trends (Line Chart of Price Per Litre over time)
var priceTrendChart: some View {
Chart(entries) { entry in
LineMark(
x: .value("Date", entry.date, unit: .day),
y: .value("Price/L", entry.pricePerLitre)
)
.foregroundStyle(.red)
.symbol(Circle())
}
.padding()
}
}
