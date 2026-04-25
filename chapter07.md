[Back to main guide](README.md)

# Chapter 07 - Enable Local MLX-LM API Provider for OpenClaw

This chapter turns the Chapter 05 local MLX-LM model into a loopback API endpoint that OpenClaw can use.

Scope:

- carry forward the Chapter 05 local model facts
- start `mlx_lm.server` on `127.0.0.1:8080`
- optionally install the user LaunchAgent for the local MLX-LM API service
- configure OpenClaw to use the local OpenAI-compatible endpoint
- verify OpenClaw can see and use the local provider path

Out of scope for this chapter:

- cloud API keys
- channel setup
- device pairing policy
- broad security audits
- LAN exposure
- public access
- custom boot-time LaunchDaemons

Those later topics are parked in [Chapter 99 - Deferred Advanced Operations](chapter99.md).

Security baseline:

```text
OpenClaw runtime user: non-admin
MLX-LM API bind: 127.0.0.1 only
MLX-LM API port: 8080
OpenClaw gateway bind: loopback
OpenClaw gateway port: 18789
Remote access: SSH tunnel only
Public exposure: none
```

Important distinction:

```text
Chapter 05 proved that MLX-LM can run the Qwen model locally.
Chapter 07 creates a local API endpoint that OpenClaw can connect to.
```

`mlx_lm.generate` is a local CLI inference command. It is not, by itself, an OpenClaw provider. For OpenClaw to use the local MLX-LM Qwen model, the model must be exposed through a supported provider path, such as an OpenAI-compatible local API endpoint.

## 1. Confirm Runtime and Gateway Baseline

Run as the OpenClaw runtime user:

```bash
whoami
id -Gn
openclaw config get gateway.mode
openclaw config get gateway.bind
openclaw doctor
```

Expected:

```text
whoami: openclaw or the chosen non-admin runtime user
id -Gn: does not include admin
gateway.mode: local
gateway.bind: loopback
gateway auth: token enabled
```

If needed:

```bash
openclaw config set gateway.mode local
openclaw config set gateway.bind loopback
openclaw doctor
```

## 2. Provision the Local LLM Handoff

Before configuring provider integration, carry forward the Chapter 05 local LLM facts.

Run:

```bash
./chapter07-provision-local-llm.sh
```

Or fetch and run it from the guide repository:

```bash
REPO_RAW_BASE="https://raw.githubusercontent.com/YOUR-GITHUB-USER/mac-mini-init/main"
curl -fsSL "$REPO_RAW_BASE/chapter07-provision-local-llm.sh" | bash
```

Replace `YOUR-GITHUB-USER` with the GitHub account that hosts your fork of this guide.

The script:

- validates that the runtime user is non-admin
- activates `~/local-llm/.venv`
- fails if the venv is still Python 3.9 or LibreSSL
- records Python, MLX-LM, model ID, model SHA, and Hugging Face cache details in `~/.openclaw/local-llm-record.txt`
- creates `~/.openclaw/.env` only if missing, with comments and no fake local-LLM secrets
- enforces `700` on `~/.openclaw` and `600` on the record and `.env` files

Verify:

```bash
cat ~/.openclaw/local-llm-record.txt
```

Expected values should include:

```text
Local LLM runtime: MLX-LM
Python version: Python 3.12.x
SSL library: OpenSSL ...
Exact model ID: mlx-community/Qwen3.5-9B-OptiQ-4bit
Model SHA / revision: ...
```

These values prove what is installed locally. They are not cloud provider secrets.

## 3. Start the MLX-LM API in the Foreground

This is the step that turns local CLI inference into something OpenClaw can connect to.

Security rule:

```text
Bind mlx_lm.server to 127.0.0.1 only.
Do not bind it to 0.0.0.0.
Do not expose it directly to the LAN or internet.
```

Run in one SSH session:

```bash
cd ~/local-llm
source .venv/bin/activate

MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"

mlx_lm.server \
  --model "$MODEL" \
  --host 127.0.0.1 \
  --port 8080
```

Leave this terminal open.

In a second SSH session, verify the local server:

```bash
curl -fsS http://127.0.0.1:8080/v1/models
```

Then test chat completion:

```bash
curl -fsS http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mlx-community/Qwen3.5-9B-OptiQ-4bit",
    "messages": [
      {"role": "user", "content": "Reply with exactly: mlx server ok"}
    ],
    "max_tokens": 20,
    "temperature": 0
  }'
```

Expected:

```text
The response includes: mlx server ok
```

