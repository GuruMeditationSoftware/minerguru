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
        Label("Live Log & Console", systemImage: "terminal.fill")
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
                    Label("Stop", systemImage: "pause.fill")
                }
                .buttonStyle(.borderedProminent)
                
                .controlSize(.small)
                .help("Pause the live stream to read and search the log")
            } else {
                Button {
                    logController.startStreaming(host: miner.ipAddress)
                } label: {
                    Label(
                        logController.state == .paused ? "Resume" : "Start Live Log",
                        systemImage: "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                
                .controlSize(.small)
                .help("Start the WebSocket connection to ws://\(redactor.ip(miner.ipAddress))/api/ws")
            }

            // Auto-Scroll Toggle
            Button {
                logController.autoScroll.toggle()
            } label: {
                Label(
                    "Auto-scroll",
                    systemImage: logController.autoScroll ? "arrow.down.to.line.circle.fill" : "arrow.down.to.line.circle"
                )
            }
            .buttonStyle(.bordered)
            .tint(logController.autoScroll ? Accent.color : .secondary)
            .controlSize(.small)
            .help("Scroll to the newest log line automatically")

            // Clear Log Buffer
            Button {
                logController.clearLogs()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(logController.entries.isEmpty)
            .help("Clear the current log buffer")

            // Copy Filtered Logs
            Button {
                copyLogsToClipboard()
            } label: {
                Label(
                    copiedFeedback ? "Copied" : "Copy",
                    systemImage: copiedFeedback ? "checkmark" : "doc.on.doc"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(logController.filteredEntries.isEmpty)
            .help("Copy the filtered log lines to the clipboard")

            // Export Logs to File
            Button {
                exportLogsToFile()
            } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(logController.filteredEntries.isEmpty)
            .help("Save the filtered log output as a .log / .txt file")

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
            .help(isExpandedHeight ? "Shrink console" : "Enlarge console")
        }
    }

    @ViewBuilder
    private var streamStatusBadge: some View {
        let (label, color): (String, Color) = {
            switch logController.state {
            case .streaming:
                return ("Live", Signal.good)
            case .connecting:
                return (String(localized: "Connecting…"), Signal.idle)
            case .paused:
                return (String(localized: "Paused"), Signal.warning)
            case .stopped:
                return (String(localized: "Stopped"), .secondary)
            case .error:
                return (String(localized: "Disconnected"), Signal.bad)
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
                    "Search the log (e.g. Accepted, diff, BM1370, stratum, pool)…",
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
                    .help("Clear search field")
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
                    ? "\(totalCount) lines"
                    : "\(filteredCount) of \(totalCount) lines"
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
                Text("Connecting to the live log of \(redactor.freeText(miner.displayName)) (ws://\(redactor.ip(miner.ipAddress))/api/ws)…")
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
                Button("Reconnect") {
                    logController.startStreaming(host: miner.ipAddress)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if !logController.entries.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("No log entries found for the current filter or search term.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reset filter & search") {
                    logController.categoryFilter = .all
                    logController.searchText = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if logController.state == .streaming {
                ProgressView()
                    .controlSize(.small)
                Text("Connected – waiting for the next log output from the miner…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "terminal")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("The live console is off by default so the miner is not loaded unnecessarily.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    logController.startStreaming(host: miner.ipAddress)
                } label: {
                    Label("Start Live Log", systemImage: "play.fill")
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
        savePanel.title = String(localized: "Export Miner Log")
        savePanel.message = String(localized: "Save the current log output of \(miner.displayName) (\(miner.ipAddress)) as a text file.")
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
            Log.logStream.error("Log export failed: \(error.localizedDescription, privacy: .public)")
            NSAlert(error: error).runModal()
        }
    }
}
