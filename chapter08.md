[Back to main guide](README.md)

# Chapter 08 - Prepare, Tune, and Proxy the Local LLM

This chapter documents the working local MLX/Qwen path OpenClaw should use before Telegram is tested.

The Telegram integration was not the root problem in the observed setup. Telegram token validation, webhook state, `getMe`, `getUpdates`, `sendMessage`, the OpenClaw gateway, and the raw MLX-LM server were basically working. The failures came from the local model/provider path and polluted OpenClaw sessions.

Working architecture:

```text
Telegram
  ↓
OpenClaw gateway
  ↓
127.0.0.1:8081/v1
  ↓
MLX OpenAI cleanup proxy
  ↓
127.0.0.1:8080/v1
  ↓
mlx_lm.server
  ↓
mlx-community/Qwen3.5-9B-OptiQ-4bit
```

Security baseline:

```text
run as the non-admin OpenClaw runtime user
no sudo for Python packages or model runtime
MLX-LM API binds to 127.0.0.1 only
cleanup proxy binds to 127.0.0.1 only
OpenClaw gateway remains loopback-only
Telegram remains DM-only in Chapter 09
Telegram uses long polling/default mode in Chapter 09
bot token stays in ~/.openclaw/secrets/telegram-bot-token
no webhook
no router port forward
no public gateway
no public MLX endpoint
no public proxy endpoint
```

## 1. What Actually Failed

Telegram may appear broken even when Telegram is fine.

The visible symptoms were model/provider/session failures:

```text
raw ChatML replay such as <|im_start|> and <|im_end|>
empty assistant content
reasoning-only output
context-overflow-precheck
estimatedPromptTokens too high
Context limit exceeded
network connection error
incomplete turn detected
payloads=0
```

For this MLX-LM + Qwen setup, the local model path needs:

```text
thinking disabled
stop tokens
response cleanup
streaming compatibility
OpenClaw configs pointing to the cleanup proxy, not directly to MLX-LM
```

This compatibility proxy is required for this MLX-LM + Qwen setup because this model/runtime combination leaked ChatML markers and OpenClaw did not reliably pass the required stop tokens. It is not a universal fix for every local model.

## 2. Confirm Runtime Context

Run as the OpenClaw runtime user:

```bash
whoami
id -Gn
pwd
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

## 3. MLX-LM Server Startup with Thinking Disabled

Create or update the MLX-LM startup script:

```bash
mkdir -p "$HOME/.openclaw/bin" "$HOME/.openclaw/logs"
chmod 700 "$HOME/.openclaw" "$HOME/.openclaw/bin"

cat > "$HOME/.openclaw/bin/start-mlx-lm-server.sh" <<'EOF'
#!/bin/zsh
set -euo pipefail

cd "$HOME/local-llm"
source "$HOME/local-llm/.venv/bin/activate"

MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"
HOST="127.0.0.1"
PORT="8080"

exec mlx_lm.server \
  --model "$MODEL" \
  --host "$HOST" \
  --port "$PORT" \
  --chat-template-args '{"enable_thinking":false}'
EOF

chmod 700 "$HOME/.openclaw/bin/start-mlx-lm-server.sh"
```

`--chat-template-args '{"enable_thinking":false}'` is required for this Qwen profile:

- Without it, Qwen may return reasoning-only output.
- OpenClaw needs normal assistant `content`.
- Telegram should receive concise final answers, not model reasoning fields.

Start MLX-LM in the foreground for the first test:

```bash
"$HOME/.openclaw/bin/start-mlx-lm-server.sh"
```

In another SSH session, verify the running process:

```bash
ps aux | grep '[m]lx_lm.server'
```

Confirm the process includes:

```text
--chat-template-args {"enable_thinking":false}
```

## 4. Direct MLX-LM Validation on 8080

Test raw MLX-LM directly with stop tokens:

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "mlx-community/Qwen3.5-9B-OptiQ-4bit",
    "messages": [
      {"role": "user", "content": "Reply with exactly one word: OK"}
    ],
    "temperature": 0,
    "max_tokens": 64,
    "stop": ["<|im_end|>", "<|im_start|>"]
  }'
```

Expected:

```text
The assistant content should be exactly OK, without ChatML markers.
```

This proves the model can answer cleanly when thinking is disabled and stop tokens are present.

## 5. Local MLX/Qwen Tuning and Cleanup Proxy

