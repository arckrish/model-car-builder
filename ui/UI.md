# Interactive UI - Model Car Builder Console

A single-file, dependency-free web app that walks you through building a model
car and generates the exact commands to run.

## Open it

```bash
# Just open the file in a browser
open ui/index.html            # macOS
xdg-open ui/index.html        # Linux

# ...or serve it
python3 -m http.server 8000 --directory ui
# then visit http://localhost:8000
```

No build step, no `npm install` - it is one self-contained `index.html`.

## What it does

The UI guides you through three steps:

1. **Build target** - choose where to build:
   *On your laptop*, *In an OpenShift cluster*, or *Data Science Pipeline*.
2. **Configure** - enter the Hugging Face model repo, target registry, image
   tag, namespace, and (for pipelines) the Model Registry name/version. Any
   `org/model` repo on Hugging Face can be used - including the Red Hat AI
   validated models published under
   [huggingface.co/RedHatAI](https://huggingface.co/RedHatAI).
3. **Generate** - produces ready-to-copy commands for the chosen build target,
   wired to the scripts in this repo (`laptop/build.sh`, `openshift/deploy.sh`,
   `pipeline/run_pipeline.py`). Use **Copy** to copy the snippet, or
   **Download .sh** to save it as an executable shell script (a
   `#!/usr/bin/env bash` shebang and `set -euo pipefail` are added
   automatically).

The model repo field is validated (`organization/model-name`) before commands
are generated. For a curated starting list of models, see
[`examples/model-catalog.json`](../examples/model-catalog.json).

## Why it generates commands instead of running them

The UI is a static file with no backend, so it cannot execute `oc`, `podman`,
or `pip` directly - browsers sandbox exactly that. Generating commands (Copy /
Download) keeps the tool a single shareable file with **no remote-execution
surface**: your credentials stay in your own shell, and you see precisely what
will run before running it. Review the downloaded script, then execute it
yourself:

```bash
chmod +x build-<model>.sh
./build-<model>.sh
```

## Notes

- The UI **generates commands** - it does not run builds itself, so it is safe
  to open anywhere. You run the copied commands in your own terminal.
- It performs no network calls and stores nothing; everything is in-page.
