[Back to main guide](README.md)

# Chapter 07 - Configure OpenClaw Gateway, Providers, Channels, Pairing, and Persistence

Most of this chapter is SSH-safe, but default macOS user LaunchAgent installation may require a GUI login session as the OpenClaw runtime user.

This chapter covers provider integration, the local MLX-LM API endpoint, manual gateway testing, SSH tunnel access, channels, pairing approval, security audit, and the chosen persistent service model after Chapter 06 bootstrap is complete.

Security baseline:

```text
gateway.mode local
gateway.bind loopback
token auth enabled
port 18789 unless deliberately changed
OpenClaw runs as the non-admin runtime user
local MLX-LM API binds to loopback only
remote access uses SSH tunnel
no public port forward
```

Important distinction:

```text
Chapter 05 proved that MLX-LM can run the Qwen model locally.
This chapter creates a local API endpoint that OpenClaw can connect to.
```

`mlx_lm.generate` is a local CLI inference command. It is not, by itself, an OpenClaw provider. For OpenClaw to use the local MLX-LM Qwen model, the model must be exposed through a supported provider path, such as an OpenAI-compatible local API endpoint.

## 1. Confirm Gateway Baseline

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

Verify:

```bash
openclaw config get gateway.mode
openclaw config get gateway.bind
```

Expected:

```text
local
loopback
```

## 2. Local Inference Provider Decision

Chapter 05 proves the local model can run through MLX-LM. OpenClaw still needs a supported provider path.

Do not confuse local model validation with provider integration. A model that runs through `mlx_lm.generate` is proven locally, but OpenClaw still needs a configured provider path to use it.

Decision path:

- If OpenClaw supports MLX-LM directly in the installed version, use that documented path.
- If not, use a supported local provider endpoint.
- For this guide, the primary local provider endpoint is `mlx_lm.server` on loopback.
- Ollama remains the practical fallback if MLX-LM server/provider integration is blocked.
- LM Studio is acceptable for GUI experimentation but is not the preferred headless dependency.

The intended local inference path in this chapter is:

```text
MLX-LM Qwen model
-> mlx_lm.server on 127.0.0.1:8080
-> OpenAI-compatible /v1 API
-> OpenClaw custom provider
-> OpenClaw gateway on 127.0.0.1:18789
-> SSH tunnel from operator workstation
```

Keep the local model server and OpenClaw gateway as separate services:

```text
MLX-LM server:       127.0.0.1:8080
OpenClaw gateway:    127.0.0.1:18789
```

Do not bind either service to `0.0.0.0` in this guide.

## 3. Carry Forward Chapter 05 Local LLM Facts

Before configuring provider integration, carry forward the Chapter 05 local LLM facts.

The easiest path is to run the provisioning script from this repository:

```bash
./chapter07-provision-local-llm.sh
```

Or fetch and run it from the guide repository:

```bash
REPO_RAW_BASE="https://raw.githubusercontent.com/YOUR-GITHUB-USER/mac-mini-init/main"
curl -fsSL "$REPO_RAW_BASE/chapter07-provision-local-llm.sh" | bash
```

Replace `YOUR-GITHUB-USER` with the GitHub account that hosts your fork of this guide.

The script provisions the safe local-only handoff:

- validates that the runtime user is non-admin
- activates `~/local-llm/.venv`
- fails if the venv is still Python 3.9 or LibreSSL
- records Python, MLX-LM, model ID, model SHA, and Hugging Face cache details in `~/.openclaw/local-llm-record.txt`
- creates `~/.openclaw/.env` only if missing, with comments and no fake local-LLM secrets
- enforces `700` on `~/.openclaw` and `600` on the record and `.env` files

These values prove what is installed locally. They are not provider secrets, and by themselves they do not configure OpenClaw to use the model.

Verify the record:

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

## 4. Create a Local MLX-LM API Endpoint

This is the key step that turns Chapter 05 local CLI inference into something OpenClaw can connect to.

`mlx_lm.server` exposes the local MLX model through an HTTP API similar to the OpenAI chat API. This local API endpoint is the bridge between OpenClaw and the MLX-LM model.

Security rule:

```text
Bind mlx_lm.server to 127.0.0.1 only.
Do not bind it to 0.0.0.0.
Do not expose it directly to the LAN or internet.
```

Start with a foreground test before creating any persistent service.

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

Leave this terminal open. The first start may take time because the model may need to load or download from the Hugging Face cache.

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