OpenClaw should not talk directly to `127.0.0.1:8080/v1` for this model.

Use this path instead:

```text
OpenClaw → 127.0.0.1:8081/v1 → cleanup proxy → 127.0.0.1:8080/v1 → MLX-LM
```

The cleanup proxy:

1. Adds stop tokens to every chat completion request:
   - `<|im_end|>`
   - `<|im_start|>`
2. Strips leaked ChatML tokens from responses:
   - `<|im_start|>`
   - `<|im_end|>`
3. Preserves streaming behavior:
   - if OpenClaw sends `"stream": true`, the proxy keeps streaming enabled
   - it cleans streamed SSE chunks
   - it passes through `data: [DONE]`
   - it does not force `"stream": false`

> **Important: Do Not Use a Non-Streaming-Only Proxy**
>
> OpenClaw expects streaming payloads in this path. Forcing `"stream": false` can cause errors such as `incomplete turn detected` and `payloads=0`.

Create the proxy:

```bash
cat > "$HOME/.openclaw/bin/mlx-openai-clean-proxy.py" <<'PY'
#!/usr/bin/env python3
import json
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = "http://127.0.0.1:8080"
HOST = "127.0.0.1"
PORT = 8081
STOP_TOKENS = ["<|im_end|>", "<|im_start|>"]
CHATML_TOKENS = ["<|im_start|>", "<|im_end|>"]


def clean_text(value):
    if not isinstance(value, str):
        return value
    for token in CHATML_TOKENS:
        value = value.replace(token, "")
    return value.strip()


def clean_json(value):
    if isinstance(value, dict):
        return {key: clean_json(item) for key, item in value.items()}
    if isinstance(value, list):
        return [clean_json(item) for item in value]
    return clean_text(value)


def prepare_payload(raw_body):
    if not raw_body:
        return raw_body
    data = json.loads(raw_body.decode("utf-8"))
    if self_path_is_chat_completions(data):
        stops = data.get("stop")
        if stops is None:
            data["stop"] = STOP_TOKENS
        elif isinstance(stops, str):
            data["stop"] = sorted(set([stops] + STOP_TOKENS))
        elif isinstance(stops, list):
            data["stop"] = sorted(set(stops + STOP_TOKENS))
    return json.dumps(data).encode("utf-8")


def self_path_is_chat_completions(data):
    return isinstance(data, dict) and "messages" in data


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args), file=sys.stderr)

    def upstream_url(self):
        return UPSTREAM + self.path

    def copy_response_headers(self, response, force_event_stream=False):
        excluded = {"connection", "content-length", "transfer-encoding"}
        for key, value in response.headers.items():
            if key.lower() in excluded:
                continue
            if force_event_stream and key.lower() == "content-type":
                continue
            self.send_header(key, value)
        if force_event_stream:
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("X-Accel-Buffering", "no")

    def do_GET(self):
        request = urllib.request.Request(self.upstream_url(), method="GET")
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                body = response.read()
                self.send_response(response.status)
                self.copy_response_headers(response)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        except urllib.error.HTTPError as error:
            body = error.read()
            self.send_response(error.code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    def do_POST(self):
        raw_body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        is_stream = False
        try:
            parsed = json.loads(raw_body.decode("utf-8")) if raw_body else {}
            is_stream = bool(parsed.get("stream"))
            body = prepare_payload(raw_body)
        except Exception as error:
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            payload = json.dumps({"error": str(error)}).encode("utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        request = urllib.request.Request(
            self.upstream_url(),
            data=body,
            method="POST",
            headers={"Content-Type": "application/json"},
        )

        try:
            with urllib.request.urlopen(request, timeout=600) as response:
                self.send_response(response.status)
                self.copy_response_headers(response, force_event_stream=is_stream)
                self.end_headers()

                if is_stream:
                    for line in response:
                        if line.startswith(b"data: "):
                            payload = line[len(b"data: "):].strip()
                            if payload == b"[DONE]":
                                self.wfile.write(b"data: [DONE]\n\n")
                                self.wfile.flush()
                                continue
                            try:
                                cleaned = clean_json(json.loads(payload.decode("utf-8")))
                                line = b"data: " + json.dumps(cleaned).encode("utf-8") + b"\n\n"
                            except Exception:
                                pass
                        self.wfile.write(line)
                        self.wfile.flush()
                else:
                    data = response.read()
                    try:
                        data = json.dumps(clean_json(json.loads(data.decode("utf-8")))).encode("utf-8")
                    except Exception:
                        data = clean_text(data.decode("utf-8", errors="replace")).encode("utf-8")
                    self.wfile.write(data)
        except urllib.error.HTTPError as error:
            body = error.read()
            self.send_response(error.code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception as error:
            payload = json.dumps({"error": str(error)}).encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"MLX cleanup proxy listening on http://{HOST}:{PORT}", file=sys.stderr)
    server.serve_forever()
PY

chmod 700 "$HOME/.openclaw/bin/mlx-openai-clean-proxy.py"
```

