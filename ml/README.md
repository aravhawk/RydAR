# Road-surface model

The phone does not train. Core ML is the file bundled inside the app.

## What to train

Fine-tune torchvision MobileNetV3-Small. Create ML is the backup, and it cannot run on an NVIDIA GPU. It only runs on a Mac, and it does not train the network. It fits a small classifier on Apple's frozen scene features.

Labels: `paved`, `unpaved`, `cant_tell`.

Images: RSCD on Mendeley, DOI `10.17632/w86hvkrzc5`, CC BY 4.0. Do not use the million-image RSXD release (CC BY-NC) or StreetSurfaceVis (CC BY-SA).

## Split

- Train: 90% of the class-folder images after snow and ice are removed and the material names are collapsed.
- Validation: the other 10%, stratified by collapsed label, for early stopping only. Neighboring frames can leak across this cut because the folders do not name the drive. Do not quote this number as the model's accuracy.
- Test: the official 12 sequences, 30 frames each, 8 labeled patches per frame, 2,880 patches. Use them once, after training stops.

## Train, then convert

Run `ml/train_surface.py` on a Daytona NVIDIA GPU. One GPU is enough. Download `roadsurface.pt` and the metrics file before the sandbox stops. Daytona deletes a GPU sandbox when it stops.

On a Mac:

```bash
python3 ml/convert_coreml.py ml/runs/roadsurface.pt ios/CurveAudit/RoadSurface.mlpackage
```

Commit the package. The app loads it from the bundle. The user does not download it.

If conversion fails, train a backup in the Create ML app from the folders made by `ml/prepare_createml_folders.py`, using Image Feature Print V2. Say that it is a Create ML model, not a fine-tuned MobileNet.
