[Back to main guide](README.md)

# Chapter 07 - Configure OpenClaw Gateway, Providers, Channels, Pairing, and Persistence

Most of this chapter is SSH-safe, but default macOS user LaunchAgent installation may require a GUI login session as the OpenClaw runtime user.

This chapter covers provider integration, manual gateway test, SSH tunnel access, channels, pairing approval, security audit, and the chosen persistent gateway model after Chapter 06 bootstrap is complete.

Security baseline:

```text
gateway.mode local
gateway.bind loopback
token auth enabled
port 18789 unless deliberately changed
OpenClaw runs as the non-admin runtime user
remote access uses SSH tunnel
no public port forward
```

## 1. Confirm Gateway Baseline

Run as the OpenClaw runtime user:

```bash
openclaw config get gateway.mode
openclaw config get gateway.bind
openclaw doctor
```

Expected:

```text
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

## 2. Local Inference Provider Decision

Chapter 05 proves the local model can run through MLX-LM. OpenClaw still needs a supported provider path.

Do not confuse local model validation with provider integration. A model that runs through `mlx_lm.generate` is proven locally, but OpenClaw still needs a configured provider path to use it.

Decision path:

- If OpenClaw supports MLX-LM directly in the installed version, use that documented path.
- If not, do not improvise. Use a supported local provider endpoint.
- Ollama is the practical fallback if an API server is required.
- LM Studio is acceptable for GUI experimentation but is not the preferred headless dependency.

Carry forward the Chapter 05 local LLM facts before provider setup. The easiest path is to run the provisioning script from this repository:

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

## 3. Store Provider Secrets

This section is for secrets such as cloud API keys or provider tokens.

If the only provider work completed so far is Chapter 05 MLX-LM local CLI inference, there may be no API secret to store yet. Do not invent `.env` variables for MLX-LM. Use `~/.openclaw/local-llm-record.txt` for the local runtime facts above, then configure the actual OpenClaw provider path according to the installed OpenClaw version's documentation.

For a local-only MLX-LM setup, Section 2 already creates the safe placeholder `.env` file. Only edit `.env` here if the provider path you choose actually needs secrets.

Create and lock down the config directory:

```bash
mkdir -p ~/.openclaw
chmod 700 ~/.openclaw
umask 077
nano ~/.openclaw/.env
```

Example:

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

Check model auth:

```bash
openclaw models status
openclaw doctor
```

## 4. Manual Gateway Test

Before installing a persistent service, run the gateway in the foreground:

```bash
openclaw gateway --port 18789
```

In a second SSH session:

```bash
openclaw gateway status
openclaw status
```

Stop the foreground gateway with `Ctrl-C`.

## 5. SSH Tunnel Test

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

## 6. Device Pairing and Scope Approval

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

## 7. macOS LaunchAgent Limitation over SSH/Headless

`openclaw gateway install` installs a user LaunchAgent.

User LaunchAgents normally require the target macOS user's GUI launchd domain to exist. On a headless Mac over SSH, `launchctl bootstrap` may fail with error 125.

The forced install may require the OpenClaw runtime user to have an active macOS GUI launchd domain:

```bash
openclaw gateway install --force
```

Run that as the OpenClaw runtime user, not with `sudo` and not as the admin account. If the GUI domain is missing, sign in to the macOS desktop as the OpenClaw runtime user and rerun the command from that user's session.

If a persistent gateway must start before GUI login, that is a different design: a custom LaunchDaemon or another supervised service pattern. OpenClaw says this is not shipped, so keep it as an advanced note, not the main path.

## 8. Persistence Options

Option A: User LaunchAgent after GUI login.

Pros:

- Matches OpenClaw's supported/default macOS service model.
- Runs as the non-admin OpenClaw runtime user.
- Keeps files and runtime state under the correct user.
- Lower privilege than a system LaunchDaemon.

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

- Not shipped by OpenClaw according to the observed error.
- Requires custom design, testing, logging, and security review.
- Higher risk of running with wrong privileges.
- Easy to accidentally run OpenClaw as root or admin if implemented poorly.
- Should not be part of the initial safe baseline.

Least-regret recommendation:

```text
Use manual foreground gateway during bootstrap. Use OpenClaw's user LaunchAgent only after confirming the runtime user and, if required, signing into the macOS desktop as that user. Defer custom LaunchDaemon patterns to an advanced appendix.
```

## 9. Install the User LaunchAgent

Only do this after manual gateway startup, tunnel testing, and security review are clean.

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

## 10. Channel Setup

Configure only the channels you intend to use.

Baseline posture:

- Keep gateway bind on loopback.
- Use token auth.
- Prefer pairing or allowlist behavior where applicable.
- Avoid broad channel exposure during first install.
- Do not enable WhatsApp/pairing/OAuth-style channels until the credential storage and channel security implications are understood.

## 11. Skill and Plugin Allowlist Posture

Treat plugins and skills as part of the local attack surface.

- Start with the minimum set required for installation, doctor, gateway, and intended channels.
- Review plugin purpose and permissions before enabling more.
- Missing skill requirements are normal on a minimal secure install.
- Prefer a small, intentional, allowlisted skill set.

## 12. Security Audit

Run:

```bash
openclaw security audit --deep
```

Review findings before enabling more channels, plugins, or background gateway operation.

`No channel security warnings detected` from doctor is not the same as a full security audit.

## 13. Conservative Firewall Verification

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
OpenClaw listens on 127.0.0.1:18789 or another loopback address.
No public router port forward points to OpenClaw.
```