Start the proxy in the foreground:

```bash
"$HOME/.openclaw/bin/mlx-openai-clean-proxy.py"
```

Keep this terminal open while testing.

## 6. Test the Cleanup Proxy on 8081

In a second SSH session:

```bash
curl -fsS http://127.0.0.1:8081/v1/models
```

Run the streaming test through the proxy:

```bash
curl -N -s http://127.0.0.1:8081/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "mlx-community/Qwen3.5-9B-OptiQ-4bit",
    "messages": [
      {"role": "user", "content": "Reply with exactly one word: OK"}
    ],
    "temperature": 0,
    "max_tokens": 64,
    "stream": true
  }'
```

Expected:

```text
data: ... "content": "OK" ...
data: [DONE]
```

Check listeners:

```bash
lsof -nP -iTCP:8080 -sTCP:LISTEN
lsof -nP -iTCP:8081 -sTCP:LISTEN
```

Expected:

```text
mlx_lm.server listens on 127.0.0.1:8080
mlx-openai-clean-proxy.py listens on 127.0.0.1:8081
```

Neither service should listen on `0.0.0.0`.

## 7. Optional LaunchAgent for the Cleanup Proxy

Use foreground tests first. Install the user LaunchAgent only after both `8080` and `8081` work.

Create the LaunchAgent:

```bash
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.openclaw/logs"

cat > "$HOME/Library/LaunchAgents/ai.openclaw.mlx-clean-proxy.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>ai.openclaw.mlx-clean-proxy</string>

    <key>ProgramArguments</key>
    <array>
      <string>$HOME/.openclaw/bin/mlx-openai-clean-proxy.py</string>
    </array>

    <key>WorkingDirectory</key>
    <string>$HOME/.openclaw</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>$HOME/.openclaw/logs/mlx-clean-proxy.log</string>

    <key>StandardErrorPath</key>
    <string>$HOME/.openclaw/logs/mlx-clean-proxy.err</string>
  </dict>
</plist>
EOF

chmod 600 "$HOME/Library/LaunchAgents/ai.openclaw.mlx-clean-proxy.plist"
plutil -lint "$HOME/Library/LaunchAgents/ai.openclaw.mlx-clean-proxy.plist"
```

Load it as the runtime user:

```bash
launchctl bootout "gui/$UID/ai.openclaw.mlx-clean-proxy" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/ai.openclaw.mlx-clean-proxy.plist"
launchctl kickstart -k "gui/$UID/ai.openclaw.mlx-clean-proxy"
```

If `launchctl bootstrap` fails with a GUI-domain error, do not use `sudo`. Sign in to the macOS desktop as the OpenClaw runtime user or keep the proxy foreground/manual until a deliberate service model is chosen.

## 8. Patch Both OpenClaw Model Configs

OpenClaw has more than one relevant model config.

Both files must point to the cleanup proxy on port `8081`:

```text
~/.openclaw/openclaw.json
~/.openclaw/agents/main/agent/models.json
```

The `mlx` provider must use:

```json
"baseUrl": "http://127.0.0.1:8081/v1"
```

not:

```json
"baseUrl": "http://127.0.0.1:8080/v1"
```

Back up and patch both configs:

```bash
timestamp="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$HOME/.openclaw-debug/$timestamp"

for config in \
  "$HOME/.openclaw/openclaw.json" \
  "$HOME/.openclaw/agents/main/agent/models.json"
do
  if [ -f "$config" ]; then
    cp "$config" "$HOME/.openclaw-debug/$timestamp/$(basename "$config").bak"
    python3 - "$config" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())

def rewrite(value):
    if isinstance(value, dict):
        return {key: rewrite(item) for key, item in value.items()}
    if isinstance(value, list):
        return [rewrite(item) for item in value]
    if isinstance(value, str):
        return value.replace("http://127.0.0.1:8080/v1", "http://127.0.0.1:8081/v1")
    return value

path.write_text(json.dumps(rewrite(data), indent=2) + "\n")
PY
    chmod 600 "$config"
  else
    echo "Config not found, skipped: $config"
  fi
done
```