If the runtime user cannot run `lsof` with enough detail, use the admin user only for inspection:

```bash
su - adminuser
sudo lsof -nP -iTCP:8080 -sTCP:LISTEN
exit
```

Stop the foreground MLX-LM server with `Ctrl-C` after the test.

### Troubleshooting MLX-LM API Test

If `/v1/models` fails:

```bash
curl -v http://127.0.0.1:8080/v1/models
```

Check:

- the first SSH session is still running `mlx_lm.server`
- the venv is active
- the model ID is correct
- the server is bound to `127.0.0.1`
- port `8080` is not already in use

If the server starts but the Mac becomes sluggish:

- stop the server with `Ctrl-C`
- do not test larger models
- check memory pressure and swap:

```bash
vm_stat
top -l 1 | head -n 25
```

If the server cannot load the model:

```bash
cd ~/local-llm
source .venv/bin/activate

MODEL="mlx-community/Qwen3.5-9B-OptiQ-4bit"

python - <<'PY'
from huggingface_hub import model_info
model_id = "mlx-community/Qwen3.5-9B-OptiQ-4bit"
info = model_info(model_id)
print("model_id:", info.modelId)
print("sha:", info.sha)
print("tags:", ", ".join(info.tags or []))
PY
```

Then rerun:

```bash
mlx_lm.generate \
  --model "$MODEL" \
  --prompt "Reply with exactly: local model ok" \
  --max-tokens 20
```

Only continue when both `mlx_lm.generate` and `mlx_lm.server` work.

## 5. Make the Local MLX-LM API Endpoint Persistent

After the foreground server test works, create a user-level persistent service for the MLX-LM API endpoint.

This is separate from the OpenClaw gateway LaunchAgent.

Service split:

```text
ai.openclaw.mlx-lm       -> local model API endpoint on 127.0.0.1:8080
ai.openclaw.gateway      -> OpenClaw gateway on 127.0.0.1:18789
```

Both should run as the non-admin OpenClaw runtime user.

Create directories:

```bash
mkdir -p ~/.openclaw/bin
mkdir -p ~/.openclaw/logs
mkdir -p ~/Library/LaunchAgents
chmod 700 ~/.openclaw
```

Create a wrapper script:

```bash
cat > ~/.openclaw/bin/start-mlx-lm-server.sh <<'EOF'
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
  --port "$PORT"
EOF

chmod 700 ~/.openclaw/bin/start-mlx-lm-server.sh
```

Test the wrapper in the foreground:

```bash
~/.openclaw/bin/start-mlx-lm-server.sh
```

In a second SSH session:

```bash
curl -fsS http://127.0.0.1:8080/v1/models
```

Stop the wrapper with `Ctrl-C`.

Create a user LaunchAgent:

```bash
cat > ~/Library/LaunchAgents/ai.openclaw.mlx-lm.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>ai.openclaw.mlx-lm</string>

    <key>ProgramArguments</key>
    <array>
      <string>/bin/zsh</string>
      <string>-lc</string>
      <string>$HOME/.openclaw/bin/start-mlx-lm-server.sh</string>
    </array>

    <key>WorkingDirectory</key>
    <string>$HOME/local-llm</string>

    <key>EnvironmentVariables</key>
    <dict>
      <key>PATH</key>
      <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
      <key>PYTHONUNBUFFERED</key>
      <string>1</string>
    </dict>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>$HOME/.openclaw/logs/mlx-lm-server.log</string>

    <key>StandardErrorPath</key>
    <string>$HOME/.openclaw/logs/mlx-lm-server.err</string>
  </dict>
</plist>
EOF

chmod 600 ~/Library/LaunchAgents/ai.openclaw.mlx-lm.plist
```

macOS LaunchAgent plist files do not expand `$HOME` in all keys reliably. Replace `$HOME` with the actual home path before loading:

```bash
HOME_ESCAPED="$(printf '%s\n' "$HOME" | sed 's/[\/&]/\\&/g')"
sed -i '' "s|\$HOME|$HOME_ESCAPED|g" ~/Library/LaunchAgents/ai.openclaw.mlx-lm.plist
```

Validate the plist:

```bash
plutil -lint ~/Library/LaunchAgents/ai.openclaw.mlx-lm.plist
```

Load the LaunchAgent:

