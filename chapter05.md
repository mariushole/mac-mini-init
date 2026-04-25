[Back to main guide](README.md)

# Chapter 05 - Bootstrap OpenClaw Install and Doctor

This chapter is SSH-safe. It should not require keyboard/mouse/monitor unless an unexpected macOS system prompt appears.

Chapter 05 assumes Chapter 04 is complete. It installs OpenClaw as the non-admin runtime user, repairs first-run `openclaw doctor` findings, sets the local/loopback/token baseline, and verifies local runtime state.

This chapter stops before detailed provider secrets, channel setup, and persistent service design. Those belong in Chapter 06.

Security baseline:

```text
standard non-admin runtime user
admin only for system-level tasks
OpenClaw files owned by the runtime user
gateway loopback-only
token auth enabled
remote access through SSH tunnel
conservative firewall
no public port forward
no LaunchAgent until doctor/manual gateway startup is clean
```

Confirm before installing:

```bash
whoami
id -Gn
xcode-select -p
git --version
git config --global --get-regexp '^url\..*insteadOf'
```

## 1. Choose the Install Method

OpenClaw's official docs list these relevant install paths:

| Method | Use when | Notes |
| --- | --- | --- |
| Local prefix installer | Recommended here | Installs OpenClaw and a local Node runtime under `~/.openclaw`; no root required. |
| Standard installer | Good for interactive personal Macs | Detects the OS, installs Node if needed, installs OpenClaw, and can run onboarding. May install Homebrew/Node globally on macOS. |
| npm global install | Good if you already manage Node yourself | Requires Node 24 recommended or Node 22.14+. |
| Source install | For development or pinned forks | Requires `pnpm` and a local checkout. |

For this secured Mac mini, use the local prefix installer first. It keeps OpenClaw files, config, secrets, and runtime state owned by the non-admin runtime user.

## 2. Install with the Local Prefix Installer

Stay logged in as the OpenClaw runtime user.

```bash
cd /tmp
curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install-cli.sh -o install-openclaw-cli.sh
chmod 700 install-openclaw-cli.sh
```

Optional inspection:

```bash
sed -n '1,220p' install-openclaw-cli.sh
```

Help/dry-run check if supported:

```bash
./install-openclaw-cli.sh --help
```

Install:

```bash
./install-openclaw-cli.sh --prefix "$HOME/.openclaw" --version latest
```

Optional onboarding:

```bash
./install-openclaw-cli.sh --prefix "$HOME/.openclaw" --version latest --onboard
```

## 3. Add OpenClaw to PATH

For zsh:

```bash
grep -q 'HOME/.openclaw/bin' ~/.zshrc 2>/dev/null || printf '\nexport PATH="$HOME/.openclaw/bin:$PATH"\n' >> ~/.zshrc
export PATH="$HOME/.openclaw/bin:$PATH"
```

For bash:

```bash
grep -q 'HOME/.openclaw/bin' ~/.bashrc 2>/dev/null || printf '\nexport PATH="$HOME/.openclaw/bin:$PATH"\n' >> ~/.bashrc
export PATH="$HOME/.openclaw/bin:$PATH"
```

Confirm:

```bash
command -v openclaw
openclaw --version
```

If not found:

```bash
echo "$PATH"
ls -la "$HOME/.openclaw/bin"
```

## 4. Run openclaw doctor

Run:

```bash
openclaw doctor
openclaw --version
```

Observed first-run behavior may look like this:

```text
OpenClaw 2026.4.23 (a979721)

Update:
This install is not a git checkout.
Run `openclaw update` to update via your package manager (npm/pnpm), then rerun doctor.

Gateway:
gateway.mode is unset; gateway start will be blocked.
Fix: run openclaw configure and set Gateway mode (local/remote).
Or set directly: openclaw config set gateway.mode local
Missing config: run openclaw setup first.

Gateway auth:
Gateway auth is off or missing a token.
Token auth is now the recommended default, including loopback.

Generate and configure a gateway token now?
Yes

Gateway token configured.

Tighten permissions on ~/.openclaw to 700?
Yes

Create Session store dir at ~/.openclaw/agents/main/sessions?
Yes

State integrity:
- State directory permissions are too open (~/.openclaw). Recommend chmod 700.
- OAuth dir not present (~/.openclaw/credentials). Skipping create because no WhatsApp/pairing channel config is active.
- CRITICAL: Session store dir missing (~/.openclaw/agents/main/sessions).

Doctor changes:
- Tightened permissions on ~/.openclaw to 700
- Created Session store dir: ~/.openclaw/agents/main/sessions

Security:
- No channel security warnings detected.
- Run: openclaw security audit --deep

Skills status:
Eligible: 6
Missing requirements: 46
Blocked by allowlist: 0

Plugins:
Loaded: 59
Imported: 1
Disabled: 43
Errors: 0

Enable zsh shell completion for openclaw?
Yes

Shell completion installed. Restart your shell or run: source ~/.zshrc

Gateway:
Gateway not running.

Gateway connection:
Gateway target: ws://127.0.0.1:18789
Source: local loopback
Config: /Users/openclaw/.openclaw/openclaw.json
Bind: loopback

Gateway:
Gateway service not installed.

Install gateway service now?
Yes

Gateway service runtime:
Node (recommended)

Gateway service install failed:
Error: launchctl bootstrap failed: Bootstrap failed: 125: Domain does not support specified action

LaunchAgent openclaw gateway install --force requires a logged-in macOS GUI session for this user (gui/502).
This usually means you are running from SSH/headless context or as the wrong user, including sudo.

Fix:
sign in to the macOS desktop as the target user and rerun `openclaw gateway install --force`.

Headless deployments should use a dedicated logged-in user session or a custom LaunchDaemon (not shipped).

Tip:
rerun `openclaw gateway install` after fixing the error.

Updated ~/.openclaw/openclaw.json
Doctor complete.
```

## 5. Update Message

`This install is not a git checkout` is normal for installer/npm/package-manager installs. It is not an error.

Later updates should use:

```bash
openclaw update
openclaw doctor
```

Do not switch to git/source update procedures unless this is actually a source checkout.

## 6. Gateway Mode and Bind

`gateway.mode is unset` blocks gateway startup.

For this Mac mini guide, the baseline is:

```text
gateway.mode: local
gateway.bind: loopback
gateway.auth: token enabled
```

Repair:

```bash
openclaw config set gateway.mode local
openclaw config set gateway.bind loopback
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

## 7. Gateway Auth Token

When prompted:

```text
Generate and configure a gateway token now?
```

Answer **Yes** for the standard Mac mini setup.

Token auth is recommended even on loopback. It protects against accidental future LAN exposure, local browser/UI risks, tunnels, and local process misuse. Do not choose **No** unless intentionally managing gateway auth through another documented mechanism.

## 8. Permissions Prompt

When prompted:

```text
Tighten permissions on ~/.openclaw to 700?
```

Answer **Yes** if `whoami` is the intended non-admin runtime user.

Verify:

```bash
whoami
id -Gn
ls -ld ~/.openclaw
stat -f "%Su %Sp %N" ~/.openclaw
```

Expected:

```text
owner is the OpenClaw runtime user
permissions are owner-only, typically drwx------
```

`700` on a directory means only the owner can enter, list, read, or write under it.

## 9. Session Store Prompt

When prompted:

```text
Create Session store dir at ~/.openclaw/agents/main/sessions?
```

Answer **Yes** for the normal single-operator setup.

This is local OpenClaw runtime/session state for the main agent. It should be created under the non-admin runtime user. It is not repository content and should not be committed to Git.

Verify:

```bash
ls -ld ~/.openclaw/agents
ls -ld ~/.openclaw/agents/main
ls -ld ~/.openclaw/agents/main/sessions
stat -f "%Su %Sp %N" ~/.openclaw/agents/main/sessions
```

Expected:

```text
owner is the OpenClaw runtime user
path is under the runtime user's ~/.openclaw directory
permissions are not group/world-writable
```

## 10. State Integrity Output

First-run state findings may include:

```text
State directory permissions are too open (~/.openclaw). Recommend chmod 700.
OAuth dir not present (~/.openclaw/credentials). Skipping create because no WhatsApp/pairing channel config is active.
CRITICAL: Session store dir missing (~/.openclaw/agents/main/sessions).
```

Interpretation:

- Permissions warning is fixed by accepting the `700` prompt.
- Missing OAuth dir is informational if no WhatsApp or pairing channel is configured.
- Missing session store is expected on first run and fixed by accepting session store creation.
- These findings are normal during first bootstrap, but should not remain unresolved after doctor repair.

Doctor repair confirmation:

```text
Doctor changes:
- Tightened permissions on ~/.openclaw to 700
- Created Session store dir: ~/.openclaw/agents/main/sessions
```

These actions should be under the runtime user, not the admin account.

## 11. Security Output

Doctor may report:

```text
No channel security warnings detected.
Run: openclaw security audit --deep
```

This is a basic channel-security signal only. It does not mean the whole host is secure.

Run the deeper audit before enabling more channels or persistent service:

```bash
openclaw security audit --deep
```

## 12. Skills and Plugins

Doctor may report:

```text
Eligible: 6
Missing requirements: 46
Blocked by allowlist: 0
```

Missing requirements are normal on a minimal secure install. Do not try to satisfy every skill requirement on day one. A hardened setup should prefer a small, intentional, allowlisted skill set.

> **Minimal Skill Posture**
>
> A high number of missing skill requirements is acceptable during first install. Do not add broad credentials, extra runtimes, channels, or third-party dependencies just to make all skills eligible.

Doctor may also report:

```text
Loaded: 59
Imported: 1
Disabled: 43
Errors: 0
```

Disabled plugins are not automatically a problem. `Errors: 0` is the important first-pass signal.

> **Plugin Posture**
>
> Treat plugins and skills as part of the local attack surface.
>
> Start with the minimum set required for installation, doctor, gateway, and intended channels.
>
> Review plugin purpose and permissions before enabling more.
>
> Prefer no errors over maximum enabled functionality.

## 13. zsh Completion

When prompted:

```text
Enable zsh shell completion for openclaw?
```

Answer **Yes** if:

- The runtime user uses zsh.
- The user wants OpenClaw tab completion over SSH.
- It is acceptable for OpenClaw to modify the runtime user's shell completion/startup configuration.

Answer **No** if:

- The user uses bash.
- The user wants no shell profile changes.
- The user prefers to configure completion manually.

Check:

```bash
echo "$SHELL"
dscl . -read "/Users/$(whoami)" UserShell
```

If enabled:

```bash
source ~/.zshrc
command -v openclaw
openclaw --version
```

Shell completion is convenience only and does not affect gateway security.

## 14. Gateway Service Failure over SSH/Headless

Persistent service installation is handled in Chapter 06. Chapter 05 only documents the observed failure mode.

```text
Gateway service install failed:
launchctl bootstrap failed: Bootstrap failed: 125: Domain does not support specified action

