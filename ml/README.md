# Road-state model

The phone does not retrain this network. Core ML is the file bundled inside the app. A separate on-device network, `ios/RydAR/OnsetNet.swift`, learns where this phone starts braking and can move a warning earlier. It does not learn a speed, and it does not replace a road that already has three measured braking starts.

## What to train

One timm MobileNetV4-Conv-Small trunk (`mobilenetv4_conv_small.e2400_r224_in1k`) and three heads (`ml/roadnet.py`). Conv-Small, not the hybrid and not the large. Create ML is the backup, and it cannot run on an NVIDIA GPU. It also cannot train three heads. If conversion fails, the Create ML backup is material only.

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
- Test: the official 12 sequences, 30 frames each, 8 labeled patches per frame, 2,880 patches. `ml/eval_sequences.py` scores the shipped checkpoint on those frames. They were not in the training folders. Report the three heads separately. Do not quote the validation split, in the app or in a video. The sequences are Beijing roads, not an Arkansas test.

The timing memory has no split. It starts from a prior of two late and two early passes and updates on the phone. The county ranking is a confidence bound after 20 passes, not a fitted model.

## Train, then convert

The checkpoint already exists at `ml/runs/roadsurface.pt` (gitignored) and the held-out sequence result is `ml/sequence-test.json`. Do not retrain to refresh a number. Do not open the Colab website, and do not run `colab drivemount`, `colab repl`, `colab console`, or `colab auth`. A new GPU job, if one is actually required, is `colab new -s rydar --gpu A100` (then `G4`, then `L4` if A100 returns 400). Pass `--timeout` on `colab exec`. Do not request an H100. Do not download the million-image release.

On a Mac:

```bash
python3 ml/convert_coreml.py ml/runs/roadsurface.pt ios/RydAR/RoadSurface.mlpackage
```

Commit the package. The app loads it from the bundle when Dash mode opens. The user does not download it, and launch does not load it.

If conversion fails, train a material-only backup in the Create ML app from the folders made by `ml/prepare_createml_folders.py`, using Image Feature Print V2. Say that it is a Create ML model, not the three-head network.
