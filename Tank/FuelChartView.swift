import SwiftUI
import Charts

struct FuelChartView: View {
    let entries: [FuelEntry]
    let cars: [CarProfile]
    @State private var selectedCarIds: Set<UUID> = []
    private var filtered: [FuelEntry] { selectedCarIds.isEmpty ? entries : entries.filter { selectedCarIds.contains($0.carId) } }
    var body: some View {
        VStack(spacing: 12) {
            Menu {
                Button { selectedCarIds = [] } label: { if selectedCarIds.isEmpty { Label("All Cars", systemImage: "checkmark") } else { Text("All Cars") } }
                Divider()
                ForEach(cars) { car in
                    Button { if selectedCarIds.contains(car.id) { selectedCarIds.remove(car.id) } else { selectedCarIds.insert(car.id) } } label: {
                        if selectedCarIds.contains(car.id) { Label(car.carNickname, systemImage: "checkmark") } else { Text(car.carNickname) }
                    }
                }
            } label: { Label(selectionLabel, systemImage: "car.2") }
            .padding(.horizontal)
            Text("Select All Cars or choose multiple vehicles to compare.").font(.caption).foregroundStyle(.secondary)
            Picker("Analytics", selection: $selectedTab) { Text("Total Spend").tag(0); Text("Best Days").tag(1); Text("Price Trends").tag(2) }.pickerStyle(.segmented).padding(.horizontal)
            switch selectedTab { case 0: spendOverTimeChart; case 1: dayOfWeekChart; default: priceTrendChart }
            Spacer()
        }.navigationTitle("Fuel Analytics").onAppear { selectedCarIds = [] }
    }
    @State private var selectedTab = 0
    private var selectionLabel: String {
        if selectedCarIds.isEmpty { return "All Cars" }
        if selectedCarIds.count == 1, let id = selectedCarIds.first, let car = cars.first(where: { $0.id == id }) { return car.carNickname }
        return "\(selectedCarIds.count) Cars"
    }
    private var spendOverTimeChart: some View {
        Chart(filtered) { entry in
            AreaMark(x: .value("Date", entry.date, unit: .day), y: .value("Spend ($)", entry.totalCost)).foregroundStyle(by: .value("Vehicle", carName(entry.carId))).opacity(0.3)
            LineMark(x: .value("Date", entry.date, unit: .day), y: .value("Spend ($)", entry.totalCost)).foregroundStyle(by: .value("Vehicle", carName(entry.carId))).symbol(Circle())
        }.padding()
    }
    private var dayOfWeekData: [(day: String, avgPrice: Double)] {
        let grouped = Dictionary(grouping: filtered) { Calendar.current.component(.weekday, from: $0.date) }
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return (1...7).map { n in let items = grouped[n] ?? []; return (days[n-1], items.isEmpty ? 0 : items.map(\.pricePerLitre).reduce(0,+) / Double(items.count)) }
    }
    private var dayOfWeekChart: some View {
        Chart(dayOfWeekData, id: \.day) { item in
            BarMark(x: .value("Day", item.day), y: .value("Avg Price", item.avgPrice)).foregroundStyle(.green)
                .annotation(position: .top) { if item.avgPrice > 0 { Text(String(format: "$%.2f", item.avgPrice)).font(.caption2).foregroundStyle(.secondary) } }
        }.padding()
    }
    private var priceTrendChart: some View {
        Chart(filtered) { entry in
            LineMark(x: .value("Date", entry.date, unit: .day), y: .value("Price/L", entry.pricePerLitre)).foregroundStyle(by: .value("Vehicle", carName(entry.carId))).symbol(Circle())
        }.padding()
    }
    private func carName(_ id: UUID) -> String { cars.first(where: { $0.id == id })?.carNickname ?? "Unknown car" }
}
