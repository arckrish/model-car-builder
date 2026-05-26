#!/usr/bin/env python3
"""
Model Car Builder — Data Science Pipeline for Red Hat OpenShift AI

This Kubeflow Pipelines (KFP v2) pipeline:

  1. download   — pulls a model from Hugging Face onto a shared workspace.
  2. build_push — builds an OCI "model car" image with Buildah and pushes it
                  to a registry (e.g. Quay).
  3. register   — registers the resulting model car in the Red Hat OpenShift AI
                  Model Registry so it is discoverable and deployable.

It is designed to run on the OpenShift AI pipelines server (Data Science
Pipelines, based on Kubeflow + Argo).

Compile to a pipeline YAML:

    pip install -r pipeline/requirements.txt
    python pipeline/model_car_pipeline.py

This writes `model_car_pipeline.yaml`, which you upload in the OpenShift AI
dashboard under  Data Science Pipelines -> Pipelines -> Import pipeline,
or run directly with run_pipeline.py.

Required cluster prerequisites (see docs/PIPELINE.md):
  * A configured Data Science Pipelines server in your project.
  * Secret `hf-token`         with key `token`        (Hugging Face token).
  * Secret `quay-push-secret` (docker-registry type)  for pushing images.
  * A Model Registry instance enabled in OpenShift AI.
"""

from kfp import dsl, compiler
from kfp.kubernetes import use_secret_as_env

# UBI Python image used for the lightweight steps.
PY_IMAGE = "registry.access.redhat.com/ubi9/python-312:latest"
# Buildah image used to build the OCI model car without a Docker daemon.
BUILDAH_IMAGE = "quay.io/buildah/stable:latest"


# ──────────────────────────────────────────────────────────────────────────────
# Component 1 — Download the model from Hugging Face
# ──────────────────────────────────────────────────────────────────────────────
@dsl.component(base_image=PY_IMAGE, packages_to_install=["huggingface-hub[cli]"])
def download_model(
    model_repo: str,
    model_dir: dsl.OutputPath(),
):
    """Download model weights + config from the Hugging Face Hub."""
    import os
    import re
    import subprocess

    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", model_repo):
        raise ValueError(f"Invalid model repo id: {model_repo!r}")

    os.makedirs(model_dir, exist_ok=True)
    env = dict(os.environ, HF_HUB_DISABLE_XET="1")

    cmd = [
        "hf", "download", model_repo,
        "--local-dir", model_dir,
        "--exclude", "original/*", "*.pth", "*.gguf",
    ]
    print(f"Downloading {model_repo} -> {model_dir}")
    subprocess.run(cmd, check=True, env=env)

    files = os.listdir(model_dir)
    print(f"Downloaded {len(files)} files: {files}")
    if not files:
        raise RuntimeError("No files downloaded — check the repo id / HF_TOKEN.")


# ──────────────────────────────────────────────────────────────────────────────
# Component 2 — Build the model car image and push it to a registry
# ──────────────────────────────────────────────────────────────────────────────
@dsl.component(base_image=BUILDAH_IMAGE)
def build_and_push_model_car(
    model_dir: dsl.InputPath(),
    image: str,
    image_digest: dsl.OutputPath(str),
):
    """Build an OCI model car from the downloaded model and push it."""
    import os
    import subprocess
    import tempfile

    # Minimal, shell-capable base — KServe needs a shell in modelcar images.
    containerfile = """\
FROM registry.access.redhat.com/ubi9/ubi-micro:9.4
COPY models /models
USER root
RUN chmod -R g+rX /models 2>/dev/null || true
USER 1001
"""
    ctx = tempfile.mkdtemp()
    os.symlink(model_dir, os.path.join(ctx, "models"))
    with open(os.path.join(ctx, "Containerfile"), "w") as fh:
        fh.write(containerfile)

    # Build with Buildah (rootless, no daemon).
    subprocess.run(
        ["buildah", "bud", "--storage-driver=vfs",
         "-f", "Containerfile", "-t", image, "."],
        check=True, cwd=ctx,
    )

    # Push using the mounted quay-push-secret (mounted at /var/run/secrets/quay).
    authfile = "/var/run/secrets/quay/.dockerconfigjson"
    push_cmd = ["buildah", "push", "--storage-driver=vfs"]
    if os.path.exists(authfile):
        push_cmd += ["--authfile", authfile]
    push_cmd += [image, f"docker://{image}"]
    subprocess.run(push_cmd, check=True)

    # Capture the pushed image digest for traceable registration.
    digest = subprocess.run(
        ["buildah", "inspect", "--storage-driver=vfs",
         "--format", "{{.FromImageDigest}}", image],
        capture_output=True, text=True,
    ).stdout.strip()

    with open(image_digest, "w") as fh:
        fh.write(digest or "unknown")
    print(f"Pushed model car: {image}  digest={digest}")


