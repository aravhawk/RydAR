# Road-surface model

The phone does not train. Core ML is the file the phone loads.

## Train on the Mac first

Create ML trains a small classifier on top of Apple's Image Feature Print. It does not fine-tune a big network, which is why a powerful Mac is the right machine and why the result is already a Core ML model.

1. Download RSCD from Mendeley, DOI `10.17632/w86hvkrzc5`, CC BY 4.0. Do not use the million-image RSXD release (CC BY-NC) or StreetSurfaceVis (CC BY-SA).
2. Sort it:

```bash
python3 ml/prepare_createml_folders.py --data /path/to/RSCD/train-set --out ml/data/createml
```

3. Open the Create ML app. New Project, Image Classification. Training data is `ml/data/createml`. Feature extractor is Image Feature Print V2. Turn on crop, blur, exposure, and noise.
4. Train, then export `RoadSurface.mlmodel` into `ios/CurveAudit/`.
5. Check it on RSCD's 12 test sequences before quoting an accuracy number.

Labels are `paved`, `unpaved`, and `cant_tell`. Snow and ice folders are skipped. The model does not predict wetness or friction.

## Colab is the backup

Use `ml/train_surface.py` only if the Create ML model is weak. That script fine-tunes MobileNetV3-Small in PyTorch. Run it on Google Colab's free GPU. A balanced subset is enough if the full 370,151 images do not fit the session. Download `roadsurface.pt` before the session ends, then on a Mac:

```bash
python3 ml/convert_coreml.py ml/runs/roadsurface.pt ios/CurveAudit/RoadSurface.mlpackage
```

Daytona can run the same script. It is not the plan. Colab costs nothing, and this backup does not need a larger GPU.
