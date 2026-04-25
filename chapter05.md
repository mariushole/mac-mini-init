[Back to main guide](README.md)

# Chapter 05 - Install Local LLM Runtime for Headless OpenClaw

This chapter installs and verifies the local LLM runtime before OpenClaw provider onboarding. OpenClaw can be installed without a local model runtime, but onboarding is cleaner when the intended local model path is already known and tested.

As of April 2026, this guide uses this baseline:

```text
Runtime: MLX-LM
Model: mlx-community/Qwen3.5-9B-OptiQ-4bit
Host: Mac mini M4 with 16 GB unified memory
Python: Python 3.12 with OpenSSL
Install user: non-admin OpenClaw runtime user, for example openclaw
```

MLX-LM proves local Apple Silicon CLI inference. It is not automatically an always-on OpenClaw provider endpoint. Chapter 07 decides how OpenClaw consumes local inference.

## 1. Operating Rules

- Run the local LLM runtime as the non-admin OpenClaw runtime user, for example `openclaw`.
- Use `adminuser` only for system/package-manager bootstrap tasks such as Homebrew or Python installation.
- Exit the admin shell immediately after admin work is done.
- Do not install Python packages with `sudo pip`.
- Do not create the MLX-LM venv as `adminuser`.
- Do not use Apple/system Python 3.9 + LibreSSL as the guide baseline.
- Do not use 27B/35B models as the default on a 16 GB Mac mini.

## 2. Confirm the Runtime User

Run this as the OpenClaw runtime user:

```bash
whoami
id -Gn
pwd
```

Expected:

```text
whoami: openclaw or the chosen runtime user
id -Gn: does not include admin
pwd: /Users/openclaw or that user's home directory
```

If the user is in the `admin` group, fix that before continuing. The local LLM runtime and OpenClaw should not run from the admin account.

## 3. Check the Existing Python

```bash
command -v python3 || true
python3 --version || true
python3 -c "import ssl; print(ssl.OPENSSL_VERSION)" 2>/dev/null || true
```

If this shows `/usr/bin/python3`, Python `3.9.x`, or `LibreSSL`, do not use it for the MLX-LM venv. It can still run small scripts, but it is not the repeatable baseline for this guide.

The preferred baseline is Python 3.12 with OpenSSL, installed through Homebrew or the official Python.org macOS installer.

## 4. Install Homebrew and Python 3.12 if Needed

Check for Homebrew and Python 3.12:

```bash
command -v brew || true
test -x /opt/homebrew/bin/python3.12 && /opt/homebrew/bin/python3.12 --version || true
```

If both are present, skip to Section 5.

If Homebrew is missing, or if `brew install python@3.12` requires admin rights, switch temporarily to the admin account:

```bash
su - adminuser
```

From the admin shell, install Homebrew if needed:

```bash
cd ~

if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

eval "$(/opt/homebrew/bin/brew shellenv)"
command -v brew
brew --version
```

Install Python 3.12:

```bash
brew install python@3.12
/opt/homebrew/bin/python3.12 --version
/opt/homebrew/bin/python3.12 -c "import ssl; print(ssl.OPENSSL_VERSION)"
```

Exit the admin shell:

```bash
exit
```

Back as the runtime user, load Homebrew and verify Python:

```bash
whoami
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
command -v brew
/opt/homebrew/bin/python3.12 --version
/opt/homebrew/bin/python3.12 -c "import ssl; print(ssl.OPENSSL_VERSION)"
```

Expected:

```text
whoami: openclaw or the chosen runtime user
Python 3.12.x
OpenSSL ...
```

If Homebrew is not allowed on this host, install a current Python 3.12+ macOS package from Python.org, then verify `python3.12 --version` and its SSL backend before continuing.

## 5. Select Python 3.12

Run this as the runtime user:

```bash
if [ -x /opt/homebrew/bin/python3.12 ]; then
  PYTHON_BIN="/opt/homebrew/bin/python3.12"
elif command -v python3.12 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3.12)"
else
  echo "Python 3.12 not found. Install Homebrew Python or Python.org Python before continuing."
  exit 1
fi

echo "$PYTHON_BIN"
"$PYTHON_BIN" --version
"$PYTHON_BIN" -c "import ssl; print(ssl.OPENSSL_VERSION)"
```

Do not proceed unless this shows Python 3.12 and OpenSSL.

## 6. Create a Clean MLX-LM Virtual Environment

If an old venv exists, remove it. This is intentional: a venv created with Apple/system Python 3.9 will keep using Python 3.9 even after Python 3.12 is installed.

