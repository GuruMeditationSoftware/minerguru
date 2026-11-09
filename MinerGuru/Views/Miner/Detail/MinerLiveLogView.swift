import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MinerLiveLogSectionView: View {
    let miner: MinerDevice
    @Environment(\.redactor) private var redactor
    /// Owned by the detail page so the share difficulty chart can use the same stream.
    @ObservedObject var logController: MinerLogStreamController
    @State private var copiedFeedback: Bool = false
    @State private var isExpandedHeight: Bool = false

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topHeaderBar
            filterAndSearchBar
            terminalOutputArea
        }
        .padding(16)
        .nativeCard()
        .onChange(of: miner.ipAddress) { _, _ in
            logController.stopStreaming()
            logController.clearLogs()
        }
        .onDisappear {
            logController.stopStreaming()
        }
    }

    // MARK: - Top Header Bar

    @ViewBuilder
    private var topHeaderBar: some View {
        // Action buttons are always icon-only (labels live in the tooltips), so one row always fits.
        HStack(alignment: .center, spacing: 10) {
            logTitleGroup
            Spacer(minLength: 8)
            logActionButtons
                .labelStyle(.iconOnly)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var logTitleGroup: some View {
        // The ws:// address is dropped first when space gets tight; the title never truncates.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                logTitleLabel
                streamStatusBadge
                Text("ws://\(redactor.ip(miner.ipAddress))/api/ws")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
            HStack(alignment: .center, spacing: 10) {
                logTitleLabel
                streamStatusBadge
            }
        }
    }

    private var logTitleLabel: some View {
        Label("Live-Log & Konsole", systemImage: "terminal.fill")
            .font(.system(size: 15, weight: .medium))
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private var logActionButtons: some View {
        HStack(spacing: 8) {
            // Start / Stop (Pause) Button
            if logController.isRunning {
                Button {
                    logController.pauseStreaming()
                } label: {
                    Label("Stoppen", systemImage: "pause.fill")
                }
                .buttonStyle(.borderedProminent)
                
                .controlSize(.small)
                .help("Live-Stream anhalten, um in Ruhe im Log zu lesen und zu suchen")
            } else {
                Button {
                    logController.startStreaming(host: miner.ipAddress)
                } label: {
                    Label(
                        logController.state == .paused ? "Weiter" : "Live-Log starten",
                        systemImage: "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                
                .controlSize(.small)
                .help("WebSocket-Verbindung zu ws://\(redactor.ip(miner.ipAddress))/api/ws starten")
            }

            // Auto-Scroll Toggle
            Button {
                logController.autoScroll.toggle()
            } label: {
                Label(
                    "Auto-Scroll",
                    systemImage: logController.autoScroll ? "arrow.down.to.line.circle.fill" : "arrow.down.to.line.circle"
                )
            }
            .buttonStyle(.bordered)
            .tint(logController.autoScroll ? Accent.color : .secondary)
            .controlSize(.small)
            .help("Automatisch zur neuesten Log-Zeile scrollen")

            // Clear Log Buffer
            Button {
                logController.clearLogs()
            } label: {
                Label("Leeren", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(logController.entries.isEmpty)
            .help("Aktuellen Log-Puffer leeren")

            // Copy Filtered Logs
            Button {
                copyLogsToClipboard()
            } label: {
                Label(
                    copiedFeedback ? "Kopiert" : "Kopieren",
                    systemImage: copiedFeedback ? "checkmark" : "doc.on.doc"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(logController.filteredEntries.isEmpty)
            .help("Gefilterte Log-Zeilen in die Zwischenablage kopieren")

            // Export Logs to File
            Button {
                exportLogsToFile()
            } label: {
                Label("Exportieren…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(logController.filteredEntries.isEmpty)
            .help("Gefilterte Log-Ausgabe als .log / .txt Datei speichern")

            // Toggle Console Height
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpandedHeight.toggle()
                }
            } label: {
                Image(systemName: isExpandedHeight ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(isExpandedHeight ? "Konsole verkleinern" : "Konsole vergrößern")
        }
    }

    @ViewBuilder
    private var streamStatusBadge: some View {
        let (label, color): (String, Color) = {
            switch logController.state {
            case .streaming:
                return ("Live", Signal.good)
            case .connecting:
                return (String(localized: "Verbinde…"), Signal.idle)
            case .paused:
                return (String(localized: "Angehalten"), Signal.warning)
            case .stopped:
                return (String(localized: "Gestoppt"), .secondary)
            case .error:
                return (String(localized: "Getrennt"), Signal.bad)
            }
        }()

        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    // MARK: - Filter & Search Bar

    @ViewBuilder
    private var filterAndSearchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Filter:")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("Filter", selection: $logController.categoryFilter) {
                    ForEach(MinerLogCategoryFilter.allCases) { category in
                        Label(category.title, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 165)
            }
            .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(
                    "Im Log suchen (z.B. Accepted, diff, BM1370, stratum, Pool)…",
                    text: $logController.searchText
                )
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))

                if !logController.searchText.isEmpty {
                    Button {
                        logController.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Suchfeld leeren")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            let filteredCount = logController.filteredEntries.count
            let totalCount = logController.entries.count
            Text(
                filteredCount == totalCount
                    ? "\(totalCount) Zeilen"
                    : "\(filteredCount) von \(totalCount) Zeilen"
            )
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
        }
    }

    // MARK: - Terminal Output Area

    @ViewBuilder
    private var terminalOutputArea: some View {
        let filtered = logController.filteredEntries

        ScrollViewReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    // White in light mode, near-black in dark mode; a black tint turned gray in light mode.
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    )

                if filtered.isEmpty {
                    emptyLogPlaceholder
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(filtered) { entry in
                                MinerLogRowView(entry: entry, timeFormatter: Self.timeFormatter)
                                    .id(entry.id)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: filtered.last?.id) { _, newestID in
                        guard logController.autoScroll, let newestID else { return }
                        withAnimation(.linear(duration: 0.08)) {
                            proxy.scrollTo(newestID, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(height: isExpandedHeight ? 520 : 290)
        }
    }

    @ViewBuilder
    private var emptyLogPlaceholder: some View {
        VStack(spacing: 8) {
            if case .connecting = logController.state {
                ProgressView()
                    .controlSize(.small)
                Text("Verbinde mit Live-Log von \(redactor.freeText(miner.displayName)) (ws://\(redactor.ip(miner.ipAddress))/api/ws)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if case .error(let msg) = logController.state {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title3)
                    .foregroundStyle(Signal.warning)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Erneut verbinden") {
                    logController.startStreaming(host: miner.ipAddress)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if !logController.entries.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Keine Log-Einträge für den aktuellen Filter oder Suchbegriff gefunden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Filter & Suche zurücksetzen") {
                    logController.categoryFilter = .all
                    logController.searchText = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if logController.state == .streaming {
                ProgressView()
                    .controlSize(.small)
                Text("Verbunden – warte auf nächste Log-Ausgabe vom Miner…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "terminal")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Die Live-Konsole ist standardmäßig deaktiviert, um den Miner nicht unnötig zu belasten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    logController.startStreaming(host: miner.ipAddress)
                } label: {
                    Label("Live-Log starten", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .padding(24)
    }

    // MARK: - Copy & Export Actions

    private func copyLogsToClipboard() {
        let text = logController.exportText(
            minerName: miner.displayName,
            ipAddress: miner.ipAddress,
            hardware: miner.hardwareTitle
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedFeedback = true
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            copiedFeedback = false
        }
    }

    private func exportLogsToFile() {
        let text = logController.exportText(
            minerName: miner.displayName,
            ipAddress: miner.ipAddress,
            hardware: miner.hardwareTitle
        )

        let savePanel = NSSavePanel()
        savePanel.title = String(localized: "Miner-Log exportieren")
        savePanel.message = String(localized: "Speichere die aktuelle Log-Ausgabe von \(miner.displayName) (\(miner.ipAddress)) als Textdatei.")
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.log, .plainText]

        savePanel.nameFieldStringValue = MinerLogStreamController.exportFileName(
            minerName: miner.displayName,
            ipAddress: miner.ipAddress,
            date: Date()
        )

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.logStream.error("Log-Export fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            NSAlert(error: error).runModal()
        }
    }
}
