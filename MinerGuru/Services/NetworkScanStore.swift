import Foundation
import Combine

/// State and control of the local subnet scan for Bitaxe / NerdQAxe miners.
@MainActor
final class NetworkScanStore: ObservableObject {
    @Published var subnetPrefix: String
    @Published private(set) var detectedLocalIP: String
    @Published private(set) var isScanning = false
    @Published private(set) var completedCount = 0
    @Published private(set) var totalCount = 254
    @Published private(set) var discoveredMiners: [DiscoveredMiner] = []

    private weak var minerStore: MinerStore?
    private var scanTask: Task<Void, Never>?

    init(minerStore: MinerStore) {
        self.minerStore = minerStore
        let detected = NetworkScanner.detectLocalSubnetPrefix()
        self.subnetPrefix = detected.prefix
        self.detectedLocalIP = detected.localIP
    }

    /// Scans `subnetPrefix.1–254`. With `autoAddNew` every found miner is added right away;
    /// otherwise found miners are only added automatically when the fleet is still empty.
    func startScan(autoAddNew: Bool = false) {
        scanTask?.cancel()
        discoveredMiners = []
        completedCount = 0
        totalCount = 254
        isScanning = true

        let prefixToScan = subnetPrefix

        scanTask = Task { [weak self] in
            let results = await NetworkScanner.scanSubnet(
                prefix: prefixToScan,
                onProgress: { [weak self] completed, total in
                    // Throttle UI updates to every 12 hosts (or completion) to prevent layout storms
                    guard completed % 12 == 0 || completed == total else { return }
                    Task { @MainActor [weak self] in
                        self?.completedCount = completed
                        self?.totalCount = total
                    }
                },
                onDiscovered: { [weak self] discovered in
                    Task { @MainActor [weak self] in
                        self?.handleDiscovered(discovered, autoAdd: autoAddNew)
                    }
                }
            )

            guard let self, !Task.isCancelled else { return }
            self.completedCount = self.totalCount
            self.isScanning = false
            self.addResultsIfFleetIsEmpty(results)
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func addAllDiscovered() {
        guard let minerStore else { return }
        var added = 0
        for item in discoveredMiners where !minerStore.isIPAlreadyAdded(item.ipAddress) {
            minerStore.addMiner(ipAddress: item.ipAddress, initialInfo: item.info, rawJSON: item.rawJSON)
            added += 1
        }
        if added > 0 {
            minerStore.showBanner(String(localized: "\(added) Miner zum Dashboard hinzugefügt."), isError: false)
        }
    }

    func isAlreadyAdded(_ ip: String) -> Bool {
        minerStore?.isIPAlreadyAdded(ip) ?? false
    }

    // MARK: - Private

    private func handleDiscovered(_ discovered: DiscoveredMiner, autoAdd: Bool) {
        if !discoveredMiners.contains(where: { $0.ipAddress == discovered.ipAddress }) {
            discoveredMiners = (discoveredMiners + [discovered]).sorted {
                NetworkScanner.ipSortKey($0.ipAddress) < NetworkScanner.ipSortKey($1.ipAddress)
            }
        }
        if autoAdd, let minerStore, !minerStore.isIPAlreadyAdded(discovered.ipAddress) {
            minerStore.addMiner(ipAddress: discovered.ipAddress, initialInfo: discovered.info, rawJSON: discovered.rawJSON)
        }
    }

    private func addResultsIfFleetIsEmpty(_ results: [DiscoveredMiner]) {
        guard let minerStore, !results.isEmpty, minerStore.miners.isEmpty else { return }
        for item in results where !minerStore.isIPAlreadyAdded(item.ipAddress) {
            minerStore.addMiner(ipAddress: item.ipAddress, initialInfo: item.info, rawJSON: item.rawJSON)
        }
        minerStore.showBanner(String(localized: "\(results.count) Miner im lokalen Netzwerk gefunden und hinzugefügt."), isError: false)
    }
}
