[Back to main guide](README.md)

# Chapter 05 - Install Local LLM Runtime for Headless OpenClaw

This chapter installs and verifies the local LLM runtime before OpenClaw provider onboarding. The goal is to make sure the Mac mini can run a suitable local model over SSH before OpenClaw is configured to use it.

As of April 2026, this guide uses MLX-LM and Qwen 3.5 9B as the default local inference baseline for a Mac mini M4 with 16 GB unified memory.

Sources used for model/runtime context:

- [Best Local LLMs for Mac in 2026 - InsiderLLM](https://insiderllm.com/guides/best-local-llms-mac-2026/)
- [MLX-LM on GitHub](https://github.com/ml-explore/mlx-lm)
- [mlx-community/Qwen3.5-9B-OptiQ-4bit on Hugging Face](https://huggingface.co/mlx-community/Qwen3.5-9B-OptiQ-4bit)

OpenClaw can be installed before a local model runtime exists, but provider onboarding becomes cleaner if the intended local runtime and model are already installed and tested. Otherwise onboarding may push the operator into temporary or GUI-oriented provider choices.

The local model runtime is a dependency for a clean OpenClaw operating setup, even if it is not strictly required for installing the OpenClaw CLI.

## 1. Scope

This chapter covers:

- Why local LLM setup comes before OpenClaw provider setup.
- Why MLX-LM is the recommended first runtime for this guide.
- Why Qwen 3.5 9B is the recommended first model for a Mac mini M4 with 16 GB unified memory.
- How to select a modern Python baseline before creating the virtual environment.
- How to install MLX-LM without `sudo`.
- How to run a local Qwen 3.5 9B test.
- How to validate memory and storage impact.
- How to document the model path and runtime decision.

This chapter does not cover OpenClaw install, `openclaw doctor`, OpenClaw gateway setup, provider onboarding, channel setup, LaunchAgent setup, or persistent service design. Those belong in Chapter 06 and Chapter 07.

## 2. Recommendation

```text
Recommended runtime: MLX-LM
Recommended first model: mlx-community/Qwen3.5-9B-OptiQ-4bit
Model family: Qwen 3.5 9B, OptiQ 4-bit / mixed precision
Target host: Mac mini M4, 16 GB unified memory
Date of recommendation: April 2026
```

Reasoning:

- InsiderLLM's April 2026 guide places 16 GB Macs in the practical 7B-9B tier.
- It recommends Qwen 3.5 9B Q4 as the pick for 16 GB Macs.
- It describes the Qwen 3.5 9B Q4 footprint as roughly 6.6 GB with a practical speed range around 20-40 tok/s.
- It describes MLX-LM as the Apple-native/Python CLI path for maximum speed when the model is supported.
- The Hugging Face model page for `mlx-community/Qwen3.5-9B-OptiQ-4bit` identifies it as MLX, text-generation, Apache-2.0, Qwen 3.5 9B, 4-bit/mixed precision, about 6.04 GB, and says the basic path works with stock `mlx-lm`.
- On a 16 GB Mac, 27B/35B models are not the right default because OpenClaw-style agent workflows need headroom for macOS, runtime overhead, and context/KV cache.
- A smaller stable 9B model is more useful than a larger model that technically loads but starves context or swaps.

This is the guide's tested/default model ID as of April 2026. It is not the only valid Qwen 3.5 9B model. Recheck the model page before future rebuilds.

> **Why Not Start with a 27B/35B Model?**
>
> A model that technically loads is not necessarily operationally useful. On a 16 GB Mac mini, larger 27B/35B models leave too little headroom for macOS, context, runtime overhead, and OpenClaw agent workflows. Start with Qwen 3.5 9B and only test larger models later as experiments.

> **MLX-LM vs Ollama vs LM Studio**
>
> MLX-LM is preferred in this chapter for Apple-native performance and a clean Python CLI workflow.
>
> Ollama is useful when an API server is needed quickly and model management simplicity matters.
>
> LM Studio is useful for GUI experimentation, visual model browsing, and manual parameter tuning.
>
> For a permanent SSH/headless Mac mini, avoid making LM Studio the default dependency.
>
> If OpenClaw later requires an HTTP provider endpoint rather than a CLI-only model path, Chapter 07 should handle that explicitly by either using a supported OpenClaw provider path or adding a deliberately chosen local model server. Do not hide this distinction.

> **Important Honesty Note**
>
> MLX-LM is excellent for local CLI inference, but it is not the same thing as an always-on OpenClaw provider endpoint. This chapter proves that the Mac can run the model locally. Chapter 07 decides how OpenClaw will consume local inference: directly if supported by the installed OpenClaw version, or through a deliberately selected local provider/server path.

## 3. Confirm Runtime User and Python Baseline

Run as the non-admin OpenClaw runtime user:

```bash
whoami
id -Gn
pwd
command -v python3 || true
python3 --version || true
python3 -c "import ssl; print(ssl.OPENSSL_VERSION)" 2>/dev/null || true
```

Expected:

```text
whoami: openclaw or the chosen runtime user
id -Gn: does not include admin
pwd: /Users/openclaw or that user's home directory
python: preferably Python 3.11 or 3.12
ssl: OpenSSL, not Apple LibreSSL, for the preferred baseline
```

If `python3` is `/usr/bin/python3`, reports Python 3.9.x, and SSL reports LibreSSL, do not use it as the guide baseline for MLX-LM.

The macOS system Python may be old, for example Python 3.9. A Python 3.9 venv can force older MLX-LM versions and trigger dependency backtracking.

Apple/system Python may also be linked against LibreSSL, causing warnings such as:

```text
NotOpenSSLWarning: urllib3 v2 only supports OpenSSL 1.1.1+, currently the 'ssl' module is compiled with 'LibreSSL 2.8.3'
```

This warning is not always fatal, but it is a poor baseline for a repeatable guide.

The recommended baseline is a modern user-owned Python, preferably Python 3.12. Do not use `sudo pip`.

## 4. Install Homebrew if Missing

Check whether Homebrew is installed:

```bash
command -v brew || true
```

If nothing is returned, Homebrew is not installed. For this guide, Homebrew is the preferred way to install Python 3.12 on Apple Silicon because it installs into `/opt/homebrew` and gives a repeatable CLI-managed Python path.

Installing Homebrew is a system/package-manager bootstrap step. The non-admin `openclaw` runtime user may not have `sudo`, and that is expected. If the installer says the current user needs to be an Administrator, switch temporarily to the admin account:

```bash
su - adminuser
```

Install Homebrew from the admin shell:

```bash
cd ~

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

The Homebrew installer may ask for the admin user's password to create or adjust `/opt/homebrew`. That is a system/package-manager bootstrap step, not an OpenClaw runtime step.

Set up the Apple Silicon shell environment:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Install Python 3.12 while still in the admin shell:

```bash
brew install python@3.12
```

Verify Homebrew and Python from the admin shell:

```bash
command -v brew
brew --version
brew doctor
/opt/homebrew/bin/python3.12 --version
/opt/homebrew/bin/python3.12 -c "import ssl; print(ssl.OPENSSL_VERSION)"
```

`brew doctor` may print warnings. Document serious warnings, but do not chase unrelated cosmetic warnings during this chapter.

Exit the admin shell immediately after the system/package-manager work is complete:

```bash
exit
```

Back as the runtime user, load Homebrew into the runtime user's shell and verify Python:

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

After installation, normal `brew install` operations should run as the user when Homebrew permissions allow it. If the standard runtime user cannot install packages, do not make the runtime user an admin just to continue. Switch temporarily to `adminuser`, perform the system/package-manager task, then `exit` back to `openclaw`.

Do not run OpenClaw itself as admin/root. Do not create the MLX-LM venv while still inside `su - adminuser`.

If Homebrew installation is not allowed, use the official Python.org macOS installer as the alternative path.

### Alternative: Python.org macOS Installer

If Homebrew is not desired, install a current Python 3.12+ macOS installer from Python.org. Use the signed macOS installer package, then verify the installed Python path before creating the venv.

Verify:

```bash
command -v python3.12 || true
python3.12 --version || true
python3.12 -c "import ssl; print(ssl.OPENSSL_VERSION)" || true
```

Prefer Homebrew for this guide because later CLI dependencies are easier to manage. Python.org is acceptable if Homebrew is not part of the host baseline.

Do not use `/usr/bin/python3` for the MLX-LM venv baseline unless explicitly accepting a fallback/degraded path.

## 5. Install or Select Python 3.12

First check whether Python 3.12 is already available:

```bash
command -v brew
test -x /opt/homebrew/bin/python3.12 && /opt/homebrew/bin/python3.12 --version
```

If `/opt/homebrew/bin/python3.12` is missing and Homebrew is installed, install Python as a deliberate package-manager task. If the non-admin runtime user cannot run the install, switch temporarily to the admin account:

```bash
su - adminuser
eval "$(/opt/homebrew/bin/brew shellenv)"
brew install python@3.12
/opt/homebrew/bin/python3.12 --version
/opt/homebrew/bin/python3.12 -c "import ssl; print(ssl.OPENSSL_VERSION)"
exit
```

After exiting the admin shell, verify again as the runtime user:

```bash
whoami
/opt/homebrew/bin/python3.12 --version
/opt/homebrew/bin/python3.12 -c "import ssl; print(ssl.OPENSSL_VERSION)"
```

Expected:

```text
Python 3.12.x
OpenSSL ...
```

Expected `whoami` is `openclaw` or the chosen non-admin runtime user. Continue only after leaving the admin shell.

Fallback selector if Python 3.12 is installed somewhere else:

```bash
command -v python3.12
python3.12 --version
python3.12 -c "import ssl; print(ssl.OPENSSL_VERSION)"
```

Select the Python binary:

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

This prevents accidentally creating the venv with `/usr/bin/python3`. The guide uses `$PYTHON_BIN` for venv creation.

Keep this conservative:

- Do not use random curl-pipe Python installers in this chapter.
- Do not require admin/root for Python package installation.
- Python packages must be installed in a venv owned by the runtime user.

## 6. Create the MLX-LM Virtual Environment

Create the venv with Python 3.12:

```bash
mkdir -p ~/local-llm
cd ~/local-llm

"$PYTHON_BIN" -m venv .venv
source .venv/bin/activate

python --version
python -c "import ssl; print(ssl.OPENSSL_VERSION)"
python -m pip install --upgrade pip
```

Expected:

```text
Python 3.12.x
OpenSSL ...
```

Guard:

```bash
test "$VIRTUAL_ENV" = "$HOME/local-llm/.venv" && echo "venv ok"
```

Install MLX-LM:

```bash
python -m pip install mlx-lm
```

Verify:

```bash
python -m pip show mlx-lm
python -c "import mlx_lm; print('mlx-lm import ok')"
mlx_lm.generate --help | head -n 20
```

MLX-LM should be installed inside `~/local-llm/.venv`. Do not install MLX-LM globally. Do not run `sudo pip install mlx-lm`.

If `mlx_lm.generate` is not found, verify the venv is active:

```bash
echo "$VIRTUAL_ENV"
command -v python
command -v mlx_lm.generate
```

## 7. Recover if the venv Was Created with System Python

If the operator already created `~/local-llm/.venv` with `/usr/bin/python3`, Python 3.9, or LibreSSL, rebuild it.

```bash
deactivate 2>/dev/null || true

cd ~/local-llm
rm -rf .venv

if [ -x /opt/homebrew/bin/python3.12 ]; then
  PYTHON_BIN="/opt/homebrew/bin/python3.12"
elif command -v python3.12 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3.12)"
else
  echo "Python 3.12 not found. Install Homebrew Python or Python.org Python before continuing."
  exit 1
fi

"$PYTHON_BIN" -m venv .venv
source .venv/bin/activate

python --version
python -c "import ssl; print(ssl.OPENSSL_VERSION)"
python -m pip install --upgrade pip
python -m pip install mlx-lm
```

Do not keep debugging MLX-LM on the wrong venv. Rebuild the venv with the intended Python first.

## 8. Select and Record the Qwen 3.5 9B MLX Model

Set the model ID in a shell variable:

```bash
MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"
MODEL_URL="https://huggingface.co/$MODEL"
echo "$MODEL"
echo "$MODEL_URL"
```

As of April 2026, this guide uses `mlx-community/Qwen3.5-9B-OptiQ-4bit` as the default Qwen 3.5 9B MLX model for a Mac mini M4 with 16 GB unified memory.

Why this model:

- It is Qwen 3.5 9B.
- It is an MLX model.
- It is 4-bit/mixed precision.
- It is about 6 GB, which fits the 16 GB Mac tier better than 27B/35B models.
- The model card states the basic usage path works with stock `mlx-lm`.
- It is Apache-2.0 according to the model card.

Do not paste angle-bracket placeholders such as `<model-id>` into zsh. In zsh, `<...>` is treated as input redirection and causes `no such file or directory`.

## 9. How This Guide Locates the Model

- The default model ID is set explicitly in a shell variable.
- The guide verifies the model with `huggingface_hub.model_info`.
- The exact model ID and revision/SHA are recorded.
- This avoids both stale model assumptions and unsafe angle-bracket placeholders.
- If a better Qwen 3.5 9B MLX model becomes available later, update the `MODEL` variable and install record deliberately rather than editing commands ad hoc.

Verify the selected Hugging Face model metadata:

```bash
MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"
MODEL_URL="https://huggingface.co/$MODEL"
echo "$MODEL_URL"

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

If the Hugging Face metadata check fails, do not assume the model is unavailable. Check network/DNS first, then open the model URL manually from another machine if needed.

Record the exact model ID and, if available, the resolved commit SHA in the install record. This makes the local LLM baseline reproducible later.

Check the Hugging Face cache path:

```bash
echo "${HF_HOME:-$HOME/.cache/huggingface}"
```

MLX-LM downloads model files through Hugging Face tooling. The model will normally be cached under `~/.cache/huggingface`. On a 256 GB Mac mini, keep the cache small and deliberate. Do not download several large models during first setup.

## 10. What Went Wrong if zsh Says no such file or directory

> If `zsh` says `no such file or directory: mlx-compatible-qwen-3.5-9b-4bit-model-id`, you pasted an angle-bracket placeholder literally.

In `zsh`, angle brackets are shell input redirection. A placeholder written with brackets must never be pasted literally.

Use a shell variable instead:

```bash
MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"
```

Then always call:

```bash
mlx_lm.generate --model "$MODEL" --prompt "Reply with: local model ok"
```

## 11. Check Resources Before Download

Before the generation test:

```bash
df -h /
du -sh ~/.cache/huggingface 2>/dev/null || true
du -sh ~/local-llm 2>/dev/null || true
vm_stat
```

First generation downloads the model and may take time.

## 12. Run Local Generation Tests

Minimal test:

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

Practical test:

```bash
time mlx_lm.generate \
  --model "$MODEL" \
  --prompt "In three short bullets, explain why a smaller stable local model can be better than an oversized model on a 16 GB Mac." \
  --max-tokens 160
```

Expected:

```text
The model responds without the Mac becoming unusable, without excessive swapping, and with acceptable latency.
```

Do not maximize context on the first run. On a 16 GB Mac mini, prove basic stability first, then tune context and provider behavior later.

Optional chat test:

```bash
mlx_lm.chat --model "$MODEL"
```

Type a short prompt, verify response quality, then exit the chat REPL with `Ctrl-D` or the documented exit command. Do not make the chat REPL mandatory for automation.

## 13. Check Resources After Download and Generation

```bash
df -h /
du -sh ~/.cache/huggingface 2>/dev/null || true
du -sh ~/local-llm 2>/dev/null || true
vm_stat
top -l 1 | head -n 25
```

Notes:

- Model downloads can consume several GB.
- The model cache should grow by several GB.
- On a 256 GB Mac mini, keep the local model set small.
- Do not pull multiple large models during the first build.
- Record model disk usage.
- Watch for memory pressure and swap during tests.
- If the Mac becomes sluggish or starts heavy swapping, stop and do not test larger models.

## 14. Troubleshooting MLX-LM Install and First Model Run

Case 1: `brew: command not found`.

Cause:

```text
Homebrew is not installed or not on PATH.
```

Fix:

```bash
cd ~
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
command -v brew
brew --version
```

Case 2: Python is `/usr/bin/python3`, Python 3.9, LibreSSL.

Cause:

```text
The host is using Apple's system Python.
```

Fix:

```bash
brew install python@3.12
```

Or use the Python.org installer, then rebuild `~/local-llm/.venv`.

Case 3: `NotOpenSSLWarning` / LibreSSL warning.

Cause:

```text
The venv was likely created with Apple/system Python linked against LibreSSL.
```

Fix:

```bash
deactivate 2>/dev/null || true
rm -rf ~/local-llm/.venv
cd ~/local-llm
/opt/homebrew/bin/python3.12 -m venv .venv
source .venv/bin/activate
python -c "import ssl; print(ssl.OPENSSL_VERSION)"
python -m pip install --upgrade pip
python -m pip install mlx-lm
```

Case 4: pip backtracks through many `mlx-lm` versions.

Cause:

```text
Often caused by older Python compatibility constraints.
```

Fix:

```text
Use Python 3.12 and rebuild the venv.
```

Case 5: `zsh: no such file or directory: <model-id>`.

Cause:

```text
An angle-bracket placeholder was pasted literally.
```

Fix:

```bash
MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"
mlx_lm.generate --model "$MODEL" --prompt "Reply with: local model ok" --max-tokens 20
```

Case 6: Hugging Face download is slow or fails.

Fix:

```bash
curl -I https://huggingface.co
python - <<'PY'
from huggingface_hub import model_info
print(model_info("mlx-community/Qwen3.5-9B-OptiQ-4bit").modelId)
PY
```

Then retry generation.

Case 7: Mac becomes unresponsive or swaps heavily.

Fix:

- Stop the test.
- Do not test larger models.
- Consider a smaller model fallback.
- Keep Chapter 05 baseline at Qwen 3.5 9B or smaller.

## 15. Fallback if MLX-LM or Qwen 3.5 9B Setup Is Blocked

Do not block the whole OpenClaw installation indefinitely.

If Python 3.12, MLX-LM, or the Qwen 3.5 9B model cannot be made stable, document the failure and use a smaller or simpler fallback.

For pure MLX-LM fallback, use the MLX-LM default model only to prove the runtime works:

```bash
mlx_lm.generate \
  --prompt "Reply with: mlx-lm default model ok" \
  --max-tokens 20
```

For OpenClaw provider integration fallback, use Ollama later because it provides a local HTTP API server. The Ollama fallback belongs to Chapter 07 provider integration, not the core MLX-LM baseline.

Optional Ollama fallback reminder:

```bash
ollama --version
ollama pull qwen2.5:7b
ollama run qwen2.5:7b
```

Ollama is a fallback provider/server path. MLX-LM proves Apple-native local inference. Do not confuse the two.

## 16. Install Record

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
- [ ] Homebrew presence was checked.
- [ ] If missing, Homebrew was installed or Python.org Python was selected deliberately.
- [ ] Python baseline was checked before venv creation.
- [ ] Python 3.12 or another modern Python was selected deliberately.
- [ ] `/usr/bin/python3` Python 3.9 + LibreSSL was not used as the guide baseline.
- [ ] SSL backend is OpenSSL, not the Apple/system LibreSSL baseline.
- [ ] Venv was rebuilt if it was accidentally created with system Python.
- [ ] MLX-LM is installed in `~/local-llm/.venv`.
- [ ] No Python packages were installed with `sudo`.
- [ ] `mlx_lm.generate --help` works.
- [ ] Default model is recorded as `mlx-community/Qwen3.5-9B-OptiQ-4bit` or a deliberately updated equivalent.
- [ ] Hugging Face model metadata was checked or the failure was documented.
- [ ] Local generation test completed.
- [ ] Disk impact was checked.
- [ ] Memory pressure/swap behavior was checked.
- [ ] The Mac remained responsive during model generation.
- [ ] 27B/35B models were not used as the default on the 16 GB Mac mini.
- [ ] Any fallback runtime/model decision was documented.
- [ ] OpenClaw provider onboarding remains deferred to Chapter 07.

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
