[Back to main guide](README.md)

# Chapter 08 - Prepare, Tune, and Proxy the Local LLM

This chapter turns the local model work from Chapters 05 and 07 into an operational local inference baseline before any human-facing channel is enabled.

The goal is not to chase maximum benchmark numbers. The goal is a stable, loopback-only local LLM path that OpenClaw can use predictably.

Target state:

```text
MLX-LM model exists locally
mlx_lm.generate works
mlx_lm.server works on 127.0.0.1:8080
OpenClaw can reach the local provider path
basic tuning choices are recorded
no model endpoint is exposed to LAN or internet
```

Security baseline:

```text
run as the non-admin OpenClaw runtime user
no sudo for Python packages or model runtime
local model server binds to 127.0.0.1 only
OpenClaw gateway remains loopback-only
no router port forward
no public webhook
no API keys in this repository
```

## 1. Confirm Runtime Context

Run as the OpenClaw runtime user:

```bash
whoami
id -Gn
pwd
echo "$VIRTUAL_ENV"
```

Expected:

```text
whoami: openclaw or the chosen non-admin runtime user
id -Gn: does not include admin
pwd: under the runtime user's home directory
```

Activate the local LLM virtual environment:

```bash
cd ~/local-llm
source .venv/bin/activate
python --version
python -c "import ssl; print(ssl.OPENSSL_VERSION)"
python -m pip show mlx-lm
```

Do not continue from an admin account. Do not reinstall Python packages with `sudo`.

## 2. Confirm Model and Cache State

Use the guide baseline model unless you deliberately documented another model in Chapter 05:

```bash
MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"
HF_CACHE="${HF_HOME:-$HOME/.cache/huggingface}"

echo "MODEL=$MODEL"
echo "HF_CACHE=$HF_CACHE"
du -sh "$HF_CACHE" 2>/dev/null || true
du -sh ~/local-llm 2>/dev/null || true
df -h /
```

Confirm the model metadata is still resolvable:

```bash
python - <<'PY'
from huggingface_hub import model_info

model_id = "mlx-community/Qwen3.5-9B-OptiQ-4bit"
info = model_info(model_id)
print("model_id:", info.modelId)
print("sha:", info.sha)
print("tags:", ", ".join(info.tags or []))
PY
```

If this fails, check DNS and internet access before assuming the model has disappeared.

## 3. Run a Baseline Local Generation Test

Start with a small, deterministic prompt:

```bash
MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"

time mlx_lm.generate \
  --model "$MODEL" \
  --prompt "Reply with exactly: local model ready" \
  --max-tokens 20 \
  --temp 0
```

Expected:

```text
local model ready
```

Run one practical prompt:

```bash
time mlx_lm.generate \
  --model "$MODEL" \
  --prompt "In three short bullets, explain why loopback-only local inference is safer than exposing a model server to the LAN." \
  --max-tokens 180 \
  --temp 0.2
```

If the Mac becomes sluggish, stop here. Do not test larger models until memory pressure is understood.

## 4. Capture Resource Baseline

Record storage and memory before tuning:

```bash
df -h /
du -sh ~/.cache/huggingface 2>/dev/null || true
du -sh ~/local-llm 2>/dev/null || true
vm_stat
top -l 1 | head -n 25
```

Watch for:

- model cache growth of several GB
- swap activity
- sustained high memory pressure
- slow shell responsiveness during generation

On a 16 GB Mac mini, prefer a stable 9B-class model over a larger model that technically loads but leaves too little headroom for OpenClaw, the gateway, channels, browser automation, and macOS itself.

## 5. Tune Conservative Runtime Parameters

Start with conservative values:

```text
temperature: 0.0-0.3 for operational commands
max_tokens: 512-2048 for normal agent replies
context: do not maximize on first build
model server bind: 127.0.0.1
model server port: 8080
```

Practical first-build posture:

```text
low temperature for predictable behavior
small max token limit for smoke tests
increase max tokens only after stability is proven
do not pull 27B/35B models on the 16 GB baseline host
```

Create a local tuning record:

```bash
mkdir -p ~/.openclaw
chmod 700 ~/.openclaw

cat > ~/.openclaw/local-llm-tuning.md <<EOF
# Local LLM Tuning Record

Runtime user: $(whoami)
Runtime: MLX-LM
Model: mlx-community/Qwen3.5-9B-OptiQ-4bit
Model endpoint: http://127.0.0.1:8080/v1
Temperature baseline: 0.0-0.3
Max tokens baseline: 512-2048
Context posture: conservative first build
LAN exposure: no
Last updated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')

Notes:
EOF

chmod 600 ~/.openclaw/local-llm-tuning.md
```

This file is local operational documentation. Do not commit it to Git.

## 6. Start the Local LLM Proxy in Foreground

In this guide, "LLM proxy" means the local OpenAI-compatible HTTP endpoint that exposes the MLX-LM model to OpenClaw.

Start it in the foreground first:

```bash
cd ~/local-llm
source .venv/bin/activate

MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"

mlx_lm.server \
  --model "$MODEL" \
  --host 127.0.0.1 \
  --port 8080
```

Leave this SSH session open.

