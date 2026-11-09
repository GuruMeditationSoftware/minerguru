import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

/// Reports over a period: output, uptime, energy and cost per miner, exportable as PDF and CSV.
struct ReportsView: View {
    @ObservedObject var store: MinerStore
    @AppStorage("MinerGuru.ReportPeriod") private var period = ReportPeriod.last7Days
    @State private var report: MinerReport?

    var body: some View {
        PageScrollView(spacing: 16) {
            HStack {
                Picker("Timeframe", selection: $period) {
                    ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button {
                    exportCSV()
                } label: {
                    Label("CSV", systemImage: "tablecells")
                }
                .disabled(report?.isEmpty ?? true)
                Button {
                    exportPDF()
                } label: {
                    Label("PDF", systemImage: "doc.richtext")
                }
                .disabled(report?.isEmpty ?? true)
            }

            if let report, !report.isEmpty {
                ReportContent(report: report, formatCost: store.power.tariff.formatPrice)
            } else {
                ContentUnavailableView(
                    "No data for this period",
                    systemImage: "doc.text",
                    description: Text("Reports are built from the long-term history. MinerGuru records while the app is running.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
        }
        .navigationTitle("Reports")
        .navigationSubtitle(subtitle)
        .task(id: period) { await load() }
    }

    private var subtitle: String {
        let interval = period.interval()
        return "\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(interval.end.formatted(date: .abbreviated, time: .omitted))"
    }

    private func load() async {
        let interval = period.interval()
        let points = await store.history.hourlyPoints(from: interval.start, to: interval.end)
        let names = Dictionary(uniqueKeysWithValues: store.miners.map { ($0.id, $0.displayName) })
        let tariff = store.power.tariff
        report = MinerReport.build(interval: interval, points: points, minerName: { names[$0] },
                                   price: { tariff.price(at: $0) }, maintenance: store.maintenance.records)
    }

    private var fileName: String {
        let format = Date.ISO8601FormatStyle().year().month().day()
        return "MinerGuru-Report-\(period.interval().start.formatted(format))"
    }

    private func exportCSV() {
        guard let report else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = fileName + ".csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.csvText().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func exportPDF() {
        guard let report else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = fileName + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ReportPDF.write(report, formatCost: store.power.tariff.formatPrice, to: url)
    }
}

/// The figures on screen.
private struct ReportContent: View {
    let report: MinerReport
    let formatCost: (Double, Int) -> String

    var body: some View {
        AdaptiveGrid(minColumnWidth: 170, spacing: 12) {
            ForEach(ReportFigures.summary(report, formatCost: formatCost), id: \.title) { figure in
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: figure.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(verbatim: figure.value)
                        .font(.system(size: 20, weight: .medium))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nativeCard()
            }
        }

        if report.dailyHashRateGHs.count > 1 {
            VStack(alignment: .leading, spacing: 14) {
                Text("Hashrate per day")
                    .font(.system(size: 13, weight: .medium))
                Chart(report.dailyHashRateGHs) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("GH/s", day.value))
                        .foregroundStyle(Accent.color)
                }
                .mutedAxes()
                .frame(height: 150)
            }
            .padding(16)
            .nativeCard()
        }

        VStack(alignment: .leading, spacing: 12) {
            Text("Miners")
                .font(.system(size: 13, weight: .medium))
            ReportTable(report: report, formatCost: formatCost)
        }
        .padding(16)
        .nativeCard()

        if !report.maintenance.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Maintenance done")
                    .font(.system(size: 13, weight: .medium))
                ForEach(report.maintenance) { record in
                    HStack {
                        Text(verbatim: record.title)
                        Spacer()
                        Text(verbatim: record.doneAt.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                }
            }
            .padding(16)
            .nativeCard()
        }
    }
}

enum ReportFigures {
    struct Figure {
        let title: String
        let value: String
    }

    static func summary(_ report: MinerReport, formatCost: (Double, Int) -> String) -> [Figure] {
        func decimal(_ value: Double?, _ digits: Int, _ unit: String) -> String {
            value.map { DisplayFormat.decimal($0, fractionDigits: digits) + " " + unit } ?? "—"
        }
        return [
            Figure(title: String(localized: "Avg. hashrate"), value: report.averageHashRateGHs.map(MinerFormatting.formatHashrate) ?? "—"),
            Figure(title: String(localized: "Uptime"), value: decimal(report.uptimePercent, 1, "%")),
            Figure(title: String(localized: "Energy"), value: decimal(report.totalEnergyKWh, 2, "kWh")),
            Figure(title: String(localized: "Electricity cost"), value: formatCost(report.totalCost, 2)),
            Figure(title: String(localized: "Avg. efficiency"), value: decimal(report.efficiencyJPerTH, 1, "J/TH")),
            Figure(title: String(localized: "Highest temperature"), value: decimal(report.maxTempC, 1, "°C")),
            Figure(title: String(localized: "Accepted shares"), value: report.sharesAccepted.formatted()),
            Figure(title: String(localized: "Rejected shares"), value: report.sharesRejected.formatted()),
        ]
    }
}

/// Per-miner table, used on screen and in the PDF.
struct ReportTable: View {
    let report: MinerReport
    let formatCost: (Double, Int) -> String
    var rows: [MinerReportRow]?

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Miners").gridColumnAlignment(.leading)
                Text("Online")
                Text("Avg. hashrate")
                Text("kWh")
                Text("Cost")
                Text("J/TH")
                Text("Max. °C")
                Text("Shares")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            Divider()
            ForEach(rows ?? report.rows) { row in
                GridRow {
                    Text(verbatim: row.name).lineLimit(1)
                    Text(verbatim: row.uptimePercent.map { DisplayFormat.decimal($0, fractionDigits: 1) + " %" } ?? "—")
                    Text(verbatim: row.averageHashRateGHs.map(MinerFormatting.formatHashrate) ?? "—")
                    Text(verbatim: DisplayFormat.decimal(row.energyKWh, fractionDigits: 2))
                    Text(verbatim: formatCost(row.cost, 2))
                    Text(verbatim: row.efficiencyJPerTH.map { DisplayFormat.decimal($0, fractionDigits: 1) } ?? "—")
                    Text(verbatim: row.maxTempC.map { DisplayFormat.decimal($0, fractionDigits: 1) } ?? "—")
                    Text(verbatim: "\(row.sharesAccepted.formatted()) / \(row.sharesRejected.formatted())")
                }
                .font(.mono(11))
            }
        }
    }
}