Verify no active model config still points to `8080`:

```bash
grep -Rni '127.0.0.1:8080' \
  ~/.openclaw/openclaw.json \
  ~/.openclaw/agents/main/agent/models.json
```

Expected:

```text
No active model config should point to 8080.
```

Then verify both active model configs point to `8081`:

```bash
grep -Rni '127.0.0.1:8081' \
  ~/.openclaw/openclaw.json \
  ~/.openclaw/agents/main/agent/models.json
```

Expected:

```text
Both active model configs should point to 8081.
```

Restart OpenClaw after config changes:

```bash
openclaw gateway restart
sleep 3
openclaw doctor
openclaw models status
```

## 9. Compaction Tuning for the Local Model

The previous reserve was too high for this local model:

```json
"compaction": {
  "reserveTokensFloor": 20000
}
```

For the local MLX/Qwen Telegram profile, use:

```json
"compaction": {
  "reserveTokensFloor": 4096
}
```

`20000` may make sense for large cloud models, but it is too expensive for a local 32k-ish model. `4096` leaves more usable prompt budget while still reserving space for output and compaction.

Patch `~/.openclaw/openclaw.json`:

```bash
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak.$(date +%Y%m%d-%H%M%S)

python3 - <<'PY'
import json
from pathlib import Path

path = Path.home() / ".openclaw" / "openclaw.json"
data = json.loads(path.read_text())
data.setdefault("compaction", {})
data["compaction"]["reserveTokensFloor"] = 4096
path.write_text(json.dumps(data, indent=2) + "\n")
PY

python3 -m json.tool ~/.openclaw/openclaw.json >/dev/null && echo "openclaw.json valid"
```

## 10. Polluted Session Cleanup

Broken Telegram/model sessions can pollute OpenClaw context.

Symptoms:

```text
raw ChatML replay
context-overflow-precheck
estimatedPromptTokens too high
Context limit exceeded
compaction failures
```

Session directory:

```text
~/.openclaw/agents/main/sessions/
```

Rules:

- Stop OpenClaw before touching sessions.
- Archive `~/.openclaw` first.
- Move session files aside rather than deleting them.
- Do not grep-and-quarantine broadly under `~/.openclaw` without excluding installed runtime files.
- Do not move files under `dist/`.

Archive state:

```bash
timestamp="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$HOME/.openclaw-debug/$timestamp"
cp -a "$HOME/.openclaw" "$HOME/.openclaw-debug/$timestamp/openclaw-copy"
```

Stop OpenClaw:

```bash
openclaw gateway stop 2>/dev/null || true
```

Move top-level session files aside. This is macOS-compatible and does not rely on `find -maxdepth`:

```bash
SESSION_DIR="$HOME/.openclaw/agents/main/sessions"
QUARANTINE_DIR="$HOME/.openclaw-debug/$timestamp/quarantined-sessions"

mkdir -p "$QUARANTINE_DIR"

if [ -d "$SESSION_DIR" ]; then
  for file in "$SESSION_DIR"/*; do
    if [ -f "$file" ]; then
      mv "$file" "$QUARANTINE_DIR/"
    fi
  done
else
  echo "Session directory not found: $SESSION_DIR"
fi
```

Restart OpenClaw after the model path and compaction config are fixed:

```bash
openclaw gateway restart
sleep 3
openclaw doctor
```

## 11. Service Order and Health Check

Required running services:

```text
1. MLX-LM server
   127.0.0.1:8080

2. MLX cleanup proxy
   127.0.0.1:8081

3. OpenClaw gateway
   Telegram channel enabled later in Chapter 09
```

Startup order:

```text
1. ai.openclaw.mlx-lm
2. ai.openclaw.mlx-clean-proxy
3. ai.openclaw.gateway
```

Health checklist:

