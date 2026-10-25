# RydAR

iPhone app for curve screening on Arkansas roads, plus a public Cloudflare map. The product spec is `docs/CurveAudit-AR-Product-Brief.md`. If this README and that file disagree, the build contract at the top of the brief wins.

## Stack

- iOS 17, SwiftUI, MapKit, one SQLite file for curves and trips
- Python for the curve importer and the training script
- Cloudflare Worker, D1, and static files for the public page and anonymous passes
- One vision model with three heads on MobileNetV4-Conv-Small. Fine-tuned in PyTorch on Google Colab from Mac A, converted to Core ML on Mac A, and bundled in the app. See `ml/README.md`. The curve database is also bundled. A drive does not download data. An on-device timing memory can speak earlier. Nothing in the app predicts a speed.

## Who works where

| Computer | Open | Do not open |
|---|---|---|
| Mac A (this Mac: paid Apple team, the phone, Colab) | `ios/CurveAudit.xcodeproj`, `ml/train_colab.ipynb` | the website |
| Mac B | the same Xcode project, simulator | a second copy of `Screening.swift` |
| Windows | `tools/`, `web/` | the Xcode project, the Colab notebook |

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
npx wrangler d1 migrations apply rydar-passes --local
npm run dev
```

The `database_id` in `web/wrangler.jsonc` is a placeholder. The first person with a Cloudflare login replaces it:

```bash
npx wrangler login
npx wrangler d1 create rydar-passes
```

Paste the printed id into `wrangler.jsonc`, then `npm run types`.

## Model

Train the camera model from Mac A with `ml/train_colab.ipynb`, then convert the checkpoint on Mac A. Instructions are in `ml/README.md`. The phone already contains `curves.sqlite`. Do not make it rebuild curves or download them. Launch does not load every curve or the Core ML file. Dash mode loads the model. A drive queries the curves ahead of the car. The overnight task list is `docs/BUILD_PLAN.md`.
