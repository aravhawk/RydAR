# RydAR

RydAR is an iPhone co-pilot for tight bends in Arkansas, and a public map of those bends at [rydar.org](https://rydar.org). The source is [github.com/aravhawk/RydAR](https://github.com/aravhawk/RydAR).

A drive warns from the curve database bundled in the app and from the formula in `ios/RydAR/Screening.swift`. The drive does not wait on the website. A single-curve prompt says "Slow to N mph for the curve ahead," using the rounded low end of the computed range. Confidently matched bends on the same named road can share a "Curves ahead" warning, with a separate warning for a notably sharper bend. The base warning lead is 12 seconds of travel, clamped to 100–450 m. The on-screen caption is "Advisory." That number is the formula. It is the range the app computed, and it is separate from a posted plaque.

An under-18 driver gets no voice, no chime, no haptic, no camera, and no upload, including while parked. The trip choices are Driver and Teen driver. For a road test, an adult drives and a student holds the phone; choose Driver for the adult. Older passenger selections and saved trips migrate to Driver.

The long product brief lives outside this repository.

## Layout

| Path | What it is |
|---|---|
| `ios/` | SwiftUI app, Live Activity, bundled `curves.sqlite`, and `RoadSurface.mlpackage` |
| `web/` | Public map and the anonymous-pass API. The Vercel project root is this folder. |
| `ml/` | Road-surface checkpoint, Core ML conversion, and the held-out scoring scripts |
| `data/` | Crash tables and the original Benton and Washington curve study |
| `fixtures/` | Simulator approach for curve `007-2-3` on N Old Wire Rd |
| `tools/` | Builders for the statewide database. The shipped files are already built. |
| `Contracts/` | Curve table and the anonymous pass shape |

## App

```bash
open ios/RydAR.xcodeproj
```

Builds need `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The team is `XLR6H6DKHH`. Install onto an unlocked phone. The curve database and the model ship inside the app. Launch reads neither the full curve table nor the model. Dash loads the model. A drive queries a bounding box and the road ahead.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project ios/RydAR.xcodeproj -scheme RydAR \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Website

Pushes to `main` deploy the site. The Vercel project root is `web/`. Anonymous passes go to Neon. The phone posts to `https://rydar.org/api/pass`. The old Cloudflare worker is still running. Leave that worker and its database alone.

## Camera and timing

The bundled model is MobileNetV4-Conv-Small with three heads, trained on RSCD and converted to Core ML. A paved file can become unpaved. Water, snow, or a severely uneven paved surface can move the warning earlier. The advisory speed stays on the formula. Material switches to unpaved on 3 of the last 6 frames with average unpaved probability at least 0.7, returns on 5 paved frames out of 6 below that average, and holds an accepted unpaved reading through the current curve approach. Water, snow, and severe stay at 0.8. The records are `ml/sequence-test.json` and `ml/phone-gate.json`. Leave those numbers out of the app and out of a video.

`OnsetNet` remembers where this phone starts braking and can place the warning sooner. Three measured braking starts on that road win over the network. The advisory speed stays on the formula.

## Leave these as they are

The vision model stays on the shipped checkpoint. `ios/RydAR/curves.sqlite` and the four public GeoJSON files stay as shipped. `data/curves/build_curves.py` and `data/fars/compute.py` stay unused for a refresh. OpenStreetMap speed limits stay out of the curve files. The product brief stays out of `docs/`.