```bash
deactivate 2>/dev/null || true

mkdir -p ~/local-llm
cd ~/local-llm
rm -rf .venv

"$PYTHON_BIN" -m venv .venv
source .venv/bin/activate

python --version
python -c "import ssl; print(ssl.OPENSSL_VERSION)"
python -m pip install --upgrade pip
```

Hard stop if the venv is wrong:

```bash
python - <<'PY'
import ssl
import sys

print("python:", sys.version.split()[0])
print("ssl:", ssl.OPENSSL_VERSION)

if sys.version_info < (3, 11):
    raise SystemExit("Stop: venv is too old. Rebuild it with Python 3.12.")

if "LibreSSL" in ssl.OPENSSL_VERSION:
    raise SystemExit("Stop: venv uses LibreSSL. Rebuild it with Python 3.12 from Homebrew or Python.org.")
PY
```

Install MLX-LM inside the venv:

```bash
python -m pip install mlx-lm

python -m pip show mlx-lm
python -c "import mlx_lm; print('mlx-lm import ok')"
mlx_lm.generate --help | head -n 20
```

Expected:

```text
Location: /Users/openclaw/local-llm/.venv/lib/python3.12/site-packages
mlx-lm import ok
```

If the path contains `.venv/lib/python3.9`, stop and rebuild the venv.

## 7. Set the Model

Use a shell variable. Do not paste angle-bracket placeholders into `zsh`.

```bash
MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"
MODEL_URL="https://huggingface.co/$MODEL"
echo "$MODEL"
echo "$MODEL_URL"
```

This is the guide's default model ID as of April 2026. It is Qwen 3.5 9B, MLX format, OptiQ 4-bit / mixed precision, Apache-2.0, and about 6 GB. Recheck the model page before future rebuilds.

Verify and record the model metadata:

```bash
python - <<'PY'
from huggingface_hub import model_info

model_id = "mlx-community/Qwen3.5-9B-OptiQ-4bit"
info = model_info(model_id)
print("model_id:", info.modelId)
print("sha:", info.sha)
print("downloads:", info.downloads)
print("tags:", ", ".join(info.tags or []))
PY
```

If this prints `NotOpenSSLWarning`, stop before generation and rebuild the venv. The metadata check can succeed while the venv is still wrong.

## 8. Check Disk and Memory Before Download

```bash
df -h /
du -sh ~/.cache/huggingface 2>/dev/null || true
du -sh ~/local-llm 2>/dev/null || true
vm_stat
```

The first generation downloads several GB into the Hugging Face cache, usually under `~/.cache/huggingface`. Keep the model set small on a 256 GB Mac mini.

## 9. Download and Run the Local Model

```bash
MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"

time mlx_lm.generate \
  --model "$MODEL" \
  --prompt "You are running locally on a Mac mini. Reply with exactly: local model ok" \
  --max-tokens 20
```

Expected:

```text
local model ok
```

Run one practical prompt:

```bash
time mlx_lm.generate \
  --model "$MODEL" \
  --prompt "In three short bullets, explain why a smaller stable local model can be better than an oversized model on a 16 GB Mac." \
  --max-tokens 160
```

The Mac should remain responsive. Do not tune large context sizes or test larger models during the first setup.

## 10. Final Verification

Run the repo verification script from the checked-out guide:

```bash
./chapter05-verify.sh
```

Or fetch and run the current script directly:

```bash
REPO_RAW_BASE="https://raw.githubusercontent.com/YOUR-GITHUB-USER/mac-mini-init/main"
curl -fsSL "$REPO_RAW_BASE/chapter05-verify.sh" | bash
```

Replace `YOUR-GITHUB-USER` with the GitHub account that hosts your fork of this guide.

The script checks:

- runtime user and admin-group status
- active venv path
- Python version and SSL backend
- MLX-LM import and package location
- Hugging Face model metadata
- local model cache presence
- disk and memory summary
- short local generation test

The final result should be human-readable. If it ends with `RESULT: PASS`, Chapter 05 is complete.

## 11. Install Record

Record:

```text
Local LLM runtime: MLX-LM
Runtime version:
Python executable:
Python version:
SSL library:
Virtual environment path:
Homebrew installed: yes/no
Homebrew path:
Hugging Face cache path:
Model family: Qwen 3.5 9B
Exact model ID: mlx-community/Qwen3.5-9B-OptiQ-4bit
Model SHA / revision:
Quantization: OptiQ 4-bit / mixed precision
Model disk usage:
First test date:
Observed latency:
Observed memory pressure:
Fallback used: yes/no
Notes:
```

