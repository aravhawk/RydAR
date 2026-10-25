# Road-surface model

The phone does not train. This folder trains a three-class classifier and a Mac converts it to Core ML.

## What the model is

- Labels: `paved`, `unpaved`, `cant_tell`
- Network: torchvision MobileNetV3-Small, fine-tuned from ImageNet
- Training images: RSCD on Mendeley, DOI `10.17632/w86hvkrzc5`, CC BY 4.0. 370,151 road crops, 240×360.
- Do not use the million-image RSXD release. That license is CC BY-NC.
- Do not train the shipped file on StreetSurfaceVis. That license is CC BY-SA.
- The model does not predict wet, ice, snow, or friction.

## Where it runs

1. Download RSCD Mendeley onto the training machine. Do not commit the images.
2. Train on a Daytona NVIDIA GPU sandbox. One GPU is enough. An H100 is not required. Colab is the fallback if Daytona is down. A Mac is the fallback only if both GPUs are unavailable, and then the result will not match this script.
3. Daytona deletes the sandbox when it stops. Download `roadsurface.pt` and `metrics.json` first.
4. On a Mac, with the repo and a Python environment that has `torch`, `torchvision`, and `coremltools`:

```bash
python3 ml/convert_coreml.py ml/runs/roadsurface.pt ios/CurveAudit/RoadSurface.mlpackage
```

5. The iPhone app loads that package in Dash mode only. Frames are not saved.

## Train

```bash
python3 ml/train_surface.py --data /path/to/RSCD/train-set --epochs 5 --out ml/runs/roadsurface.pt
```

Folder names are classified by words in the name: asphalt or concrete become paved, gravel or mud become unpaved, snow or ice are skipped. Anything else is printed and left out. Point `--cant-tell` at a folder of non-road crops if you have one.

Put the metrics file next to the checkpoint. The video may quote only numbers that are in that file.
