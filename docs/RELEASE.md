# Release erstellen

Diese Anleitung beschreibt, wie ein Release von MinerGuru als DMG entsteht – zuerst der normale Weg mit
Skript, danach Schritt für Schritt, was das Skript intern tut.

## Der normale Weg (mit Skript)

### 1. Version anheben

Die Version steht an zwei Stellen, die zusammenpassen müssen:

- `MinerGuru/Info.plist`
  - `CFBundleShortVersionString` – sichtbare Version, z. B. `1.2.0`
  - `CFBundleVersion` – Build-Nummer, bei jedem Release um 1 erhöhen
- Xcode: Target *MinerGuru* → *General* → *Version* und *Build*
  (schreibt `MARKETING_VERSION` und `CURRENT_PROJECT_VERSION` in die Projektdatei)

Neue Funktionen erhöhen die mittlere Stelle (`1.1.0` → `1.2.0`), reine Fehlerbehebungen die letzte
(`1.2.0` → `1.2.1`).

### 2. Tests laufen lassen

In Xcode mit `⌘U` oder im Terminal:

```bash
swift test
```

### 3. DMG bauen

```bash
scripts/make-dmg.sh
```

Ergebnis: `dist/MinerGuru-<Version>.dmg`. Die Versionsnummer im Dateinamen kommt aus `Info.plist`.
Der Ordner `dist/` ist in `.gitignore`, das DMG landet also nicht im Repository.

### 4. Commit, Tag und Push

```bash
git commit -am "Release 1.2.0"
```

```bash
git tag -a v1.2.0 -m "MinerGuru 1.2.0"
```

```bash
git push && git push origin v1.2.0
```

## Was das Skript macht (der komplett manuelle Weg)

### 1. Release-Build erzeugen

**In Xcode:** *Product → Archive*, anschließend im Organizer *Distribute App → Custom → Copy App*.
Das liefert eine fertige `MinerGuru.app`.

**Im Terminal** – optimierter Universal-Build für Apple Silicon und Intel:

```bash
xcodebuild -project MinerGuru.xcodeproj -scheme MinerGuru -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CONFIGURATION_BUILD_DIR="$PWD/build/release" build
```

Wichtig ist `-configuration Release`: Debug-Builds sind unoptimiert und nur für die eigene Architektur
gebaut.

### 2. Signieren

Ohne Apple-Developer-Account ist nur eine Ad-hoc-Signatur möglich. Entscheidend sind die Entitlements
(App-Sandbox und Netzwerkzugriff):

```bash
codesign --force --deep --sign - --entitlements MinerGuru/MinerGuru.entitlements build/release/MinerGuru.app
```

Prüfen:

```bash
codesign --verify --deep --strict build/release/MinerGuru.app
```

### 3. DMG-Inhalt vorbereiten

Ein Ordner mit drei Dingen:

- `MinerGuru.app` – die App selbst
- ein Symlink `Applications` → `/Applications` (das Ziel zum Hineinziehen)
- `.background/background.png` – das Hintergrundbild mit Pfeil, erzeugt von
  `scripts/generate-dmg-background.swift` (660 × 400 pt, Retina-Auflösung)

### 4. DMG erstellen

1. Aus dem Ordner ein beschreibbares Image erzeugen (`hdiutil create … -format UDRW`) und einhängen
   (`hdiutil attach`).
2. **Fensterlayout setzen** – der einzige wirklich knifflige Teil: Fenstergröße, Icon-Größe,
   Hintergrundbild und Icon-Positionen. Finder speichert das in einer versteckten `.DS_Store` im Image.
   Das Skript erledigt das per AppleScript. Von Hand: eingehängtes Volume öffnen, mit `⌘J`
   (Darstellungsoptionen) Hintergrundbild und Icon-Größe einstellen und die Icons an ihren Platz schieben.
3. Optional das Volume-Icon: `.VolumeIcon.icns` ins Volume kopieren und `SetFile -a C` auf das Volume
   anwenden.
4. Aushängen und in ein komprimiertes, schreibgeschütztes Image umwandeln:

```bash
hdiutil convert build/MinerGuru-rw.dmg -format UDZO -imagekey zlib-level=9 -o dist/MinerGuru-1.2.0.dmg
```

### 5. Prüfen

```bash
hdiutil verify dist/MinerGuru-1.2.0.dmg
```

Danach das DMG öffnen und kontrollieren, ob Fenster und Pfeil passen. Zum Schluss die App aus dem DMG nach
*Programme* ziehen und einmal starten.

## Hinweis zu Gatekeeper

Ad-hoc-signierte Apps sind nicht notarisiert. Auf dem eigenen Mac starten sie normal; auf anderen Macs
blockiert Gatekeeper den ersten Start mit dem Hinweis „nicht verifizierter Entwickler“. Abhilfe: Rechtsklick
auf die App → *Öffnen*, oder in den Systemeinstellungen unter *Datenschutz & Sicherheit* → *Trotzdem öffnen*.

## Optional: Signieren und Notarisieren ohne Gatekeeper-Warnung

Dafür ist ein Apple Developer Account nötig (99 $ pro Jahr). Dann ändern sich drei Schritte:

1. Mit dem Zertifikat *Developer ID Application* statt Ad-hoc signieren und die Hardened Runtime
   aktivieren (`--options runtime`).
2. Das DMG zur Notarisierung an Apple schicken: `xcrun notarytool submit … --wait`.
3. Das Notarisierungs-Ticket ins DMG heften: `xcrun stapler staple dist/MinerGuru-1.2.0.dmg`.

Dafür müsste `scripts/make-dmg.sh` um die Zertifikats-ID und ein App-spezifisches Passwort erweitert werden.