/// A4 pages rendered from SwiftUI, always in light colours.
enum ReportPDF {
    private static let pageSize = CGSize(width: 595, height: 842)
    private static let rowsOnFirstPage = 14
    private static let rowsPerPage = 38

    @MainActor
    static func write(_ report: MinerReport, formatCost: @escaping (Double, Int) -> String, to url: URL) {
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }

        var chunks: [[MinerReportRow]] = [Array(report.rows.prefix(rowsOnFirstPage))]
        var rest = Array(report.rows.dropFirst(rowsOnFirstPage))
        while !rest.isEmpty {
            chunks.append(Array(rest.prefix(rowsPerPage)))
            rest = Array(rest.dropFirst(rowsPerPage))
        }

        for (index, rows) in chunks.enumerated() {
            let page = ReportPage(report: report, rows: rows, isFirst: index == 0, isLast: index == chunks.count - 1,
                                  number: index + 1, formatCost: formatCost)
                .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
                .background(Color.white)
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: page)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
    }
}

private struct ReportPage: View {
    let report: MinerReport
    let rows: [MinerReportRow]
    let isFirst: Bool
    let isLast: Bool
    let number: Int
    let formatCost: (Double, Int) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isFirst {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MinerGuru report")
                        .font(.system(size: 20, weight: .medium))
                    Text(verbatim: "\(report.interval.start.formatted(date: .long, time: .omitted)) – \(report.interval.end.formatted(date: .long, time: .omitted))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: 4), alignment: .leading, spacing: 10) {
                    ForEach(ReportFigures.summary(report, formatCost: formatCost), id: \.title) { figure in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: figure.title)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text(verbatim: figure.value)
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                }
                if report.dailyHashRateGHs.count > 1 {
                    Chart(report.dailyHashRateGHs) { day in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("GH/s", day.value))
                            .foregroundStyle(Color.gray)
                    }
                    .frame(height: 130)
                }
            }
            ReportTable(report: report, formatCost: formatCost, rows: rows)
                .scaleEffect(0.9, anchor: .topLeading)
            if isLast, !report.maintenance.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Maintenance done")
                        .font(.system(size: 12, weight: .medium))
                    ForEach(report.maintenance.prefix(10)) { record in
                        HStack {
                            Text(verbatim: record.title)
                            Spacer()
                            Text(verbatim: record.doneAt.formatted(date: .abbreviated, time: .omitted))
                        }
                        .font(.system(size: 10))
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Text(verbatim: "\(number)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(36)
        .foregroundStyle(.black)
    }
}
