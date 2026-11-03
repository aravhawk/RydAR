# RydAR

RydAR is an iPhone co-pilot for tight bends in Arkansas, and a public map of those bends at [rydar.org](https://rydar.org). The source is [github.com/aravhawk/RydAR](https://github.com/aravhawk/RydAR).

A drive warns from the curve database bundled in the app and from the formula in `ios/RydAR/Screening.swift`. The drive does not wait on the website. A single-curve prompt says, for example, "Slow to 25 mph for the curve ahead," using the low end of the computed range, rounded down. Confidently matched bends on the same named road can share a "Curves ahead" warning, with a separate warning for a notably sharper bend. The base warning lead is 12 seconds of travel, clamped to 100–450 m. The screen shows it as "Suggested speed." That number is the formula's range for the curve, and it is separate from a posted speed sign.

Teen driver mode speaks the same numeric curve advisories and vibrates twice before each one. It has no camera, curve display, or Live Activity, and it lets the screen sleep. Anonymous sharing follows the same switch as any other trip. Pause and end controls remain available for use while parked. The trip choices are Driver and Teen driver. For a road test, an adult drives and a student holds the phone; choose Driver for the adult. Saved passenger trips read as Driver.

While the camera check is running, the drive screen shows a small live thumbnail of what the camera sees and a live Paved or Unpaved label for the road under the car, whether or not a curve is near. Frames are displayed, never saved.

A warning only plays when there is road left for it: closer than three seconds of travel (and at least 30 m), or once the car is already moving away from the bend, it stays silent. Any confident bend ahead can warn once it is inside its own warning distance, so a sharp bend behind a gentle one is not left until the gentle one is passed. A bend far to the side of the line of travel is treated as another road: it does not warn and its pass is not logged. If GPS fixes stop for more than four seconds the drive screen says so instead of freezing on the last curve.

Anonymous passes are held until the trip ends, then sent together in random order, and only if uploads are still on. Each install makes one App Attest key, which Apple attests once through `/api/attest`; every trip's batch is then signed on the phone with an assertion (no Apple call, so no attestation rate limit). The key id lives in the Keychain (this device only, not backed up) and is replaced after Reset all data, after sharing is turned off, or when iOS invalidates it. The server keeps a hash of the key id, its public key, a replay counter, and a last-seen day, never linked to passes, and deletes records unused for 180 days. A batch that cannot be sent waits on the phone (not backed up) and is retried on the next trip or launch; it is dropped after five tries or 14 days, and at once if sharing is turned off. The simulator build never uploads. The server keeps the day, not the time.

Trips need location, Precise Location, and a fix in Arkansas (2 km margin at the state line, checked on the phone against `ios/RydAR/ArkansasCounties.json`). Elsewhere Home says "RydAR covers Arkansas roads. More states are coming soon." and the map still works. A trip that leaves the state keeps running and shows "Outside Arkansas · No curve data".

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

Location is When In Use only. A trip always starts in the foreground, so its updates keep running behind Maps with the location indicator showing; the app never asks for Always. Onboarding asks whether to share anonymous curve data and whether to use the camera check before any trip, and resetting settings never turns either back on. `PrivacyInfo.xcprivacy` declares the shared curve (precise location), pass details (other usage data), and the App Attest key (device ID, app functionality only), none linked to the rider or used for tracking; the App Store privacy label must say the same.

Builds need `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The team is `XLR6H6DKHH`. Install onto an unlocked phone. The curve database and the model ship inside the app. Launch reads neither the full curve table nor the model. The camera check loads the model. A drive queries a bounding box and the road ahead.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project ios/RydAR.xcodeproj -scheme RydAR \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Website

Pushes to `main` deploy the site. The Vercel project root is `web/`. Anonymous passes go to Neon through `DATABASE_URL`. The phone gets a challenge from `https://rydar.org/api/challenge`, registers its key once at `https://rydar.org/api/attest`, then posts one assertion-signed batch per trip to `https://rydar.org/api/pass` (shapes in `Contracts/pass.json`). Uploads need `PASS_CHALLENGE_SECRET` (32+ random characters) in Vercel; without it the challenge, attest, and pass endpoints answer 503 and nothing is stored. `APP_ATTEST_APP_ID` defaults to `XLR6H6DKHH.org.rydar.app`; `APP_ATTEST_ALLOW_DEVELOPMENT=1` also accepts development-environment keys (the app ships the production entitlement, so this is normally off). `npm run check` in `web/` type-checks the API and `npm test` runs its tests, including a real recorded attestation and assertion. `npm run build` generates the static information pages, homepage metadata, and sitemap; `npm run check:seo` checks metadata, structured data, internal links, and sitemap coverage.

## Camera and timing

The bundled model is MobileNetV4-Conv-Small with three heads, trained on RSCD and converted to Core ML. A paved file can become unpaved. Water, snow, or a severely uneven paved surface can move the warning earlier. The advisory speed stays on the formula. Material switches to unpaved on 3 of the last 6 frames with average unpaved probability at least 0.7, returns on 5 paved frames out of 6 below that average, and holds an accepted unpaved reading through the current curve approach. Water, snow, and severe stay at 0.8. The records are `ml/sequence-test.json` and `ml/phone-gate.json`.

`OnsetNet` remembers where this phone starts braking and can place the warning sooner. Three measured braking starts on that road win over the network. The advisory speed stays on the formula.