Check listening state:

```bash
lsof -nP -iTCP:8080 -sTCP:LISTEN
```

Expected:

```text
mlx_lm.server or python listens on 127.0.0.1:8080
```

Stop the foreground MLX-LM server with `Ctrl-C` after the test.

## 4. Install the MLX-LM User LaunchAgent

After the foreground server test works, create a user-level persistent service for the local model endpoint.

Service split:

```text
ai.openclaw.mlx-lm       -> local model API endpoint on 127.0.0.1:8080
ai.openclaw.gateway      -> OpenClaw gateway on 127.0.0.1:18789
```

Both should run as the non-admin OpenClaw runtime user.

Run:

```bash
./chapter07-install-mlx-launchagent.sh
```

Or fetch and run it from the guide repository:

```bash
REPO_RAW_BASE="https://raw.githubusercontent.com/YOUR-GITHUB-USER/mac-mini-init/main"
curl -fsSL "$REPO_RAW_BASE/chapter07-install-mlx-launchagent.sh" | bash
```

Replace `YOUR-GITHUB-USER` with the GitHub account that hosts your fork of this guide.

The script:

- determines the runtime user's home directory
- creates `~/.openclaw/bin/start-mlx-lm-server.sh`
- creates `~/Library/LaunchAgents/ai.openclaw.mlx-lm.plist`
- writes absolute paths into the plist
- verifies the plist does not contain literal `$HOME`
- loads and kickstarts the user LaunchAgent
- verifies `http://127.0.0.1:8080/v1/models`

If `launchctl bootstrap` fails with a GUI-domain error, do not use `sudo`. Sign in to the macOS desktop as the OpenClaw runtime user and rerun the script, or run the MLX-LM server manually during bootstrap.

Verify:

```bash
launchctl print "gui/$UID/ai.openclaw.mlx-lm" | head -n 80
curl -fsS http://127.0.0.1:8080/v1/models
```

Check logs if needed:

```bash
tail -n 120 ~/.openclaw/logs/mlx-lm-server.log 2>/dev/null || true
tail -n 120 ~/.openclaw/logs/mlx-lm-server.err 2>/dev/null || true
```

Stop, start, or restart:

```bash
launchctl bootout "gui/$UID/ai.openclaw.mlx-lm"
launchctl bootstrap "gui/$UID" ~/Library/LaunchAgents/ai.openclaw.mlx-lm.plist
launchctl kickstart -k "gui/$UID/ai.openclaw.mlx-lm"
```

## 5. Configure OpenClaw to Use the Local MLX-LM Endpoint

Prerequisites:

```text
mlx_lm.server is reachable on http://127.0.0.1:8080
/v1/models works
/v1/chat/completions works
OpenClaw gateway config is local + loopback
```

Verify the MLX-LM endpoint first:

```bash
curl -fsS http://127.0.0.1:8080/v1/models
```

Back up the OpenClaw config:

```bash
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak.$(date +%Y%m%d-%H%M%S)
chmod 600 ~/.openclaw/openclaw.json*
```

Open the config:

```bash
nano ~/.openclaw/openclaw.json
```

Add or merge a custom OpenAI-compatible provider. Merge carefully with the existing JSON rather than replacing unrelated config:

```json
{
  "models": {
    "mode": "merge",
    "providers": {
      "mlx": {
        "baseUrl": "http://127.0.0.1:8080/v1",
        "apiKey": "mlx-local",
        "api": "openai-completions",
        "models": [
          {
            "id": "mlx-community/Qwen3.5-9B-OptiQ-4bit",
            "name": "Qwen 3.5 9B OptiQ 4-bit via MLX-LM",
            "input": ["text"],
            "reasoning": false,
            "contextWindow": 32768,
            "maxTokens": 2048,
            "cost": {
              "input": 0,
              "output": 0,
              "cacheRead": 0,
              "cacheWrite": 0
            }
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "mlx/mlx-community/Qwen3.5-9B-OptiQ-4bit"
      }
    }
  }
}
```

If the installed OpenClaw version expects a different provider schema, use the current OpenClaw provider documentation and record the difference in the install record.

Validate JSON syntax:

```bash
python3 -m json.tool ~/.openclaw/openclaw.json >/dev/null && echo "openclaw.json is valid JSON"
```

Check model status and rerun doctor:

```bash
openclaw models status
openclaw doctor
```

Restart the OpenClaw gateway:

```bash
openclaw gateway restart
sleep 3
openclaw gateway status
openclaw doctor
```

