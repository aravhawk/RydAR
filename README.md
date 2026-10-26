# RydAR

RydAR is an iPhone co-pilot for tight bends in Arkansas, and a public map of those bends at [rydar.org](https://rydar.org). The source is [github.com/aravhawk/RydAR](https://github.com/aravhawk/RydAR).

A drive warns from the curve database bundled in the app and from the formula in `ios/RydAR/Screening.swift`. The drive does not wait on the website. The spoken line is exactly "Curve ahead. Above advisory speed." The on-screen caption is "Advisory." That number is the formula. It is the range the app computed, and it is separate from a posted plaque.

An under-18 driver gets no voice, no chime, no haptic, no camera, and no upload, including while parked. The road test is Passenger, with an adult driving and a student holding the phone.

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

The bundled model is MobileNetV4-Conv-Small with three heads, trained on RSCD and converted to Core ML. A paved file can become unpaved. Water, snow, or a severely uneven paved surface can move the warning earlier. The advisory speed stays on the formula. Material needs 4 of the last 6 frames at a confidence of 0.7. Water, snow, and severe stay at 0.8. The records are `ml/sequence-test.json` and `ml/phone-gate.json`. Leave those numbers out of the app and out of a video.

`OnsetNet` remembers where this phone starts braking and can place the warning sooner. Three measured braking starts on that road win over the network. The advisory speed stays on the formula.

## Leave these as they are

The vision model stays on the shipped checkpoint. `ios/RydAR/curves.sqlite` and the four public GeoJSON files stay as shipped. `data/curves/build_curves.py` and `data/fars/compute.py` stay unused for a refresh. OpenStreetMap speed limits stay out of the curve files. The product brief stays out of `docs/`.
