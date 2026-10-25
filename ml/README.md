# Road-state model

The phone does not retrain this network. Core ML is the file bundled inside the app. A separate on-device timing memory, in `Screening.swift`, learns when to speak earlier. It does not learn a speed.

## What to train

One torchvision MobileNetV3-Small trunk and three heads (`ml/roadnet.py`). Create ML is the backup, and it cannot run on an NVIDIA GPU. It also cannot train three heads. If conversion fails, the Create ML backup is material only.

| Head | Labels | Effect on the phone |
|---|---|---|
| Material | paved, unpaved, cant_tell | Can lower the screening assumption. Cannot raise it |
| Friction appearance | dry, wet, water, snow_ice, cant_tell | Water or snow/ice can move the warning earlier. Dry and wet change nothing |
| Unevenness | smooth, slight, severe, cant_tell | Severe, on a paved surface, can move the warning earlier |

Images: RSCD on Mendeley, DOI `10.17632/w86hvkrzc5`, CC BY 4.0. The 27 folder names already carry the three properties. Do not use the million-image RSXD release (CC BY-NC) or StreetSurfaceVis (CC BY-SA). RSCD has no speed label, so this dataset is not a speed predictor.

## Split

This is the only trained model, so it is the only split.

- Train: 90% of each of the 27 class folders. Snow and ice stay in, with material and unevenness masked. Gravel and mud stay in, with unevenness masked.
- Validation: the other 10% of each folder, for early stopping only. Neighboring frames can leak across this cut because the folders do not name the drive. Do not quote this number as the model's accuracy.
- Test: the official 12 sequences, 30 frames each, 8 labeled patches per frame, 2,880 patches. Use them once, after training stops. Report the three heads separately.

The timing memory has no split. It starts from a prior of two late and two early passes and updates on the phone. The county ranking is a confidence bound after 20 passes, not a fitted model.

## Train, then convert

Mac A opens `ml/train_colab.ipynb` in Google Colab. No API key. The repo is private, so the notebook tells you to upload a zip of the training scripts. Choose an H100 runtime if the menu allows it. On Colab Pro, H100 is often greyed out. Choose A100 and start. Download `roadsurface.pt` and the metrics file to this Mac when the run finishes. A Colab runtime can still be deleted.

On a Mac:

```bash
python3 ml/convert_coreml.py ml/runs/roadsurface.pt ios/CurveAudit/RoadSurface.mlpackage
```

Commit the package. The app loads it from the bundle when Dash mode opens. The user does not download it, and launch does not load it.

If conversion fails, train a material-only backup in the Create ML app from the folders made by `ml/prepare_createml_folders.py`, using Image Feature Print V2. Say that it is a Create ML model, not the three-head network.
