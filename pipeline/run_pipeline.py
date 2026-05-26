#!/usr/bin/env python3
"""
run_pipeline.py — submit the Model Car pipeline to an OpenShift AI
Data Science Pipelines server.

This compiles model_car_pipeline.py (if needed) and creates a run on the
pipeline server using the KFP client.

Authentication: the script uses your current `oc` login token and the
Data Science Pipelines route in your project.

Usage:
  # Discover the pipeline route in your project:
  export DSP_HOST="https://$(oc get route ds-pipeline-dspa -o jsonpath='{.spec.host}')"
  export DSP_TOKEN="$(oc whoami -t)"

  python pipeline/run_pipeline.py \
      --model-repo RedHatAI/Qwen3-8B-FP8-dynamic \
      --image quay.io/youruser/qwen3-8b-fp8:latest \
      --model-name qwen3-8b-fp8 \
      --model-version 1.0.0
"""
import argparse
import os
import sys

try:
    from kfp.client import Client
    from kfp import compiler
except ImportError:
    sys.exit("kfp is not installed. Run: pip install -r pipeline/requirements.txt")

from model_car_pipeline import model_car_pipeline

PIPELINE_YAML = "model_car_pipeline.yaml"


def main() -> None:
    ap = argparse.ArgumentParser(description="Submit the Model Car pipeline.")
    ap.add_argument("--model-repo", required=True, help="Hugging Face repo id")
    ap.add_argument("--image", required=True, help="Target OCI image ref")
    ap.add_argument("--model-name", required=True, help="Name in Model Registry")
    ap.add_argument("--model-version", default="1.0.0")
    ap.add_argument("--author", default="model-car-pipeline")
    ap.add_argument("--experiment", default="model-car-builds")
    ap.add_argument(
        "--registry-url",
        default="http://modelregistry-sample-rest.kubeflow.svc.cluster.local",
        help="Model Registry REST service URL",
    )
    ap.add_argument("--registry-port", type=int, default=8080)
    args = ap.parse_args()

    host = os.environ.get("DSP_HOST")
    token = os.environ.get("DSP_TOKEN")
    if not host or not token:
        sys.exit("Set DSP_HOST and DSP_TOKEN env vars (see docstring).")

    print("Compiling pipeline...")
    compiler.Compiler().compile(model_car_pipeline, PIPELINE_YAML)

    client = Client(host=host, existing_token=token, verify_ssl=False)

    run = client.create_run_from_pipeline_package(
        pipeline_file=PIPELINE_YAML,
        arguments={
            "model_repo": args.model_repo,
            "image": args.image,
            "model_name": args.model_name,
            "model_version": args.model_version,
            "author": args.author,
            "registry_url": args.registry_url,
            "registry_port": args.registry_port,
        },
        experiment_name=args.experiment,
        run_name=f"build-{args.model_name}-{args.model_version}",
    )
    print(f"Submitted run: {run.run_id}")
    print(f"Track it at: {host}")


if __name__ == "__main__":
    main()