# ──────────────────────────────────────────────────────────────────────────────
# Component 3 — Register the model car in the OpenShift AI Model Registry
# ──────────────────────────────────────────────────────────────────────────────
@dsl.component(base_image=PY_IMAGE, packages_to_install=["model-registry"])
def register_model_car(
    model_repo: str,
    image: str,
    image_digest: str,
    registry_url: str,
    registry_port: int,
    model_name: str,
    model_version: str,
    author: str,
):
    """Register the model car as a versioned entry in the Model Registry."""
    from model_registry import ModelRegistry

    registry = ModelRegistry(
        server_address=registry_url,
        port=registry_port,
        author=author,
        is_secure=False,
    )

    oci_uri = f"oci://{image}"
    rm = registry.register_model(
        name=model_name,
        uri=oci_uri,
        version=model_version,
        model_format_name="safetensors",
        model_format_version="1.0",
        storage_key="modelcar",
        metadata={
            "source_hf_repo": model_repo,
            "image_digest": image_digest,
            "packaging": "modelcar-oci",
        },
    )
    print(f"Registered '{model_name}' v{model_version} -> {oci_uri}")
    print(f"Model Registry id: {getattr(rm, 'id', 'n/a')}")


# ──────────────────────────────────────────────────────────────────────────────
# Pipeline definition
# ──────────────────────────────────────────────────────────────────────────────
@dsl.pipeline(
    name="model-car-builder",
    description="Download a Hugging Face model, build an OCI model car, "
                "push it to a registry, and register it in OpenShift AI.",
)
def model_car_pipeline(
    model_repo: str = "RedHatAI/granite-3.3-2b-instruct-FP8-dynamic",
    image: str = "quay.io/youruser/granite-3.3-2b-instruct:latest",
    model_name: str = "granite-3.3-2b-instruct",
    model_version: str = "1.0.0",
    author: str = "model-car-pipeline",
    registry_url: str = "http://modelregistry-sample-rest.kubeflow.svc.cluster.local",
    registry_port: int = 8080,
):
    # Step 1 — download. HF_TOKEN injected from the `hf-token` secret.
    download = download_model(model_repo=model_repo)
    use_secret_as_env(download, secret_name="hf-token", secret_key_to_env={"token": "HF_TOKEN"})
    download.set_caching_options(False)
    download.set_memory_limit("8Gi").set_cpu_limit("2")

    # Step 2 — build + push. quay-push-secret mounted for registry auth.
    build = build_and_push_model_car(
        model_dir=download.outputs["model_dir"],
        image=image,
    )
    build.set_caching_options(False)
    build.set_memory_limit("16Gi").set_cpu_limit("4")
    # Mount the docker-registry secret so buildah can authenticate on push.
    from kfp import kubernetes
    kubernetes.use_secret_as_volume(
        build, secret_name="quay-push-secret", mount_path="/var/run/secrets/quay",
    )

    # Step 3 — register in the Model Registry.
    register = register_model_car(
        model_repo=model_repo,
        image=image,
        image_digest=build.outputs["image_digest"],
        registry_url=registry_url,
        registry_port=registry_port,
        model_name=model_name,
        model_version=model_version,
        author=author,
    )
    register.set_caching_options(False)


if __name__ == "__main__":
    compiler.Compiler().compile(
        pipeline_func=model_car_pipeline,
        package_path="model_car_pipeline.yaml",
    )
    print("Compiled pipeline -> model_car_pipeline.yaml")
