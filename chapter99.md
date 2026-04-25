[Back to main guide](README.md)

# Chapter 99 - Deferred Advanced Operations

This chapter is a parking lot for useful operational topics that should not interrupt the first local MLX-LM/OpenClaw setup path.

Use this chapter after the local path is working:

```text
Chapter 05: local model works
Chapter 06: OpenClaw is installed and doctor-repaired
Chapter 07: local MLX-LM API endpoint is available to OpenClaw
```

## Cloud Provider Secrets

Cloud API keys and provider tokens belong outside the repository.

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

Do not invent `.env` variables for MLX-LM unless OpenClaw's current provider docs require them.

## Device Pairing and Scope Approval

If a client reports:

```text
gateway connect failed: GatewayClientRequestError: scope upgrade pending approval
requested scopes [operator.pairing]
approved scopes [operator.read]
```

List requests with a plain command:

```bash
openclaw devices list
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

## Channels

Configure only the channels you intend to use.

Baseline posture:

- Keep gateway bind on loopback unless there is a deliberate LAN design.
- Use token auth.
- Prefer pairing or allowlist behavior where applicable.
- Avoid broad channel exposure during first install.
- Do not enable WhatsApp/pairing/OAuth-style channels until credential storage and channel security implications are understood.

## Home Network Access

Home network exposure is deferred until the local provider path and any channels are working safely.

Planned scope:

- Decide the local URL for OpenClaw.
- Configure local DNS or mDNS.
- Add firewall rules only for required ports.
- Consider TLS for local access.
- Avoid public exposure unless a later remote-access design is documented.

Do not expose the MLX-LM API endpoint directly to the LAN. It should remain bound to `127.0.0.1`.

## Full Security Audit

Run:

```bash
openclaw security audit --deep
```

Review findings before enabling more channels, plugins, or background gateway operation.

`No channel security warnings detected` from doctor is not the same as a full security audit.

## Conservative Firewall Verification

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

## OpenClaw Gateway LaunchAgent

Only install the OpenClaw user LaunchAgent after manual gateway startup, local provider endpoint testing, tunnel testing, and security review are clean.

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

## Reboot Verification

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
curl -fsS http://127.0.0.1:8080/v1/models
openclaw gateway status
openclaw doctor
```

Document whether:

```text
MLX-LM starts automatically
OpenClaw gateway starts automatically
either service starts only after GUI login
either service requires manual foreground startup
```

## Updates

Run OpenClaw updates as the OpenClaw runtime user:

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

Do not blindly update MLX-LM while the gateway/provider is working. If you update MLX-LM, retest the local provider path.

---

Previous: [Chapter 09 - Backup, Updates, and Recovery](chapter09.md)
[Back to main guide](README.md)