```bash
lsof -nP -iTCP:8080 -sTCP:LISTEN
lsof -nP -iTCP:8081 -sTCP:LISTEN
launchctl list | grep -i openclaw
curl -fsS http://127.0.0.1:8080/v1/models
curl -fsS http://127.0.0.1:8081/v1/models
```

Clean proxy completion test:

```bash
curl -N -s http://127.0.0.1:8081/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "mlx-community/Qwen3.5-9B-OptiQ-4bit",
    "messages": [
      {"role": "user", "content": "Reply with exactly one word: OK"}
    ],
    "temperature": 0,
    "max_tokens": 64,
    "stream": true
  }'
```

Expected:

```text
data: ... "content": "OK" ...
data: [DONE]
```

## 12. Telegram Model Defaults

Recommended local Telegram defaults:

```text
max_tokens: 128-256
temperature: low
thinking: disabled
stop: <|im_end|>, <|im_start|>
```

Telegram prompts are not small from OpenClaw's perspective. OpenClaw adds:

```text
system prompt
agent instructions
channel metadata
tool/plugin context
workspace context
session metadata
user prompt
```

This local 9B model is suitable for:

```text
short answers
private/local chat
status questions
simple planning
light summaries
```

It is not ideal as the only backend for:

```text
large context reasoning
heavy tool workflows
complex coding
long architecture reports
multi-agent orchestration
```

## 13. Final Telegram Testing Guidance

Do this after this chapter is complete and Chapter 09 Telegram integration is configured.

Do not use `/start` as the model-path test. `/start` triggers Telegram/OpenClaw onboarding and persona behavior and can pollute sessions.

Use this Telegram prompt first:

```text
Reply with exactly one word: OK
```

Then test:

```text
Tell me about the architecture you are running on
```

Expected:

```text
The bot should answer coherently without raw ChatML markers, reasoning dumps, or context-limit errors.
```

## 14. Install Record

Record:

```text
Runtime user:
Python executable:
MLX-LM version:
Model ID: mlx-community/Qwen3.5-9B-OptiQ-4bit
MLX-LM bind: 127.0.0.1
MLX-LM port: 8080
Thinking disabled: yes/no
Cleanup proxy path: ~/.openclaw/bin/mlx-openai-clean-proxy.py
Cleanup proxy bind: 127.0.0.1
Cleanup proxy port: 8081
Proxy streaming support tested: yes/no
OpenClaw global config points to 8081: yes/no
OpenClaw main agent config points to 8081: yes/no
Compaction reserveTokensFloor:
Session cleanup performed: yes/no
OpenClaw gateway status:
Notes:
```

## End-of-Chapter Check

- [ ] Runtime user is non-admin.
- [ ] MLX-LM startup script uses `--chat-template-args '{"enable_thinking":false}'`.
- [ ] Raw MLX-LM responds cleanly to the direct `8080` stop-token test.
- [ ] Cleanup proxy exists at `~/.openclaw/bin/mlx-openai-clean-proxy.py`.
- [ ] Cleanup proxy adds stop tokens.
- [ ] Cleanup proxy strips leaked ChatML tokens.
- [ ] Cleanup proxy preserves streaming and passes through `data: [DONE]`.
- [ ] `8080` listens only on `127.0.0.1`.
- [ ] `8081` listens only on `127.0.0.1`.
- [ ] `~/.openclaw/openclaw.json` points the `mlx` provider to `http://127.0.0.1:8081/v1`.
- [ ] `~/.openclaw/agents/main/agent/models.json` points the `mlx` provider to `http://127.0.0.1:8081/v1`.
- [ ] No active OpenClaw model config points to `127.0.0.1:8080`.
- [ ] `reserveTokensFloor` is appropriate for the local model, recommended `4096`.
- [ ] Polluted sessions were archived and moved aside if needed.
- [ ] Health checks for `8080`, `8081`, and OpenClaw gateway pass.
- [ ] Telegram testing will use `Reply with exactly one word: OK`, not `/start`, for the model path.
- [ ] Telegram remains DM-only in Chapter 09.
- [ ] Groups remain disabled.
- [ ] Webhooks remain disabled.
- [ ] No router port forward points to OpenClaw, MLX-LM, or the cleanup proxy.

---

Previous: [Chapter 07 - Enable Local MLX-LM API Provider for OpenClaw](chapter07.md)
Next: [Chapter 09 - Telegram Bot Integration](chapter09.md)
[Back to main guide](README.md)