## 14. Reboot Verification

Reboot from the admin account if the OpenClaw runtime user cannot:

```bash
su - adminuser
sudo shutdown -r now
```

Reconnect over SSH after the Mac mini returns:

```bash
ssh openclaw@<mac-mini-ip>
```

Verify:

```bash
openclaw gateway status
openclaw doctor
openclaw logs --follow
```

Document whether the gateway starts automatically, starts only after GUI login, or requires manual foreground startup.

## 15. Update Procedure

Run updates as the OpenClaw runtime user:

```bash
openclaw update --dry-run
openclaw update
openclaw doctor
openclaw gateway restart
openclaw health
```

If the update fails because the installation path is not writable, confirm OpenClaw was not accidentally installed as the admin user.

## 16. Install and Config Record

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
Provider path:
Gateway port:
Gateway bind:
Gateway auth:
Provider secrets location:
SSH tunnel command:
Persistent service model:
LaunchAgent installed:
LaunchAgent requires GUI login:
Admin user used for:
```

## End-of-Chapter Check

- [ ] Provider path is selected deliberately.
- [ ] `chapter07-provision-local-llm.sh` was run if using the Chapter 05 local MLX-LM baseline.
- [ ] Chapter 05 local LLM handoff was recorded in `~/.openclaw/local-llm-record.txt`.
- [ ] Provider secrets are stored outside the repository.
- [ ] `~/.openclaw/.env` is mode `600`.
- [ ] Gateway starts manually.
- [ ] Gateway binds only to loopback.
- [ ] Gateway is reachable through SSH tunnel.
- [ ] Device pairing and scope approvals are understood.
- [ ] `openclaw security audit --deep` was run and reviewed.
- [ ] Channel configuration is minimal and explicitly allowed.
- [ ] Skills/plugins are minimal and reviewed.
- [ ] Persistent gateway service model was selected deliberately.
- [ ] If using LaunchAgent, it was installed as the runtime user, not admin.
- [ ] If LaunchAgent failed due to missing GUI session, this was documented and not bypassed with sudo.
- [ ] No gateway is exposed on `0.0.0.0`.
- [ ] No public router port forward points to OpenClaw.
- [ ] Reboot behavior is tested and documented.

---

Previous: [Chapter 06 - Install and Bootstrap OpenClaw](chapter06.md)
Next: [Chapter 08 - Home Network Access](chapter08.md)
[Back to main guide](README.md)