```bash
launchctl bootout "gui/$UID/ai.openclaw.mlx-lm" 2>/dev/null || true
launchctl bootstrap "gui/$UID" ~/Library/LaunchAgents/ai.openclaw.mlx-lm.plist
launchctl kickstart -k "gui/$UID/ai.openclaw.mlx-lm"
```

Verify:

```bash
launchctl print "gui/$UID/ai.openclaw.mlx-lm" | head -n 80
sleep 5
curl -fsS http://127.0.0.1:8080/v1/models
curl -fsS http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mlx-community/Qwen3.5-9B-OptiQ-4bit",
    "messages": [
      {"role": "user", "content": "Reply with exactly: persistent mlx ok"}
    ],
    "max_tokens": 20,
    "temperature": 0
  }'
```

Expected:

```text
persistent mlx ok
```

Check logs if needed:

```bash
tail -n 120 ~/.openclaw/logs/mlx-lm-server.log 2>/dev/null || true
tail -n 120 ~/.openclaw/logs/mlx-lm-server.err 2>/dev/null || true
```

### Important: LaunchAgent GUI-Domain Limitation

Like the OpenClaw gateway LaunchAgent, this user LaunchAgent may require the OpenClaw runtime user to have a valid GUI launchd domain.

If loading fails with a bootstrap/domain error, do not use `sudo` as a workaround.

Correct options:

- sign in to the macOS desktop as the OpenClaw runtime user and load the LaunchAgent again
- run the MLX-LM server manually over SSH during bootstrap
- defer true boot-time service behavior to an advanced LaunchDaemon/supervisor design

Do not run the MLX-LM server as root.

Do not run it as `adminuser`.

### Stop or Restart the MLX-LM LaunchAgent

Stop:

```bash
launchctl bootout "gui/$UID/ai.openclaw.mlx-lm"
```

Start:

```bash
launchctl bootstrap "gui/$UID" ~/Library/LaunchAgents/ai.openclaw.mlx-lm.plist
launchctl kickstart -k "gui/$UID/ai.openclaw.mlx-lm"
```

Restart:

```bash
launchctl kickstart -k "gui/$UID/ai.openclaw.mlx-lm"
```

Verify:

```bash
curl -fsS http://127.0.0.1:8080/v1/models
```

## 6. Store Provider Secrets

This section is for secrets such as cloud API keys or provider tokens.

For the local MLX-LM API endpoint in this chapter, there may be no real API secret. The local server is protected primarily by loopback binding and OS user boundaries.

Do not invent fake `.env` variables for MLX-LM unless your chosen provider path requires them.

Create and lock down the config directory:

```bash
mkdir -p ~/.openclaw
chmod 700 ~/.openclaw
umask 077
nano ~/.openclaw/.env
```

Example for cloud providers only:

```text
OPENAI_API_KEY=replace-me
ANTHROPIC_API_KEY=replace-me
```

Then:

```bash
chmod 600 ~/.openclaw/.env
```

Do not put API keys in this repository.

`700` on a directory and `600` on a secret file are different:

- `700` on a directory lets only the owner enter/list/write the directory.
- `600` on a secret file lets only the owner read/write the file.

## 7. Configure OpenClaw to Use the Local MLX-LM API Endpoint

This section connects OpenClaw to the local MLX-LM API endpoint.

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

Add or merge a custom OpenAI-compatible provider.

Use this as the intended provider structure, but merge carefully with the existing JSON rather than replacing unrelated config:

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

If your existing `openclaw.json` already has `models`, `providers`, or `agents.defaults`, merge the keys instead of replacing the file.

If the installed OpenClaw version expects a different provider schema, use the current OpenClaw provider documentation and record the difference in the install record.

Validate JSON syntax:

```bash
python3 -m json.tool ~/.openclaw/openclaw.json >/dev/null && echo "openclaw.json is valid JSON"
```

Check model visibility:

```bash
openclaw models status
openclaw doctor
```

If your installed OpenClaw version also supports a model-listing command, use it here to confirm the configured MLX provider and Qwen model are visible.

Restart the OpenClaw gateway:

```bash
openclaw gateway restart
sleep 3
openclaw gateway status
openclaw doctor
```

If OpenClaw does not list the MLX provider, check:

```bash
cat ~/.openclaw/openclaw.json
```

Common problems:

- invalid JSON
- provider added under the wrong key
- `baseUrl` missing `/v1`
- MLX-LM server not running
- using the CLI model test but forgetting to start `mlx_lm.server`
- model ID mismatch between `mlx_lm.server`, `/v1/models`, and OpenClaw config
- using an OpenClaw version whose custom provider schema differs from this guide

