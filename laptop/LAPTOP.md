# Building a Model Car on Your Laptop

Build a model car OCI image locally with `podman` (or `docker`), then push it
to a registry such as Quay. Good for quick iteration and small/medium models.

## Prerequisites

- `podman` **or** `docker` installed.
- Free disk space for the model — see the size estimates in the UI or
  [`examples/model-catalog.json`](../examples/model-catalog.json). Budget roughly
  **2× the model size** (download + image layers).
- A registry account (e.g. [quay.io](https://quay.io)) if you want to push.
- A Hugging Face token **only** for gated/private models.

## Quick start

```bash
# Public model — no token needed
./laptop/build.sh ibm-granite/granite-3.3-2b-instruct

# Gated/private model — export a token first
export HF_TOKEN=hf_xxxxxxxxxxxxxxxxxxxx
./laptop/build.sh meta-llama/Llama-3.2-3B-Instruct

# Build AND push to a registry
export REGISTRY=quay.io/youruser
./laptop/build.sh RedHatAI/Qwen3-8B-FP8-dynamic v1.0 --push
```

## How it works

`laptop/build.sh` runs a two-stage build defined in
[`laptop/Containerfile`](../laptop/Containerfile):

1. **`downloader` stage** (`ubi9/python-312`) — installs the Hugging Face CLI,
   validates the repo id, and downloads `safetensors` + config files.
2. **final stage** (`ubi9/ubi-micro`) — copies *only* the model files into a
   tiny, shell-capable image. `ubi-micro` (not `scratch`) is required because
   KServe needs a shell to verify the model files.

The `HF_TOKEN` is passed as a **build secret** (`--secret`), so it is *not*
baked into the image history.

## Options

| Variable / flag  | Purpose |
|------------------|---------|
| `HF_TOKEN`       | Hugging Face token for gated/private models |
| `REGISTRY`       | Registry + namespace, e.g. `quay.io/youruser` (needed for `--push`) |
| `CONTAINER_TOOL` | Force `podman` or `docker` (otherwise auto-detected) |
| `--push`         | Push the image after building |

## Test the image locally

```bash
# Inspect the model files inside the image
podman run --rm -it <image> ls -lhR /models
```

## Push manually

```bash
podman login quay.io
podman push quay.io/youruser/granite-3.3-2b-instruct:latest
```

## Deploy

Use the pushed image as an OCI connection in OpenShift AI:

```
oci://quay.io/youruser/granite-3.3-2b-instruct:latest
```

See [`examples/inferenceservice-modelcar.yaml`](../examples/inferenceservice-modelcar.yaml).

## Notes & limits

- Most registries comfortably handle images up to ~15–20 GB. For very large
  models, prefer a quantized variant (FP8 / INT4) — exactly what the Red Hat AI
  validated models provide.
- Large models on a flaky connection: see
  [`laptop/download_model.py`](../laptop/download_model.py), a standalone
  retrying downloader you can run before building.
