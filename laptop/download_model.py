import os 
import time
from huggingface_hub import snapshot_download

max_retries = 10

# Specify the Hugging Face repository containing the model
#model_repo = "RedHatAI/gpt-oss-120b"
model_repo = "BAAI/bge-m3"


# snapshot_download(
#     repo_id=model_repo,
#     local_dir="./models",
#     allow_patterns=["*.safetensors", "*.json", "*.txt"],
#     token=os.environ.get("HF_TOKEN"),
#     max_workers=4, 
# )

for attempt in range(max_retries):
    try:
        print(f"Attempt {attempt + 1}/{max_retries}")
        snapshot_download(
            repo_id=model_repo,
            local_dir="./models",
            allow_patterns=["*.safetensors", "*.json", "*.txt", "*.bin"],
            token=os.environ.get("HF_TOKEN"),
            max_workers=2,      # lower = more stable on flaky connections
        )
        print("Download complete!")
        break
    except Exception as e:
        print(f"Failed: {e}")
        if attempt < max_retries - 1:
            wait = 30 * (attempt + 1)
            print(f"Retrying in {wait}s...")
            time.sleep(wait)
        else:
            print("Max retries reached.")
            raise
