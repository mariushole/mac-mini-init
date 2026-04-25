[Back to main guide](README.md)

# Chapter 05 - Install Local LLM Runtime for Headless OpenClaw

This chapter installs and verifies the local LLM runtime before OpenClaw provider onboarding. The goal is to make sure the Mac mini can run a suitable local model over SSH before OpenClaw is configured to use it.

As of April 2026, this guide uses MLX-LM and Qwen 3.5 9B as the default local inference baseline for a Mac mini M4 with 16 GB unified memory.

Source used for model-sizing context: [Best Local LLMs for Mac in 2026 - InsiderLLM](https://insiderllm.com/guides/best-local-llms-mac-2026/).

OpenClaw can be installed before a local model runtime exists, but provider onboarding becomes cleaner if the intended local runtime and model are already installed and tested. Otherwise onboarding may push the operator into temporary or GUI-oriented provider choices.

The local model runtime is a dependency for a clean OpenClaw operating setup, even if it is not strictly required for installing the OpenClaw CLI.

## 1. Scope

This chapter covers:

- Why local LLM setup comes before OpenClaw provider setup.
- Why MLX-LM is the recommended first runtime for this guide.
- Why Qwen 3.5 9B is the recommended first model for a Mac mini M4 with 16 GB unified memory.
- How to install a user-owned Python environment.
- How to install MLX-LM.
- How to run a local Qwen 3.5 9B test.
- How to validate memory and storage impact.
- How to document the model path and runtime decision.

This chapter does not cover OpenClaw install, `openclaw doctor`, OpenClaw gateway setup, provider onboarding, channel setup, LaunchAgent setup, or persistent service design. Those belong in Chapter 06 and Chapter 07.

## 2. Recommendation

```text
Recommended runtime: MLX-LM
Recommended first model: Qwen 3.5 9B, 4-bit/Q4 class
Target host: Mac mini M4, 16 GB unified memory
Date of recommendation: April 2026
```

Reasoning:

- The InsiderLLM April 2026 guide places 16 GB Macs in the 7B-9B practical tier.
- It identifies Qwen 3.5 9B Q4 as the best all-rounder at that tier.
- It gives the approximate Qwen 3.5 9B Q4 footprint as around 6.6 GB and a practical speed range around 20-40 tok/s.
- It identifies MLX-LM as the Apple-native/Python CLI path for maximum speed when the model is supported.
- On a 16 GB Mac, 27B/35B models are not the right default because OpenClaw-style agent workflows need headroom for macOS, runtime overhead, and context/KV cache.
- A smaller stable 9B model is more useful than a larger model that technically loads but starves context or swaps.

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

## 3. Confirm Runtime User and Python

Run as the non-admin OpenClaw runtime user:

```bash
whoami
id -Gn
python3 --version
```

Expected:

```text
whoami: openclaw or the chosen runtime user
id -Gn: does not include admin
python3: present and modern enough for MLX-LM
```

If Python 3 is missing or too old, treat that as a system prerequisite and handle it deliberately. Do not use `sudo pip`.

All Python packages in this chapter should be installed as the OpenClaw runtime user, not as admin/root.

## 4. Create a User-Owned Python Environment

```bash
mkdir -p ~/local-llm
cd ~/local-llm
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
```

Install MLX-LM:

```bash
python -m pip install mlx-lm
```

Verify:

```bash
python -m pip show mlx-lm
python -c "import mlx_lm; print('mlx-lm import ok')"
```

## 5. Select the Qwen 3.5 9B MLX Model

Preferred model family: Qwen 3.5 9B, 4-bit/MLX-converted variant.

Use a current MLX-compatible Hugging Face model ID from a trusted maintainer such as `mlx-community` or the official Qwen/Alibaba ecosystem if available.

Record the exact model ID used in the install record. Because model IDs can change, this guide does not hardcode one as the only valid choice.

Pattern:

```bash
mlx_lm.generate \
  --model <mlx-compatible-qwen-3.5-9b-4bit-model-id> \
  --prompt "Reply with: local qwen model ok"
```

Replace `<mlx-compatible-qwen-3.5-9b-4bit-model-id>` with the exact MLX-compatible Qwen 3.5 9B model ID selected at install time.

## 6. Run Local Generation Tests

Minimal test:

```bash
time mlx_lm.generate \
  --model <mlx-compatible-qwen-3.5-9b-4bit-model-id> \
  --prompt "You are running locally on a Mac mini. Reply with exactly: local model ok"
```

Expected:

```text
local model ok
```

Practical test:

```bash
time mlx_lm.generate \
  --model <mlx-compatible-qwen-3.5-9b-4bit-model-id> \
  --prompt "In three short bullets, explain why a smaller stable local model can be better than an oversized model on a 16 GB Mac."
```

Expected:

```text
The model responds without the Mac becoming unusable, without excessive swapping, and with acceptable latency.
```

## 7. Check Disk, Cache, and Memory Impact

```bash
df -h /
du -sh ~/.cache/huggingface 2>/dev/null || true
du -sh ~/local-llm 2>/dev/null || true
vm_stat
top -l 1 | head -n 20
```

Notes:

- Model downloads can consume several GB.
- On a 256 GB Mac mini, keep the local model set small.
- Do not pull multiple large models during the first build.
- Record model disk usage.
- Watch for memory pressure and swap during tests.

## 8. Install Record

Record:

```text
Local LLM runtime:
Runtime version:
Python version:
Virtual environment path:
Model family:
Exact model ID:
Quantization:
Model disk usage:
First test date:
Observed latency/speed:
Notes:
```

## 9. Fallback if MLX-LM Model Setup Is Blocked

If a stable MLX-compatible Qwen 3.5 9B model cannot be located or loaded, do not block the whole OpenClaw installation.

Use Ollama as an operational fallback because it provides a simple local API server. The fallback model should still be in the 7B-9B class. A reasonable fallback is Qwen 2.5 7B or another verified Qwen 7B/9B model available in the installed runtime.

Document that this is a fallback, not the preferred MLX-LM baseline.

Optional fallback commands:

```bash
ollama --version
ollama pull qwen2.5:7b
ollama run qwen2.5:7b
```

API test:

```bash
curl http://127.0.0.1:11434/api/chat \
  -d '{
    "model": "qwen2.5:7b",
    "messages": [{"role": "user", "content": "Reply with: local model ok"}],
    "stream": false
  }'
```

Ollama provider onboarding belongs to Chapter 07 if this fallback is used.

## End-of-Chapter Check

- [ ] Local LLM runtime decision is documented.
- [ ] MLX-LM is installed in a user-owned Python virtual environment.
- [ ] No Python packages were installed with `sudo`.
- [ ] Qwen 3.5 9B 4-bit/MLX-compatible model choice is documented.
- [ ] Exact model ID is recorded.
- [ ] Local model generation test works.
- [ ] Disk impact is checked.
- [ ] Memory pressure/swap behavior is checked.
- [ ] The Mac remains responsive during model generation.
- [ ] Larger 27B/35B models were not used as the default on the 16 GB Mac mini.
- [ ] If MLX-LM was blocked, fallback runtime/model decision is documented.
- [ ] OpenClaw provider onboarding is deferred to Chapter 07.

## References

- [Best Local LLMs for Mac in 2026 - InsiderLLM](https://insiderllm.com/guides/best-local-llms-mac-2026/)
- [MLX-LM on GitHub](https://github.com/ml-explore/mlx-lm)
- [Using MLX at Hugging Face](https://huggingface.co/docs/hub/main/mlx)

---

Previous: [Chapter 04 - Prepare SSH and Headless Operations](chapter04.md)
Next: [Chapter 06 - Install and Bootstrap OpenClaw](chapter06.md)
[Back to main guide](README.md)
