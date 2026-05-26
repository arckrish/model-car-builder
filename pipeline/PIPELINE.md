# Data Science Pipeline — Build & Register a Model Car

This pipeline runs on **Red Hat OpenShift AI Data Science Pipelines** (Kubeflow
Pipelines v2). It automates the full model car lifecycle:

```
download (Hugging Face)  →  build + push (Buildah → registry)  →  register (Model Registry)
```

The end result is a model car OCI image in your registry **and** a versioned
entry in the OpenShift AI **Model Registry**, ready to deploy from the dashboard.

## Prerequisites

On your OpenShift cluster / OpenShift AI installation:

1. **Data Science Pipelines server** configured in your data science project.
   In the OpenShift AI dashboard: *Project → Pipelines → Configure pipeline
   server*.

2. **Model Registry** instance enabled. In recent OpenShift AI versions this is
   available under *Settings → Model registry settings*. Note its REST service
   address — it usually looks like:
   `http://modelregistry-<name>-rest.<namespace>.svc.cluster.local:8080`

3. **Secrets** in the project where pipelines run:

   ```bash
   # Hugging Face token (for gated/private models)
   oc create secret generic hf-token \
     --from-literal=token=hf_xxxxxxxxxxxxxxxxxxxx

   # Registry push secret (docker-registry type)
   oc create secret docker-registry quay-push-secret \
     --docker-server=quay.io \
     --docker-username=youruser+robot \
     --docker-password=your-quay-token
   ```

## Compile the pipeline

```bash
pip install -r pipeline/requirements.txt
python pipeline/model_car_pipeline.py
# → produces model_car_pipeline.yaml
```

## Run the pipeline

### Option A — Upload via the dashboard

1. In OpenShift AI: *Project → Pipelines → Import pipeline*.
2. Upload `model_car_pipeline.yaml`.
3. *Create run* and fill in the parameters (`model_repo`, `image`,
   `model_name`, `model_version`, `registry_url`, …).

### Option B — Submit from the CLI

```bash
export DSP_HOST="https://$(oc get route ds-pipeline-dspa -o jsonpath='{.spec.host}')"
export DSP_TOKEN="$(oc whoami -t)"

python pipeline/run_pipeline.py \
    --model-repo RedHatAI/Qwen3-8B-FP8-dynamic \
    --image quay.io/youruser/qwen3-8b-fp8:latest \
    --model-name qwen3-8b-fp8 \
    --model-version 1.0.0 \
    --registry-url http://modelregistry-sample-rest.kubeflow.svc.cluster.local \
    --registry-port 8080
```

## Pipeline parameters

| Parameter        | Description                                            |
|------------------|--------------------------------------------------------|
| `model_repo`     | Hugging Face repo id, e.g. `RedHatAI/Qwen3-8B-FP8-dynamic` |
| `image`          | Target OCI image, e.g. `quay.io/youruser/qwen3-8b-fp8:latest` |
| `model_name`     | Name the model is registered under in the Model Registry |
| `model_version`  | Semantic version string for this registration         |
| `author`         | Recorded as the registering author                    |
| `registry_url`   | Model Registry REST service URL                        |
| `registry_port`  | Model Registry REST service port (default `8080`)      |

## The three components

| Step | Component | What it does |
|------|-----------|--------------|
| 1 | `download_model` | Validates the repo id and pulls weights/config from Hugging Face. `HF_TOKEN` is injected from the `hf-token` secret. |
| 2 | `build_and_push_model_car` | Builds a minimal `ubi-micro` OCI image with **Buildah** (rootless, no daemon) and pushes it, authenticating with `quay-push-secret`. |
| 3 | `register_model_car` | Registers the pushed image as a versioned model in the OpenShift AI **Model Registry** with `oci://` storage URI and provenance metadata. |

## After the pipeline runs

The model appears in the **Model Registry** in the OpenShift AI dashboard.
From there you can click **Deploy** to create a KServe `InferenceService`, or
apply one manually — see [`examples/inferenceservice-modelcar.yaml`](../examples/inferenceservice-modelcar.yaml).

## Troubleshooting

- **`download` step fails on a gated model** — confirm the `hf-token` secret
  exists and the token has access to that model on Hugging Face.
- **`build_and_push` push fails with `unauthorized`** — confirm
  `quay-push-secret` is a `docker-registry` secret and the robot account has
  *write* access to the target repository.
- **`register` step cannot reach the registry** — verify `registry_url` /
  `registry_port`; the REST service is only reachable from inside the cluster.
- **Buildah `vfs` slowness** — the `vfs` storage driver is used for
  compatibility inside the pipeline pod; large models simply take longer.