## End-of-Chapter Check

- [ ] Runtime user is non-admin.
- [ ] Admin work, if needed, was done through temporary `su - adminuser`.
- [ ] Admin shell was exited before venv creation, MLX-LM install, metadata checks, or model generation.
- [ ] Python 3.12 with OpenSSL was selected deliberately.
- [ ] `/usr/bin/python3` Python 3.9 + LibreSSL was not used as the venv baseline.
- [ ] MLX-LM is installed in `~/local-llm/.venv`.
- [ ] No Python packages were installed with `sudo`.
- [ ] Default model is set with `MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"`.
- [ ] Local generation test completed.
- [ ] Disk and memory impact were checked.
- [ ] `chapter05-verify.sh` returned `RESULT: PASS`.
- [ ] OpenClaw provider onboarding remains deferred to Chapter 07.

**TROUBLESHOOTING STARTS HERE**
================================

Everything above is the normal installation/setup path. Do not start here unless the normal path failed.

## Troubleshooting

### `brew: command not found`

Homebrew is missing or not on `PATH`.

```bash
su - adminuser
cd ~
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"
command -v brew
brew --version
exit
```

Back as the runtime user:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
command -v brew
```

### Python is `/usr/bin/python3`, Python 3.9, or LibreSSL

The host is using Apple/system Python. Install Python 3.12, then rebuild the venv.

```bash
su - adminuser
eval "$(/opt/homebrew/bin/brew shellenv)"
brew install python@3.12
/opt/homebrew/bin/python3.12 --version
exit
```

Back as the runtime user:

```bash
cd ~/local-llm
rm -rf .venv
/opt/homebrew/bin/python3.12 -m venv .venv
source .venv/bin/activate
python --version
python -c "import ssl; print(ssl.OPENSSL_VERSION)"
python -m pip install --upgrade pip
python -m pip install mlx-lm
```

### `NotOpenSSLWarning`

The venv was likely created with Apple/system Python linked against LibreSSL. Rebuild it with Python 3.12 before running model generation.

### `ValueError: Model type qwen3_5 not supported`

The model downloaded, but the installed `mlx-lm` does not support Qwen 3.5. This usually means the venv was created with Apple/system Python 3.9 and pip installed a compatible but insufficient runtime.

Confirm:

```bash
python --version
python -c "import ssl; print(ssl.OPENSSL_VERSION)"
python -m pip show mlx-lm
```

If the path contains `.venv/lib/python3.9`, rebuild the venv with Python 3.12.

### `zsh: no such file or directory: <model-id>`

An angle-bracket placeholder was pasted literally. In `zsh`, `<...>` is input redirection.

Use:

```bash
MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"
mlx_lm.generate --model "$MODEL" --prompt "Reply with: local model ok" --max-tokens 20
```

### Hugging Face download is slow or fails

Check DNS/internet first:

```bash
curl -I https://huggingface.co
python - <<'PY'
from huggingface_hub import model_info
print(model_info("mlx-community/Qwen3.5-9B-OptiQ-4bit").modelId)
PY
```

### Mac becomes sluggish or swaps heavily

Stop the test. Do not try larger models. Keep Chapter 05 at Qwen 3.5 9B or smaller.

## Fallback

If MLX-LM or the Qwen 3.5 9B model cannot be made stable, document the failure and continue with Chapter 06. Use Chapter 07 to choose a supported provider path.

Ollama is the practical fallback when an HTTP API server is needed later:

```bash
ollama --version
ollama pull qwen2.5:7b
ollama run qwen2.5:7b
```

Ollama fallback belongs to Chapter 07 provider integration, not this core MLX-LM baseline.

## References

- [Best Local LLMs for Mac in 2026 - InsiderLLM](https://insiderllm.com/guides/best-local-llms-mac-2026/)
- [MLX-LM on GitHub](https://github.com/ml-explore/mlx-lm)
- [mlx-community/Qwen3.5-9B-OptiQ-4bit on Hugging Face](https://huggingface.co/mlx-community/Qwen3.5-9B-OptiQ-4bit)
- [Homebrew installation documentation](https://docs.brew.sh/Installation)
- [Python macOS downloads](https://www.python.org/downloads/macos/)

---

Previous: [Chapter 04 - Prepare SSH and Headless Operations](chapter04.md)
Next: [Chapter 06 - Install and Bootstrap OpenClaw](chapter06.md)
[Back to main guide](README.md)
