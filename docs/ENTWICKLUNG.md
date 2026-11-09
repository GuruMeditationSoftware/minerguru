# MinerGuru für macOS: Entwicklung

Die öffentliche Beschreibung auf Englisch steht in der [README](../README.md).

**MinerGuru** ist eine native macOS-App (SwiftUI, Swift Charts, MenuBarExtra) zur Überwachung und Steuerung von Open-Source Bitcoin-Minern wie **Bitaxe** (z.B. **Gamma 601**, Supra, Ultra) und **NerdQAxe++** / **NerdQAxe+** im lokalen Netzwerk.

**Für Entwickler:** [Architektur der Mac-App](ARCHITEKTUR.md) und [Grundlagen aller drei Apps](GRUNDLAGEN.md) (Miner-API, Abfragerunde, Schreibweg, Mock-Miner, Gegenstücke in Android und Windows).

---

## Highlights & Funktionsumfang

### 1. Nahtlose macOS-Integration
- **Natives Hauptfenster (`NavigationSplitView`)**: Übersichtliche Seitenleiste mit Gesamt-Dashboard und allen erkannten Minern inkl. Live-Status-Indikator, Hashrate und Temperatur.
- **macOS Menüleisten-Widget (`MenuBarExtra`)**: Zeigt die aktuelle Gesamt-Hashrate der Flotte direkt in der macOS-Menüleiste an – mit Schnellzugriff auf alle Miner, Temperaturen, Pool-Latenzen und Aktionen.
- **macOS Inspector-Seitenleiste**: Direkt neben den Live-Charts ein- und ausblendbare Steuerung für Takt, Spannung, Lüfter und Mining-Pools.

### 2. Automatischer Netzwerk-Scan & Manuelle IP-Eingabe
- **Automatischer Subnetz-Scanner (`/24`)**: Erkennt automatisch das lokale Subnetz des Macs (z.B. `192.168.1.1–254`) und findet alle laufenden Bitaxe- (AxeOS) und NerdQAxe++-Miner (NerdOS) parallel innerhalb weniger Sekunden über `/api/system/info`.
- **Manuelles Hinzufügen per IP / Hostname**: Direkte Eingabe einer IP-Adresse oder eines lokalen Hostnamens (z.B. `192.168.1.150` oder `bitaxe.local`) inklusive sofortigem Verbindungstest.

### 3. Live-Monitoring & Telemetrie
- **Flotten-Dashboard**: Aggregierte Gesamt-Hashrate (`GH/s` / `TH/s`), Gesamtleistung (`W` & `kWh/Tag`), Flotten-Effizienz (`J/TH`), akzeptierte/abgelehnte Shares, Rekord-Difficulty (`Best Diff`) und durchschnittliche Pool-Latenz.
- **Interaktive Echtzeit-Charts (Swift Charts)**:
  - Hashrate-Verlauf (`GH/s`)
  - ASIC- & Spannungsregler-Temperatur (`°C`) inkl. einstellbarer Warnschwelle
  - Pool-Latenz zum Stratum-Server (`ms`)
  - Leistungsaufnahme (`W`) & Effizienz (`J/TH`)

### 4. Pool-Informationen & Echtzeit-Pool-Latenz
- **Primärer & Fallback Stratum-Pool**: Anzeige von Server-Host, Port, Wallet/Worker-Name, aktiver Pool-Difficulty und aktivem Modus (Primär vs. Fallback).
- **Duale Pool-Latenzmessung (`ms`)**:
  - Auswertung der vom Miner gemeldeten Stratum-Antwortzeit (`responseTime` in AxeOS / `stratum.pools[].responseTime` in NerdOS).
  - Direkte TCP-Handshake-RTT-Messung (`SYN -> SYN-ACK`) zu Primär- und Fallback-Pool-Servern inkl. Qualitätsbewertung (*Exzellent*, *Gut*, *Mittel*, *Hoch*).

### 5. Miner-Steuerung & Konfiguration (`PATCH /api/system` & `POST /api/system/restart`)
- **Takt & Kernspannung**: Abgestimmte Schnell-Profile (*Eco*, *Standard*, *Performance/Boost*) für **Bitaxe Gamma 601 (`BM1370`)** und **NerdQAxe++ (`4x BM1370`)** sowie feingranulare manuelle Einstellung von Frequenz (`MHz`) und Core Voltage (`mV`).
- **Lüftersteuerung**: Umschaltung zwischen automatischer Temperaturregelung (`Auto-Fan`) und manueller Lüfterdrehzahl (`20 % – 100 %`).
- **Pool-Konfiguration pro Miner**: Bearbeitung aller Pool-Slots (AxeOS 2.15+: bis zu 8 Slots mit frei wählbarem Primär- und Fallback-Slot, ältere Firmware/NerdOS: Primär + Fallback), Dual-Pool-Modus mit Hashrate-Aufteilung beim NerdQAxe, Vorlagen für bekannte Pools und integrierter **Live-Latenz-Test**. Nach dem Speichern startet der Miner neu, damit die Pools aktiv werden.
- **System-Aktionen**: Miner-Reboot auslösen, Hostname anpassen, Rohdaten-JSON (`/api/system/info`) inspizieren oder die Weboberfläche im Browser öffnen.

