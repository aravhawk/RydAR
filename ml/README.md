# Road-surface model

The phone uses the Core ML package bundled in the app. It does not retrain this network. A separate on-device network, `ios/RydAR/OnsetNet.swift`, learns where this phone starts braking and can move a warning earlier. It learns a distance, and it leaves the advisory speed on the formula. Three measured braking starts on a road replace the network for that road.

## What was trained

One timm MobileNetV4-Conv-Small trunk (`mobilenetv4_conv_small.e2400_r224_in1k`) and three heads (`ml/roadnet.py`). Conv-Small, not the hybrid and not the large. The trunk width is `backbone.conv_head.out_channels` (1,280 pooled). Create ML is the backup if conversion fails. It trains material only, and it cannot run the three-head job on an NVIDIA GPU.

| Head | Labels | Effect on the phone |
|---|---|---|
| Material | paved, unpaved, cant_tell | Can lower a paved file to unpaved. Cannot raise an unpaved file. |
| Friction appearance | dry, wet, water, snow_ice, cant_tell | Water or snow/ice can move the warning earlier. Dry and wet change nothing. |
| Unevenness | smooth, slight, severe, cant_tell | Severe, on a paved surface, can move the warning earlier. |

`cant_tell` is on each head. It was not trained, because the set has no non-road crops. The phone does not treat a reading as "not a road."

Images: RSCD on Mendeley, DOI `10.17632/w86hvkrzc5`, CC BY 4.0. The 27 folder names already carry the three properties. RSCD has no speed label, so this dataset is not a speed predictor. The million-image RSXD release (CC BY-NC) and StreetSurfaceVis (CC BY-SA) are not used.

## Split

This is the only trained vision model, so it is the only split.

- Train: 90% of each of the 27 class folders. Snow and ice stay in, with material and unevenness masked. Gravel and mud stay in, with unevenness masked.
- Validation: the other 10% of each folder, for early stopping only. Neighboring frames can leak across this cut because the folders do not name the drive. The validation accuracy in `ml/runs/roadsurface.metrics.json` is an early-stopping score. It is not a claim about the model.
- Test: the official 12 sequences, 30 frames each, 8 labeled patches per frame. `ml/eval_sequences.py` scores the shipped checkpoint on those frames. They were not in the training folders. The sequences are Beijing roads. Report the three heads separately. `ml/sequence-test.json` is that record. If one number from it is required, use macro recall. AUC is a ranking score. AURC is lower-is-better and is a selective-risk score.

The phone does not act on one patch. It crops the lower center of the frame and keeps a label when 4 of the last 6 frames agree. `ml/eval_phone_gate.py` replays that rule. `ml/phone-gate.json` is that record. Material accepts a vote at 0.7 (`DriveRules.materialConfidence`), because on these sequences that cutoff held the unpaved precision of 0.8 and caught more unpaved windows. Water, snow, and severe stay at 0.8 (`DriveRules.cameraConfidence`). Severe produced no phone action at any cutoff from 0.5 to 0.9, so the 4-of-6 rule stays as it is.

The timing memory has no split. It starts from a prior of two late and two early passes and updates on the phone. The county ranking is a confidence bound after 20 passes from more than one hour, not a fitted model.

The trunk's ImageNet top-1 is a pretraining figure for the backbone. It is separate from road-surface accuracy. It is not a claim about road surfaces.

## Train, then convert

The trained checkpoint is `ml/runs/roadsurface.pt` (gitignored). The held-out results are `ml/sequence-test.json` and `ml/phone-gate.json`. A new GPU run is only needed to retrain: `colab new -s rydar --gpu A100` (then `G4`, then `L4` if A100 returns 400), with `--timeout` on `colab exec`. For scoring, download only the test-set prefix of the Mendeley zip, not the million-image release.

On a Mac:

```bash
python3 ml/convert_coreml.py ml/runs/roadsurface.pt ios/RydAR/RoadSurface.mlpackage
```

Commit the package only after a conversion that was actually required. The app loads it from the bundle when Dash opens. The user does not download it, and launch does not load it. Core ML uses one image scale for all channels. Training uses a per-channel standard deviation. The shipped package already uses this conversion.

If conversion fails, train a material-only backup in the Create ML app from the folders made by `ml/prepare_createml_folders.py`, using Image Feature Print V2. Say that it is a Create ML model, and that it is material only.