In a second SSH session, verify the proxy:

```bash
curl -fsS http://127.0.0.1:8080/v1/models
```

Then run a chat-completions test:

```bash
curl -fsS http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mlx-community/Qwen3.5-9B-OptiQ-4bit",
    "messages": [
      {"role": "user", "content": "Reply with exactly: llm proxy ready"}
    ],
    "max_tokens": 20,
    "temperature": 0
  }'
```

Expected:

```text
The response includes: llm proxy ready
```

Stop the foreground server with `Ctrl-C` after the test unless Chapter 07 already installed the user LaunchAgent for it.

## 7. Verify Loopback Binding

Check that the model endpoint is not exposed to the LAN:

```bash
lsof -nP -iTCP:8080 -sTCP:LISTEN
```

Expected:

```text
python or mlx_lm.server listens on 127.0.0.1:8080
```

If `lsof` does not show enough detail and the runtime user cannot use `sudo`, inspect temporarily as admin:

```bash
su - adminuser
sudo lsof -nP -iTCP:8080 -sTCP:LISTEN
exit
```

The endpoint must not listen on `0.0.0.0`.

## 8. Verify OpenClaw Provider Path

Chapter 07 configures OpenClaw to use the local proxy. Verify it before enabling a channel:

```bash
openclaw models status
openclaw doctor
openclaw gateway status
```

If the gateway is running, restart it after model-provider changes:

```bash
openclaw gateway restart
sleep 3
openclaw doctor
```

If OpenClaw cannot see the local model:

- confirm `http://127.0.0.1:8080/v1/models` works
- confirm `~/.openclaw/openclaw.json` points to `http://127.0.0.1:8080/v1`
- confirm the model ID is consistent between MLX-LM and OpenClaw config
- confirm the MLX-LM server is running

## 9. Create a Human-Readable LLM Proxy Check

Create a local check script outside the repository:

```bash
mkdir -p ~/.openclaw/bin
chmod 700 ~/.openclaw ~/.openclaw/bin

cat > ~/.openclaw/bin/check-llm-proxy.sh <<'EOF'
#!/bin/zsh
set -u

MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"
URL="http://127.0.0.1:8080/v1/chat/completions"

echo "Checking local LLM proxy"
echo "Model: $MODEL"
echo "URL: $URL"
echo

if ! curl -fsS http://127.0.0.1:8080/v1/models >/tmp/openclaw-llm-models.json; then
  echo "FAIL: /v1/models is not reachable on 127.0.0.1:8080"
  echo "Start mlx_lm.server or check the LaunchAgent logs."
else
  echo "OK: /v1/models is reachable"
fi

if curl -fsS "$URL" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mlx-community/Qwen3.5-9B-OptiQ-4bit",
    "messages": [
      {"role": "user", "content": "Reply with exactly: local proxy check ok"}
    ],
    "max_tokens": 20,
    "temperature": 0
  }' >/tmp/openclaw-llm-chat.json; then
  echo "OK: chat completion endpoint responded"
  python3 -m json.tool /tmp/openclaw-llm-chat.json >/dev/null 2>&1 && echo "OK: response is JSON"
else
  echo "FAIL: chat completion endpoint did not respond cleanly"
fi

echo
echo "Listening sockets:"
lsof -nP -iTCP:8080 -sTCP:LISTEN 2>/dev/null || true
EOF

chmod 700 ~/.openclaw/bin/check-llm-proxy.sh
```

Run it:

```bash
~/.openclaw/bin/check-llm-proxy.sh
```

Expected:

```text
OK: /v1/models is reachable
OK: chat completion endpoint responded
OK: response is JSON
```

## 10. Install Record

Record:

```text
Runtime user:
Python executable:
MLX-LM version:
Model ID:
Model SHA:
Hugging Face cache path:
LLM proxy URL:
LLM proxy bind:
LLM proxy port:
Temperature baseline:
Max tokens baseline:
Context posture:
Foreground test result:
LaunchAgent installed: yes/no
OpenClaw provider sees model: yes/no
Check script path: ~/.openclaw/bin/check-llm-proxy.sh
Notes:
```

## End-of-Chapter Check

- [ ] Runtime user is non-admin.
- [ ] MLX-LM venv is active when testing.
- [ ] Baseline model ID is recorded.
- [ ] Model metadata check works or the failure is documented.
- [ ] Local generation test works.
- [ ] Resource usage was checked.
- [ ] Tuning record exists at `~/.openclaw/local-llm-tuning.md`.
- [ ] `mlx_lm.server` works in foreground.
- [ ] `/v1/models` responds on `127.0.0.1:8080`.
- [ ] `/v1/chat/completions` responds on `127.0.0.1:8080`.
- [ ] LLM proxy does not bind to `0.0.0.0`.
- [ ] OpenClaw model/provider status was checked.
- [ ] `~/.openclaw/bin/check-llm-proxy.sh` exists and runs.
- [ ] No public router port forward points to the LLM proxy.

---

Previous: [Chapter 07 - Enable Local MLX-LM API Provider for OpenClaw](chapter07.md)
Next: [Chapter 09 - Telegram Bot Integration](chapter09.md)
[Back to main guide](README.md)