## 8. Manual OpenClaw Gateway Test

Before relying on a persistent OpenClaw gateway service, run or verify the gateway.

If no LaunchAgent is installed yet, start the gateway in the foreground:

```bash
openclaw gateway --port 18789
```

In a second SSH session:

```bash
openclaw gateway status
openclaw status
```

Stop the foreground gateway with `Ctrl-C`.

If the LaunchAgent is already installed:

```bash
openclaw gateway restart
sleep 3
openclaw gateway status
```

Expected:

```text
Gateway binds to 127.0.0.1:18789
Connectivity probe: ok
Runtime: running
```

## 9. SSH Tunnel Test

From the client machine:

```bash
ssh -N -L 18789:127.0.0.1:18789 openclaw@<mac-mini-ip>
```

Then from the client:

```text
http://127.0.0.1:18789
```

Or:

```bash
curl -fsS http://127.0.0.1:18789 >/dev/null && echo "gateway reachable through tunnel"
```

An SSH tunnel keeps the OpenClaw gateway bound locally on the Mac mini while still allowing remote administration from the workstation.

Do not bind OpenClaw to `0.0.0.0` in this guide.

The MLX-LM API endpoint should normally remain accessible only from the Mac itself:

```text
http://127.0.0.1:8080
```

Do not create a direct SSH tunnel to the MLX-LM server unless you are deliberately debugging the provider endpoint.

## 10. Device Pairing and Scope Approval

If a client reports:

```text
gateway connect failed: GatewayClientRequestError: scope upgrade pending approval
requested scopes [operator.pairing]
approved scopes [operator.read]
```

This is not a gateway startup failure. The gateway can be healthy while a device/scope request is pending.

List requests with a plain command. Do not copy the box-drawing characters from `doctor` output.

```bash
openclaw devices list
```

If you accidentally paste output formatting, the shell may try to run a command named `│`:

```text
error: unknown command '│'
zsh: command not found: │
```

Re-type the command manually:

```bash
openclaw devices list
```

What to inspect:

- `Request`: the current approval request ID. Retry operations may create a new request ID.
- `Device`: the requesting device or device fingerprint.
- `Requested`: the roles/scopes the requester wants.
- `Approved`: the roles/scopes it already has.
- `IP`: the source IP if OpenClaw reports one.
- `Age`: whether this appeared exactly when you ran `doctor`, `devices list`, or another local command.

If `doctor` reports one request ID and `openclaw devices list` shows a different one, use the latest request ID from `openclaw devices list`.

For a local-only setup, the most likely benign case is a local OpenClaw CLI or local agent requesting more scopes than it currently has. For example, a local fallback may show a paired device such as `gateway:doctor.memory.status` with only `operator.read`, while a pending request asks for pairing/admin/write scopes.

Do not approve based only on "it is local." Approve only if all of these are true:

- You just ran a command that would reasonably need that scope, such as `openclaw devices list`.
- The gateway is still bound to loopback.
- There is no public router port forward to OpenClaw.
- The request age matches your action.
- The requested scopes make sense for what you are trying to do.

Check the gateway bind:

```bash
openclaw config get gateway.bind
sudo lsof -nP -iTCP:18789 -sTCP:LISTEN
```

Expected:

```text
loopback
OpenClaw listens on 127.0.0.1:18789 or another loopback address
```

If the runtime user cannot run `sudo`, use the admin account only for the `lsof` check:

```bash
su - adminuser
sudo lsof -nP -iTCP:18789 -sTCP:LISTEN
exit
```

Check active local connections while reproducing the request:

```bash
lsof -nP -iTCP:18789
```

Loopback connections such as `127.0.0.1` suggest local activity. A LAN address suggests another host or an SSH tunnel endpoint. An empty `IP` column in `openclaw devices list` is not proof by itself; use timing, gateway bind, logs, and active connections together.

Check recent gateway logs if available:

```bash
tail -n 120 ~/.openclaw/logs/gateway.log 2>/dev/null || true
log show --predicate 'process CONTAINS "openclaw"' --last 30m 2>/dev/null || true
```

Approve only if expected and trusted:

```bash
openclaw devices approve <request-id>
```

Reject if unknown:

```bash
openclaw devices reject <request-id>
```

