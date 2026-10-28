# RydAR

RydAR is an iPhone co-pilot for tight bends in Arkansas, and a public map of those bends at [rydar.org](https://rydar.org). The source is [github.com/aravhawk/RydAR](https://github.com/aravhawk/RydAR).

A drive warns from the curve database bundled in the app and from the formula in `ios/RydAR/Screening.swift`. The drive does not wait on the website. A single-curve prompt says, for example, "Slow to 25 mph for the curve ahead," using the low end of the computed range, rounded down. Confidently matched bends on the same named road can share a "Curves ahead" warning, with a separate warning for a notably sharper bend. The base warning lead is 12 seconds of travel, clamped to 100–450 m. The screen shows it as "Suggested speed." That number is the formula's range for the curve, and it is separate from a posted speed sign.

Teen driver mode speaks the same numeric curve advisories with no haptic, camera, upload, curve display, or Live Activity. It always uses speech, including when the adult prompt preference is Chime only, and lets the screen sleep. Pause and end controls remain available for use while parked. The trip choices are Driver and Teen driver. For a road test, an adult drives and a student holds the phone; choose Driver for the adult. Saved passenger trips read as Driver.

While the camera check is running, the drive screen shows a small live thumbnail of what the camera sees and a live Paved or Unpaved label for the road under the car, whether or not a curve is near. Frames are displayed, never saved.

A warning only plays when there is road left for it: closer than three seconds of travel (and at least 30 m), or once the car is already moving away from the bend, it stays silent. Any confident bend ahead can warn once it is inside its own warning distance, so a sharp bend behind a gentle one is not left until the gentle one is passed. A bend far to the side of the line of travel is treated as another road: it does not warn and its pass is not logged. If GPS fixes stop for more than four seconds the drive screen says so instead of freezing on the last curve.

Anonymous passes are held until the trip ends, then sent together in random order, and only if uploads are still on. The simulator build never uploads. The server keeps the day, not the time.

## Layout

| Path | What it is |
|---|---|
| `ios/` | SwiftUI app, Live Activity, bundled `curves.sqlite`, and `RoadSurface.mlpackage` |
| `web/` | Public map and the anonymous-pass API. The Vercel project root is this folder. |
| `ml/` | Road-surface checkpoint, Core ML conversion, and the held-out scoring scripts |
| `fixtures/` | Simulator approach for curve `007-2-3` on N Old Wire Rd |
| `tools/` | Builders for the statewide curve database and the public map files. The shipped files are already built. |
| `Contracts/` | Curve table and the anonymous pass shape |

## App

```bash
open ios/RydAR.xcodeproj
```

Builds need `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The team is `XLR6H6DKHH`. Install onto an unlocked phone. The curve database and the model ship inside the app. Launch reads neither the full curve table nor the model. The camera check loads the model. A drive queries a bounding box and the road ahead.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project ios/RydAR.xcodeproj -scheme RydAR \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Website

Pushes to `main` deploy the site. The Vercel project root is `web/`. Anonymous passes go to Neon through `DATABASE_URL`. The phone posts to `https://rydar.org/api/pass`. `npm run check` in `web/` type-checks the API.

## Camera and timing

The bundled model is MobileNetV4-Conv-Small with three heads, trained on RSCD and converted to Core ML. A paved file can become unpaved. Water, snow, or a severely uneven paved surface can move the warning earlier. The advisory speed stays on the formula. Material switches to unpaved on 3 of the last 6 frames with average unpaved probability at least 0.7, returns on 5 paved frames out of 6 below that average, and holds an accepted unpaved reading through the current curve approach. Water, snow, and severe stay at 0.8. The records are `ml/sequence-test.json` and `ml/phone-gate.json`.

`OnsetNet` remembers where this phone starts braking and can place the warning sooner. Three measured braking starts on that road win over the network. The advisory speed stays on the formula.
