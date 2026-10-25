# CurveAudit AR

iPhone app for curve-speed screening on Benton and Washington county roads, plus a public Cloudflare map. The product spec is `docs/CurveAudit-AR-Product-Brief.md`. If this README and that file disagree, the build contract at the top of the brief wins.

## Stack

- iOS 17, SwiftUI, MapKit, one SQLite file for curves and trips
- Python for the curve importer and the training script
- Cloudflare Worker, D1, and static files for the public page and anonymous passes
- One vision model. Trained on a Mac with Create ML. The phone runs the Core ML file. A Colab PyTorch training run is the backup. See `ml/README.md`.

## Who works where

| Computer | Open | Do not open |
|---|---|---|
| Mac A (paid Apple team, the phone) | `ios/CurveAudit.xcodeproj` | |
| Mac B | the same Xcode project, simulator | a second copy of `Screening.swift` |
| Windows | `tools/`, `web/`, `ml/train_surface.py` | the Xcode project |

`main` stays buildable. One person owns a file at a time.

## Mac

```bash
open ios/CurveAudit.xcodeproj
```

Pick the parent's paid team when you install on a phone. The simulator does not need that for the shell. The shell shows a sample screening range. Location, speech, and the camera are not connected yet.

## Windows or either Mac, curve file

```bash
python3 tools/geojson_to_sqlite.py
```

That reads `data/curves/curves.geojson` and writes `ios/CurveAudit/curves.sqlite`.

## Website

```bash
cd web
npm install
npx wrangler d1 migrations apply curveaudit-passes --local
npm run dev
```

The `database_id` in `web/wrangler.jsonc` is a placeholder. The first person with a Cloudflare login replaces it:

```bash
npx wrangler login
npx wrangler d1 create curveaudit-passes
```

Paste the printed id into `wrangler.jsonc`, then `npm run types`.

## Model

Train the camera model on a Mac with Create ML. Instructions are in `ml/README.md`.