Re-run `openclaw devices list` immediately before approval because retrying clients may create a new request ID.

## 11. macOS LaunchAgent Limitation over SSH/Headless

`openclaw gateway install` installs a user LaunchAgent.

User LaunchAgents normally require the target macOS user's GUI launchd domain to exist. On a headless Mac over SSH, `launchctl bootstrap` may fail with error 125.

The forced install may require the OpenClaw runtime user to have an active macOS GUI launchd domain:

```bash
openclaw gateway install --force
```

Run that as the OpenClaw runtime user, not with `sudo` and not as the admin account. If the GUI domain is missing, sign in to the macOS desktop as the OpenClaw runtime user and rerun the command from that user's session.

This same general limitation may also apply to the custom user LaunchAgent for `ai.openclaw.mlx-lm`.

If a persistent gateway or model endpoint must start before GUI login, that is a different design: a custom LaunchDaemon or another supervised service pattern. OpenClaw says this is not shipped, so keep it as an advanced note, not the main path.

## 12. Persistence Options

Option A: User LaunchAgents after GUI login.

This means:

```text
ai.openclaw.mlx-lm starts the local model API endpoint
ai.openclaw.gateway starts the OpenClaw gateway
```

Pros:

- Matches the user-level service model.
- Runs as the non-admin OpenClaw runtime user.
- Keeps files and runtime state under the correct user.
- Lower privilege than system LaunchDaemons.
- Works well after the runtime user has a valid GUI launchd domain.

Cons:

- May require the runtime user to have an active macOS GUI login session.
- May not start after reboot until that user logs in.
- Less ideal for a fully headless appliance-style host.

Option B: Custom LaunchDaemon or external supervisor.

Pros:

- Better fit for true headless boot-time service.
- Can start before GUI login.
- More appliance-like.

Cons:

- Not shipped by OpenClaw according to observed behavior.
- Requires custom design, testing, logging, and security review.
- Higher risk of running with wrong privileges.
- Easy to accidentally run OpenClaw or MLX-LM as root/admin if implemented poorly.
- Should not be part of the initial safe baseline.

Least-regret recommendation:

```text
Use foreground services during bootstrap.
Use user LaunchAgents only after confirming the runtime user and, if required, signing into the macOS desktop as that user.
Defer custom LaunchDaemon patterns to an advanced appendix.
```

## 13. Install the OpenClaw User LaunchAgent

Only do this after manual gateway startup, MLX-LM endpoint testing, tunnel testing, and security review are clean.

Run as the OpenClaw runtime user:

```bash
openclaw gateway install
openclaw gateway status
```

If the LaunchAgent failed earlier and you have a valid GUI login session as the runtime user:

```bash
openclaw gateway install --force
openclaw gateway status
```

Do not use `sudo`. Do not run this as `adminuser`.

## 14. Channel Setup

Configure only the channels you intend to use.

Baseline posture:

- Keep gateway bind on loopback.
- Use token auth.
- Prefer pairing or allowlist behavior where applicable.
- Avoid broad channel exposure during first install.
- Do not enable WhatsApp/pairing/OAuth-style channels until the credential storage and channel security implications are understood.

## 15. Skill and Plugin Allowlist Posture

Treat plugins and skills as part of the local attack surface.

- Start with the minimum set required for installation, doctor, gateway, and intended channels.
- Review plugin purpose and permissions before enabling more.
- Missing skill requirements are normal on a minimal secure install.
- Prefer a small, intentional, allowlisted skill set.

## 16. Security Audit

Run:

```bash
openclaw security audit --deep
```

Review findings before enabling more channels, plugins, or background gateway operation.

`No channel security warnings detected` from doctor is not the same as a full security audit.

## 17. Conservative Firewall Verification