LaunchAgent openclaw gateway install --force requires a logged-in macOS GUI session for this user (gui/502).
This usually means you are running from SSH/headless context or as the wrong user, including sudo.
```

Interpretation:

- OpenClaw installed successfully.
- `doctor` completed.
- The failure is specifically the macOS LaunchAgent service install.
- This happens because LaunchAgent bootstrap targets the GUI domain for that user.
- A pure SSH/headless session may not have that GUI domain available.
- Running as `sudo` or as the admin user is the wrong fix.
- Do not install the gateway service as `adminuser` or another admin user.
- Do not rerun the whole OpenClaw installer as admin.

Immediate safe checks:

```bash
openclaw config get gateway.mode
openclaw config get gateway.bind
openclaw doctor
```

Manual foreground gateway test:

```bash
openclaw gateway --port 18789
```

In another SSH session:

```bash
openclaw gateway status
```

Stop the foreground gateway with `Ctrl-C`.

Manual foreground gateway is acceptable for bootstrap testing. Persistent gateway service setup is handled in Chapter 06.

## End-of-Chapter Check

- [ ] OpenClaw is installed as the non-admin runtime user.
- [ ] `openclaw --version` works.
- [ ] `openclaw doctor` completed.
- [ ] Gateway token prompt was answered Yes.
- [ ] `gateway.mode` is set to `local`.
- [ ] `gateway.bind` is set to `loopback`.
- [ ] `~/.openclaw` was tightened to `700`.
- [ ] `~/.openclaw/agents/main/sessions` was created under the runtime user.
- [ ] Missing OAuth dir was understood as informational when no WhatsApp/pairing channel is active.
- [ ] Skills with missing requirements were not blindly enabled.
- [ ] Plugin status was reviewed and `Errors: 0` was confirmed.
- [ ] zsh completion was enabled only if useful for the runtime user.
- [ ] Gateway service install failure over SSH/headless was understood as a LaunchAgent limitation, not a failed OpenClaw install.
- [ ] Persistent gateway service setup was deferred to Chapter 06.
- [ ] No OpenClaw files, config, sessions, or LaunchAgent were intentionally created under the admin account.

## References

- [OpenClaw install overview](https://docs.openclaw.ai/install)
- [OpenClaw installer internals](https://docs.openclaw.ai/install/installer)
- [OpenClaw Node.js requirements](https://docs.openclaw.ai/install/node)
- [OpenClaw gateway runbook](https://docs.openclaw.ai/gateway)
- [OpenClaw authentication](https://docs.openclaw.ai/gateway/authentication)
- [OpenClaw updating](https://docs.openclaw.ai/install/updating)

---

Previous: [Chapter 04 - Prepare SSH and Headless Operations](chapter04.md)
Next: [Chapter 06 - Configure OpenClaw Gateway, Providers, Channels, and Persistent Service](chapter06.md)
[Back to main guide](README.md)
