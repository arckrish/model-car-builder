# Model Car Builder

Package Hugging Face models as **model cars** — OCI container images that
[KServe](https://kserve.github.io/website/) and **Red Hat OpenShift AI** can
serve directly from a registry, with no S3 bucket required.

A *model car* bundles a model's weights and config into an OCI image. When you
deploy it, KServe pulls the image and mounts the model — reducing startup time,
cutting duplicate downloads, and letting you manage models with the same
supply-chain tooling (signing, SBOMs, policies) you already use for app
containers.

This repo gives you **three ways** to build a model car, plus an interactive UI
to drive them:

| Method | Best for | Entry point |
|--------|----------|-------------|
| 💻 **Laptop build** | Quick iteration, small/medium models | [`laptop/build.sh`](laptop/build.sh) |
| ☁️ **OpenShift cluster build** | Large models, no local resources, CI/CD | [`openshift/deploy.sh`](openshift/deploy.sh) |
| 🔄 **Data Science Pipeline** | Build → push → **register in the Model Registry** | [`pipeline/run_pipeline.py`](pipeline/run_pipeline.py) |
| 🖥️ **Interactive UI** | Configure a build, generate the commands | [`ui/index.html`](ui/index.html) |

## Repository layout

```
model-car-builder/
├── README.md
├── laptop/
│   ├── build.sh              # Local build + push (podman/docker)
│   ├── Containerfile         # Two-stage model car build
│   └── download_model.py     # Standalone retrying HF downloader
├── openshift/
│   ├── deploy.sh             # Cluster build orchestration
│   ├── buildconfig.yaml      # OpenShift BuildConfig  (do not edit)
│   ├── Containerfile         # Standalone copy of the inline Dockerfile
│   └── pvc-model-download.yaml  # Alternative: download a model to a PVC
├── pipeline/
│   ├── model_car_pipeline.py # Kubeflow (KFP v2) pipeline definition
│   ├── run_pipeline.py       # Submit a pipeline run
│   └── requirements.txt
├── ui/
│   └── index.html            # Interactive, dependency-free console
├── examples/
│   ├── model-catalog.json    # Curated model list (validated + popular)
│   └── inferenceservice-modelcar.yaml  # Example KServe deployment

```

## Quick start

### 1. Use the interactive UI (recommended starting point)

```bash
open ui/index.html        # or: python3 -m http.server 8000 --directory ui
```

Pick a build target, enter a model repo, and the UI generates the exact commands.

### 2. Build on your laptop

```bash
export REGISTRY=quay.io/youruser
./laptop/build.sh RedHatAI/Qwen3-8B-FP8-dynamic latest --push
```

→ See [LAPTOP.md](laptop/LAPTOP.md)

### 3. Build in an OpenShift cluster

```bash
export QUAY_REGISTRY=quay.io/youruser
export QUAY_USERNAME=youruser+robot
export QUAY_PASSWORD=your-quay-token
export HF_TOKEN=hf_xxxxxxxxxxxx
./openshift/deploy.sh all RedHatAI/Qwen3-8B-FP8-dynamic
```

→ See [OPENSHIFT.md](openshift/OPENSHIFT.md)

### 4. Run the Data Science Pipeline

```bash
pip install -r pipeline/requirements.txt
python pipeline/model_car_pipeline.py

export DSP_HOST="https://$(oc get route ds-pipeline-dspa -o jsonpath='{.spec.host}')"
export DSP_TOKEN="$(oc whoami -t)"
python pipeline/run_pipeline.py \
    --model-repo RedHatAI/Qwen3-8B-FP8-dynamic \
    --image quay.io/youruser/qwen3-8b-fp8:latest \
    --model-name qwen3-8b-fp8 --model-version 1.0.0
```

The pipeline **downloads → builds → pushes → registers** the model car in the
OpenShift AI **Model Registry**, ready to deploy from the dashboard.

→ See [PIPELINE.md](pipeline/PIPELINE.md)

## Deploying a model car

Once built and pushed, deploy with KServe by referencing the image as an OCI
connection URI:

```
oci://quay.io/youruser/granite-3.3-2b-instruct:latest
```

In the OpenShift AI dashboard: *Project → Models → Deploy model →* connection
type **OCI compliant registry**. Or apply
[`examples/inferenceservice-modelcar.yaml`](examples/inferenceservice-modelcar.yaml).

## Choosing a model

[`examples/model-catalog.json`](examples/model-catalog.json) lists two groups:

- **Red Hat AI validated models** — third-party generative AI models tested and
  verified by Red Hat AI across supported hardware. Available on Hugging Face
  under [`RedHatAI`](https://huggingface.co/RedHatAI), distributed as
  quantized (FP8 / INT4) variants that keep image sizes practical.
- **Popular Hugging Face models** — widely used open models (not part of the
  validation program).

Any `org/model` repo on Hugging Face works — the catalog is a convenience, not
a limit.

## Security notes

- **Never commit tokens.** `HF_TOKEN` and registry credentials are passed via
  environment variables or build secrets. `.gitignore` excludes common token
  files. If you cloned a version of the original `Containerfile` with a
  hardcoded token, rotate that token immediately.
- The laptop `Containerfile` passes `HF_TOKEN` as a **build secret**, so it is
  not baked into image history.
- Model cars built here pull only `safetensors` + config by default —
  `safetensors` avoids pickle-based "model-as-code" risks.
- `buildconfig.yaml` is intentionally **left unchanged** from the original and
  should not be edited as part of this project.

## Prerequisites summary

| Method | Needs |
|--------|-------|
| Laptop | `podman` or `docker`, local disk, registry account |
| OpenShift | `oc` CLI + cluster login, registry account |
| Pipeline | OpenShift AI with Data Science Pipelines + Model Registry |

## License

Provided as-is for use with Red Hat OpenShift AI and KServe. Review and adapt
to your organization's policies before production use.