If OpenClaw does not show the MLX provider, check:

```bash
cat ~/.openclaw/openclaw.json
curl -fsS http://127.0.0.1:8080/v1/models
```

Common problems:

- invalid JSON
- provider added under the wrong key
- `baseUrl` missing `/v1`
- MLX-LM server not running
- model ID mismatch between `mlx_lm.server`, `/v1/models`, and OpenClaw config
- using an OpenClaw version whose custom provider schema differs from this guide

## 6. Verify the Local Path End to End

Check listeners:

```bash
lsof -nP -iTCP:8080 -sTCP:LISTEN
lsof -nP -iTCP:18789 -sTCP:LISTEN
```

Expected:

```text
MLX-LM listens on 127.0.0.1:8080
OpenClaw listens on 127.0.0.1:18789 or another loopback address
```

Check OpenClaw:

```bash
openclaw models status
openclaw gateway status
openclaw doctor
```

From the client machine, keep remote access through the OpenClaw gateway tunnel:

```bash
ssh -N -L 18789:127.0.0.1:18789 openclaw@<mac-mini-ip>
```

Do not create a direct SSH tunnel to the MLX-LM server unless you are deliberately debugging the provider endpoint.

## 7. Local Troubleshooting

If `/v1/models` fails:

```bash
curl -v http://127.0.0.1:8080/v1/models
tail -n 120 ~/.openclaw/logs/mlx-lm-server.err 2>/dev/null || true
```

Check:

- `ai.openclaw.mlx-lm` is loaded if using LaunchAgent
- the venv is active if running foreground
- the model ID is correct
- port `8080` is not already in use
- the plist contains absolute paths, not literal `$HOME`

If the Mac becomes sluggish:

```bash
vm_stat
top -l 1 | head -n 25
```

Stop the MLX-LM server and do not test larger models.

If the LaunchAgent exits with `EX_CONFIG`, inspect the plist:

```bash
grep -n '\$HOME' ~/Library/LaunchAgents/ai.openclaw.mlx-lm.plist || echo "No literal HOME placeholders remain"
launchctl print "gui/$UID/ai.openclaw.mlx-lm" | grep -E 'state|runs|last exit|program|arguments|working directory|stdout|stderr' -A4
```

If literal `$HOME` appears, rerun:

```bash
./chapter07-install-mlx-launchagent.sh
```

## 8. Install and Config Record

Record:

```text
OpenClaw runtime user:
Local LLM runtime:
Local model:
Local LLM record path:
Local LLM provision script:
MLX-LM API endpoint:
MLX-LM LaunchAgent:
OpenClaw provider path:
OpenClaw gateway bind:
OpenClaw gateway port:
SSH tunnel command:
MLX-LM LaunchAgent requires GUI login:
Notes:
```

## End-of-Chapter Check

- [ ] `chapter07-provision-local-llm.sh` was run.
- [ ] Chapter 05 local LLM handoff was recorded in `~/.openclaw/local-llm-record.txt`.
- [ ] Local MLX-LM API endpoint was tested in foreground.
- [ ] `mlx_lm.server` binds only to `127.0.0.1`.
- [ ] `http://127.0.0.1:8080/v1/models` responds.
- [ ] `http://127.0.0.1:8080/v1/chat/completions` responds.
- [ ] `chapter07-install-mlx-launchagent.sh` was run if persistent local MLX-LM service is wanted.
- [ ] The MLX-LM LaunchAgent plist uses absolute paths and no literal `$HOME` placeholders.
- [ ] If using `ai.openclaw.mlx-lm`, it was installed as the runtime user, not admin/root.
- [ ] OpenClaw custom provider points to `http://127.0.0.1:8080/v1`.
- [ ] OpenClaw model configuration uses the intended Qwen model ID.
- [ ] OpenClaw gateway binds only to loopback.
- [ ] OpenClaw gateway is reachable through SSH tunnel.
- [ ] No OpenClaw gateway is exposed on `0.0.0.0`.
- [ ] No MLX-LM server is exposed on `0.0.0.0`.
- [ ] No public router port forward points to OpenClaw or MLX-LM.

## References

- [MLX-LM HTTP model server](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/SERVER.md)
- [OpenClaw model providers](https://github.com/openclaw/openclaw/blob/main/docs/concepts/model-providers.md)

---

Previous: [Chapter 06 - Install and Bootstrap OpenClaw](chapter06.md)
Next: [Chapter 08 - Telegram Bot Integration](chapter08.md)
[Back to main guide](README.md)
