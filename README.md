# AudioSyncer

**Native macOS App zum automatischen Synchronisieren von Multicam-Aufnahmen für Adobe Premiere Pro.**

![macOS](https://img.shields.io/badge/macOS-14.0+-blue) ![Swift](https://img.shields.io/badge/Swift-5.0-orange) ![License](https://img.shields.io/badge/License-MIT-green)

## Was macht AudioSyncer?

AudioSyncer nimmt die Audio-Datei deines externen Recorders und bis zu 6 Kamera-Dateien, synchronisiert sie automatisch per Audio-Waveform-Matching und erstellt ein fertiges Premiere Pro Projekt (`.prproj`) mit Multicam-Timeline — bereit zum Schneiden.

### Features

- **Audio-Waveform-Sync** — Automatische Synchronisation via Kreuzkorrelation (FFT-basiert, hardwarebeschleunigt mit Apple Accelerate)
- **Drag & Drop** — Dateien einfach in die App ziehen
- **Waveform-Vorschau** — Visuelle Darstellung der Audio-Spuren
- **Premiere Pro Export** — Generiert native `.prproj` Dateien mit Multicam-Sequence
- **Auto-Detection** — Erkennt Auflösung und Framerate automatisch aus den Videodateien
- **Premiere Pro Look** — Dunkles UI-Design angelehnt an Adobe Premiere Pro

## Systemanforderungen

- macOS 14.0 (Sonoma) oder neuer
- Xcode 15+ (zum Bauen)

## Installation

### Aus dem Quellcode bauen

```bash
git clone https://github.com/fmatsch/AudioSyncerPremierePro.git
cd AudioSyncerPremierePro/AudioSyncer
xcodebuild -scheme AudioSyncer -configuration Release build CONFIGURATION_BUILD_DIR=../build
open ../build/AudioSyncer.app
```

Oder das Projekt in Xcode öffnen und mit ⌘R starten:

```bash
open AudioSyncer/AudioSyncer.xcodeproj
```

## Workflow

1. **Audio Master laden** — Die Datei deines externen Audio-Recorders (WAV, MP3, AAC, etc.)
2. **Kameras laden** — Bis zu 6 Video-Dateien (MP4, MOV) per Drag & Drop oder Klick
3. **Synchronisieren** — "Synchronisation starten" klicken, die App analysiert die ersten 60 Sekunden Audio
4. **Exportieren** — Projektname und Einstellungen wählen, "Premiere Pro Projekt erstellen" klicken
5. **Schneiden** — Die `.prproj` Datei öffnet sich direkt in Premiere Pro mit fertiger Multicam-Timeline

## Unterstützte Formate

| Typ | Formate |
|-----|---------|
| Video | MP4, MOV, M4V, AVI, MXF |
| Audio | WAV, MP3, AAC, M4A, AIF, AIFF, FLAC |

## Wie funktioniert der Sync?

AudioSyncer verwendet **Kreuzkorrelation im Frequenzbereich** um den zeitlichen Versatz zwischen Audio-Spuren zu berechnen:

1. Audio aus allen Dateien extrahieren (Downsampling auf 8 kHz Mono)
2. FFT beider Signale berechnen (Apple Accelerate / vDSP)
3. Kreuzkorrelation: `IFFT(FFT(master) × conj(FFT(camera)))`
4. Peak im Ergebnis = zeitlicher Offset in Samples → Sekunden

Das ist die gleiche Methode, die auch professionelle Tools wie PluralEyes verwenden.

## Technologie

- **SwiftUI** — Native macOS Interface
- **AVFoundation** — Audio/Video-Verarbeitung
- **Accelerate / vDSP** — Hardwarebeschleunigte FFT für den Sync-Algorithmus
- **Keine externen Dependencies** — Alles mit Apple Frameworks

## Lizenz

MIT License — siehe [LICENSE](LICENSE)