Check:

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode
sudo lsof -nP -iTCP -sTCP:LISTEN
```

If the runtime user cannot run `sudo`:

```bash
su - adminuser
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode
sudo lsof -nP -iTCP -sTCP:LISTEN
exit
```

Expected:

```text
ssh listens on port 22 for LAN administration.
MLX-LM listens on 127.0.0.1:8080 if persistent local inference is enabled.
OpenClaw listens on 127.0.0.1:18789 or another loopback address.
No public router port forward points to OpenClaw.
No public router port forward points to MLX-LM.
```

## 18. Reboot Verification

Reboot from the admin account if the OpenClaw runtime user cannot:

```bash
su - adminuser
sudo shutdown -r now
```

Reconnect over SSH after the Mac mini returns:

```bash
ssh openclaw@<mac-mini-ip>
```

Verify MLX-LM endpoint:

```bash
curl -fsS http://127.0.0.1:8080/v1/models
```

Verify OpenClaw gateway:

```bash
openclaw gateway status
openclaw doctor
openclaw logs --follow
```

Document whether:

```text
MLX-LM starts automatically
OpenClaw gateway starts automatically
either service starts only after GUI login
either service requires manual foreground startup
```

## 19. Update Procedure

Run updates as the OpenClaw runtime user.

Update OpenClaw:

```bash
openclaw update --dry-run
openclaw update
openclaw doctor
openclaw gateway restart
openclaw health
```

Update MLX-LM runtime only deliberately:

```bash
cd ~/local-llm
source .venv/bin/activate
python -m pip list --outdated
```

Do not blindly update MLX-LM while the gateway/provider is working. If you update MLX-LM, retest:

```bash
python -m pip install --upgrade mlx-lm
mlx_lm.generate --help | head -n 20
curl -fsS http://127.0.0.1:8080/v1/models
openclaw models status
openclaw doctor
```

If the update fails because the installation path is not writable, confirm OpenClaw was not accidentally installed as the admin user.

## 20. Install and Config Record

Record:

```text
OpenClaw runtime user:
Admin user:
Install method:
Install prefix:
OpenClaw version:
Node version:
Local LLM runtime:
Local model:
Local LLM record path:
Local LLM provision script:
MLX-LM API endpoint:
MLX-LM LaunchAgent:
Provider path:
Gateway port:
Gateway bind:
Gateway auth:
Provider secrets location:
SSH tunnel command:
Persistent service model:
OpenClaw LaunchAgent installed:
OpenClaw LaunchAgent requires GUI login:
MLX-LM LaunchAgent installed:
MLX-LM LaunchAgent requires GUI login:
Admin user used for:
```

## End-of-Chapter Check

- [ ] Provider path is selected deliberately.
- [ ] `chapter07-provision-local-llm.sh` was run if using the Chapter 05 local MLX-LM baseline.
- [ ] Chapter 05 local LLM handoff was recorded in `~/.openclaw/local-llm-record.txt`.
- [ ] Local MLX-LM API endpoint was tested in foreground.
- [ ] `mlx_lm.server` binds only to `127.0.0.1`.
- [ ] `http://127.0.0.1:8080/v1/models` responds.
- [ ] `http://127.0.0.1:8080/v1/chat/completions` responds.
- [ ] MLX-LM persistent service decision was made deliberately.
- [ ] If using `ai.openclaw.mlx-lm`, it was installed as the runtime user, not admin/root.
- [ ] Provider secrets are stored outside the repository.
- [ ] `~/.openclaw/.env` is mode `600`.
- [ ] OpenClaw custom provider points to `http://127.0.0.1:8080/v1`.
- [ ] OpenClaw model configuration uses the intended Qwen model ID.
- [ ] OpenClaw gateway starts manually or through the selected LaunchAgent model.
- [ ] OpenClaw gateway binds only to loopback.
- [ ] OpenClaw gateway is reachable through SSH tunnel.
- [ ] Device pairing and scope approvals are understood.
- [ ] `openclaw security audit --deep` was run and reviewed.
- [ ] Channel configuration is minimal and explicitly allowed.
- [ ] Skills/plugins are minimal and reviewed.
- [ ] Persistent gateway service model was selected deliberately.
- [ ] If using OpenClaw LaunchAgent, it was installed as the runtime user, not admin.
- [ ] If a LaunchAgent failed due to missing GUI session, this was documented and not bypassed with sudo.
- [ ] No OpenClaw gateway is exposed on `0.0.0.0`.
- [ ] No MLX-LM server is exposed on `0.0.0.0`.
- [ ] No public router port forward points to OpenClaw.
- [ ] No public router port forward points to MLX-LM.
- [ ] Reboot behavior is tested and documented.

## References

- [MLX-LM HTTP model server](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/SERVER.md)
- [OpenClaw model providers](https://github.com/openclaw/openclaw/blob/main/docs/concepts/model-providers.md)

---

Previous: [Chapter 06 - Install and Bootstrap OpenClaw](chapter06.md)
Next: [Chapter 08 - Home Network Access](chapter08.md)
[Back to main guide](README.md)
