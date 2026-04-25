[Back to main guide](README.md)

# Chapter 06 - Configure OpenClaw Gateway, Providers, Channels, and Persistent Service

Most of this chapter is SSH-safe, but default macOS user LaunchAgent installation may require a GUI login session as the OpenClaw runtime user.

This chapter covers the detailed OpenClaw configuration after Chapter 05 bootstrap is complete: provider secrets, manual gateway test, SSH tunnel access, channels, security audit, and the chosen persistent gateway model.

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

## 2. Store Provider Secrets

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

## 3. Manual Gateway Test

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

## 4. SSH Tunnel Test

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

## 5. macOS LaunchAgent Limitation over SSH/Headless

`openclaw gateway install` installs a user LaunchAgent.

User LaunchAgents normally require the target macOS user's GUI launchd domain to exist. On a headless Mac over SSH, `launchctl bootstrap` may fail with error 125.

Observed fix from the error:

```bash
openclaw gateway install --force
```

Run that as the OpenClaw runtime user, not with `sudo` and not as the admin account. If the GUI domain is missing, sign in to the macOS desktop as the OpenClaw runtime user and rerun the command from that user's session.

If a persistent gateway must start before GUI login, that is a different design: a custom LaunchDaemon or another supervised service pattern. OpenClaw says this is not shipped, so keep it as an advanced note, not the main path.

## 6. Persistence Options

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

## 7. Install the User LaunchAgent

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

## 8. Channel Setup

Configure only the channels you intend to use.

Baseline posture:

- Keep gateway bind on loopback.
- Use token auth.
- Prefer pairing or allowlist behavior where applicable.
- Avoid broad channel exposure during first install.
- Do not enable WhatsApp/pairing/OAuth-style channels until the credential storage and channel security implications are understood.

## 9. Skill and Plugin Allowlist Posture

Treat plugins and skills as part of the local attack surface.

- Start with the minimum set required for installation, doctor, gateway, and intended channels.
- Review plugin purpose and permissions before enabling more.
- Missing skill requirements are normal on a minimal secure install.
- Prefer a small, intentional, allowlisted skill set.

## 10. Security Audit

Run:

```bash
openclaw security audit --deep
```

Review findings before enabling more channels, plugins, or background gateway operation.

`No channel security warnings detected` from doctor is not the same as a full security audit.

## 11. Conservative Firewall Verification

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

## 12. Reboot Verification

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

## 13. Update Procedure

Run updates as the OpenClaw runtime user:

```bash
openclaw update --dry-run
openclaw update
openclaw doctor
openclaw gateway restart
openclaw health
```

If the update fails because the installation path is not writable, confirm OpenClaw was not accidentally installed as the admin user.

## 14. Install and Config Record

Record:

```text
OpenClaw runtime user:
Admin user:
Install method:
Install prefix:
OpenClaw version:
Node version:
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

- [ ] Provider secrets are stored outside the repository.
- [ ] `~/.openclaw/.env` is mode `600`.
- [ ] Gateway starts manually.
- [ ] Gateway binds only to loopback.
- [ ] Gateway is reachable through SSH tunnel.
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

Previous: [Chapter 05 - Bootstrap OpenClaw Install and Doctor](chapter05.md)
Next: [Chapter 07 - Home Network Access](chapter07.md)
[Back to main guide](README.md)