### 6. Pool-Bibliothek (Seitenleiste „Pool-Konfiguration“)
- **Gespeicherte Pools**: Alle Pools der Miner werden ausgelesen; eigene Pools lassen sich anlegen, bearbeiten und duplizieren.
- **Zuordnung & Schnellwechsel**: Pools per Auswahl den Slots jedes Miners zuweisen oder mit einem Klick auf allen Minern als Primär- bzw. Fallback-Pool setzen. Bereits gespeicherte Slots werden dabei nur umgeschaltet, nicht überschrieben.

### 7. Screenshot-Modus & Sprache
- **Sensible Daten ausblenden** (Augen-Button in der Seitenleiste, `⇧⌘H`): IP-, Wallet- und MAC-Adressen sowie der WLAN-Name werden durch Zeichensalat gleicher Form ersetzt, Eingabefelder und JSON-Rohdaten weichgezeichnet. Worker-Namen bleiben lesbar.
- **Deutsch & Englisch**: Auf einem deutschen Mac startet die App auf Deutsch, sonst auf Englisch. In den Einstellungen lässt sich die Sprache fest wählen (wirkt nach einem Neustart der App). Zahlen folgen dem Regionsformat des Macs.

---

## Projektstruktur

```text
MinerGuru/
├── MinerGuru.xcodeproj/        # Xcode-Projekt (synchronisierte Ordner: neue Dateien werden automatisch übernommen)
├── Package.swift               # Swift Package (Swift 6, macOS 14+) – alternativer Build- und Test-Weg
├── build-app.sh                # Schnelles App-Bundle ohne Xcode-Projekt
├── scripts/
│   ├── make-dmg.sh             # Release-Build (Universal) + DMG mit Installationshintergrund
│   └── generate-dmg-background.swift
├── MinerGuru/
│   ├── MinerGuruApp.swift      # App-Einstieg, Hauptfenster, Menüleiste, Shortcuts
│   ├── Localizable.xcstrings   # Übersetzungen (Quelle Deutsch, Englisch)
│   ├── Models/                 # Datenmodelle: Miner-Telemetrie (inkl. tolerantem Decoding), Coins,
│   │                           # Solo-Mining-Wahrscheinlichkeit, Pool-Slots, Pool-Bibliothek
│   ├── Services/
│   │   ├── MinerStore.swift        # Miner-Liste, Polling, Einstellungen, Persistenz
│   │   ├── PoolLibraryStore.swift  # Gespeicherte Pool-Konfigurationen
│   │   ├── NetworkScanStore.swift  # Zustand des Subnetz-Scans
│   │   ├── MinerAPIClient.swift    # REST-Client für AxeOS / NerdOS
│   │   └── …                       # Netzwerk-Scanner, Pool-Latenz, Live-Log-WebSocket
│   ├── Support/                # Zahlenformatierung (DisplayFormat, MinerFormatting), Sprache & Logging
│   └── Views/
│       ├── Fleet/              # Dashboard: Onboarding, Solo-Chance, Miner-Karten, Pool-Tabelle
│       ├── Miner/              # Miner-Details, Steuerung, Live-Log
│       ├── Pools/              # Pool-Bibliothek und Zuordnung zu Minern
│       └── Components/         # Gemeinsame Bausteine (Karten, Badges, Layouts, Datenschutzmodus)
├── MockMiners/                 # Simulierte Miner aller Varianten zum Testen ohne Hardware
└── MinerGuruTests/             # ~145 Unit-Tests (Swift Testing + XCTest)
```

---

## Build, Test & Release

```bash
open MinerGuru.xcodeproj   # in Xcode: ⌘R starten, ⌘U testen
```

```bash
swift test                 # alle Unit-Tests ohne Xcode-Oberfläche
```

```bash
scripts/make-dmg.sh        # erzeugt dist/MinerGuru-<Version>.dmg
```

### Testen ohne Hardware (simulierte Miner)

`MockMiners/` enthält für jede bekannte Bitaxe- und NerdOS-Variante eine `/api/system/info`-Antwort
(`variants/*.json`, erzeugt von `make_variants.py` aus zwei anonymisierten echten Antworten und den
Board-Tabellen der Firmware-Quellen) und einen Server, der sich wie die Firmware verhält
(AxeOS übernimmt Einstellungen erst nach dem Neustart, NerdOS sofort; Live-Log per WebSocket).

```bash
MockMiners/run-app-with-mocks.sh           # Mock-Server + separate App „MinerGuru (Mock)“ mit allen Varianten
```

```bash
MockMiners/run-app-with-mocks.sh hex nerdqx   # nur passende Varianten
```

```bash
python3 MockMiners/mock_miner.py --list    # Varianten und Ports (ab 127.0.0.1:48001)
```

Die Mock-App hat eine eigene Bundle-ID (`app.minerguru.MinerGuru.mock`) und berührt die echte Miner-Liste
nicht. Jede Anfrage der App erscheint mit Inhalt im Terminal. Die Unit-Tests (`VariantTests`) prüfen
Modellerkennung, Pool-Format, Dual-Pool und Taktprofile für alle Varianten. Neue Variante: Eintrag in
`make_variants.py` ergänzen, Skript ausführen, Erwartung in `MinerGuruTests/VariantTests.swift` eintragen.

Neue Texte in der Oberfläche übernimmt Xcode beim Bauen automatisch in `MinerGuru/Localizable.xcstrings`; die englische Übersetzung trägt man dort im Katalog-Editor ein.

Die ausführliche Anleitung für Releases (inkl. manueller Schritte und Notarisierung) steht in [RELEASE.md](RELEASE.md).

Logs der App (Netzwerk, Persistenz, Live-Log) erscheinen in Console.app unter dem Subsystem `app.minerguru.MinerGuru`.
