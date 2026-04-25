[Back to main guide](README.md)

# Chapter 05 - Bootstrap OpenClaw Install and Doctor

This chapter is SSH-safe. It should not require keyboard/mouse/monitor unless an unexpected macOS system prompt appears.

Chapter 05 assumes Chapter 04 is complete. It installs OpenClaw as the non-admin runtime user, repairs first-run `openclaw doctor` findings, sets the local/loopback/token baseline, and verifies local runtime state.

This chapter stops before detailed provider secrets and channel setup. Persistent service behavior is introduced here only far enough to explain the first-run doctor prompts; Chapter 06 owns the long-term gateway service model.

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
```

Confirm before installing:

```bash
whoami
id -Gn
xcode-select -p
git --version
git config --global --get-regexp '^url\..*insteadOf'
```

Expected:

```text
whoami: openclaw or your chosen runtime user
id -Gn: does not include admin
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
```

First-run `doctor` may ask several questions. Answer based on this table.

| Doctor prompt or finding | Recommended answer | Why |
| --- | --- | --- |
| Bundled plugin runtime deps are missing | Yes / install them | Normal for first run; needed by bundled plugin runtimes. |
| `This install is not a git checkout` | No action | Normal for installer/npm/package-manager installs. |
| `gateway.mode is unset` | Set `gateway.mode local` | Gateway startup is blocked until mode is explicit. |
| `Gateway auth is off or missing a token` | Yes, generate token | Token auth is recommended even on loopback. |
| `Tighten permissions on ~/.openclaw to 700?` | Yes, if `whoami` is the runtime user | Keeps config, tokens, logs, sessions, and secrets owner-only. |
| `Create Session store dir at ~/.openclaw/agents/main/sessions?` | Yes | Normal local runtime state for the main agent. |
| OAuth dir missing | No action unless using WhatsApp/pairing channel | Informational when no channel needing OAuth is active. |
| Skills missing requirements | Do not install everything blindly | Minimal secure installs should keep skills intentional. |
| Plugins disabled | Usually no action | Disabled plugins are not automatically a problem; `Errors: 0` is the first-pass signal. |
| Enable zsh completion | Yes only if useful | Convenience only; does not affect gateway security. |
| Install gateway service now | Prefer not yet, unless GUI logged in as runtime user | See the LaunchAgent warning below. |

## 5. Gateway Mode, Bind, and Token

For this Mac mini guide, the baseline is:

```text
gateway.mode: local
gateway.bind: loopback
gateway.auth: token enabled
```

Set and verify:

```bash
openclaw config set gateway.mode local
openclaw config set gateway.bind loopback
openclaw config get gateway.mode
openclaw config get gateway.bind
```

Expected:

```text
local
loopback
```

When prompted:

```text
Generate and configure a gateway token now?
```

Answer **Yes** for the standard Mac mini setup. Token auth protects against accidental future LAN exposure, local browser/UI risks, tunnels, and local process misuse. Do not choose **No** unless intentionally managing gateway auth through another documented mechanism.

## 6. Permissions and Session Store

When prompted:

```text
Tighten permissions on ~/.openclaw to 700?
```

Answer **Yes** if `whoami` is the intended non-admin runtime user.

When prompted:

```text
Create Session store dir at ~/.openclaw/agents/main/sessions?
```

Answer **Yes** for the normal single-operator setup.

Verify:

```bash
whoami
id -Gn
ls -ld ~/.openclaw
stat -f "%Su %Sp %N" ~/.openclaw
ls -ld ~/.openclaw/agents/main/sessions
stat -f "%Su %Sp %N" ~/.openclaw/agents/main/sessions
```

Expected:

```text
owner is the OpenClaw runtime user
~/.openclaw permissions are owner-only, typically drwx------
session store path is under the runtime user's ~/.openclaw directory
session store is not group/world-writable
```

`700` on a directory means only the owner can enter, list, read, or write under it.

The session store is local OpenClaw runtime/session state for the main agent. It is not repository content and should not be committed to Git.

## 7. Update Message

If doctor reports:

```text
This install is not a git checkout.
Run `openclaw update` to update via your package manager (npm/pnpm), then rerun doctor.
```

Treat that as normal for installer/npm/package-manager installs. It is not an error.

Later updates should use:

```bash
openclaw update
openclaw doctor
```

Do not switch to git/source update procedures unless this is actually a source checkout.

## 8. Security, Skills, and Plugins

Doctor may report:

```text
No channel security warnings detected.
Run: openclaw security audit --deep
```

This is a basic channel-security signal only. It does not mean the whole host is secure. The deeper audit is covered in Chapter 06.

Doctor may also report skills and plugin counts, such as:

```text
Eligible: 6
Missing requirements: 46
Blocked by allowlist: 0

Loaded: 59
Imported: 1
Disabled: 43
Errors: 0
```

Missing skill requirements are normal on a minimal secure install. Disabled plugins are not automatically a problem. `Errors: 0` is the important first-pass plugin signal.

> **Minimal Skill and Plugin Posture**
>
> A high number of missing skill requirements is acceptable during first install. Do not add broad credentials, extra runtimes, channels, or third-party dependencies just to make all skills eligible.
>
> Treat plugins and skills as part of the local attack surface. Prefer no errors and a small intentional feature set over maximum enabled functionality.

## 9. zsh Completion

When prompted:

```text
Enable zsh shell completion for openclaw?
```

Answer **Yes** if the runtime user uses zsh, wants OpenClaw tab completion over SSH, and it is acceptable for OpenClaw to modify the runtime user's shell startup configuration.

Answer **No** if the user uses bash, wants no shell profile changes, or prefers to configure completion manually.

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

## 10. LaunchAgent GUI Login Requirement

> # IMPORTANT: GUI LOGIN IS REQUIRED FOR DEFAULT LAUNCHAGENT INSTALL
>
> For the default macOS user LaunchAgent path, the `openclaw` runtime user must have a logged-in macOS GUI session.
>
> SSH alone may be enough to install and run `openclaw doctor`, but it may not be enough to bootstrap the user's LaunchAgent domain.
>
> If `openclaw gateway install` or `openclaw gateway install --force` fails with launchctl error 125 from SSH, this is a macOS LaunchAgent session issue, not an OpenClaw installation failure.
>
> Do not fix this by using `sudo`, root, or `adminuser`.
>
> Sign in to the macOS desktop as the OpenClaw runtime user, then run:
>
> ```bash
> openclaw gateway install --force
> ```

The successful result should look like:

```text
Installed LaunchAgent: /Users/openclaw/Library/LaunchAgents/ai.openclaw.gateway.plist
Logs: /Users/openclaw/.openclaw/logs/gateway.log
```

If you still see:

```text
launchctl bootstrap failed: Bootstrap failed: 125: Domain does not support specified action
```

confirm you are logged in to the macOS GUI as the runtime user, not just connected by SSH. Chapter 06 discusses persistent service choices in more detail.

## 11. Final Doctor Recheck

After first-run repairs and any successful LaunchAgent install, run doctor again:

```bash
openclaw doctor
```

Doctor may offer to restart the gateway service. Answer **Yes** if you intentionally installed the LaunchAgent and want the current config applied.

Then check:

```bash
openclaw config get gateway.mode
openclaw config get gateway.bind
openclaw gateway status
```

Expected baseline:

```text
gateway.mode: local
gateway.bind: loopback
gateway service status is understood
```

If doctor still reports `gateway.mode is unset`, set it explicitly and rerun doctor:

```bash
openclaw config set gateway.mode local
openclaw config set gateway.bind loopback
openclaw doctor
```

## End-of-Chapter Check

- [ ] OpenClaw is installed as the non-admin runtime user.
- [ ] `openclaw --version` works.
- [ ] First-run `openclaw doctor` completed.
- [ ] Gateway token prompt was answered Yes.
- [ ] `gateway.mode` is set to `local`.
- [ ] `gateway.bind` is set to `loopback`.
- [ ] `~/.openclaw` was tightened to `700`.
- [ ] `~/.openclaw/agents/main/sessions` was created under the runtime user.
- [ ] Missing OAuth dir was understood as informational when no WhatsApp/pairing channel is active.
- [ ] Skills with missing requirements were not blindly enabled.
- [ ] Plugin status was reviewed and `Errors: 0` was confirmed if shown.
- [ ] zsh completion was enabled only if useful for the runtime user.
- [ ] LaunchAgent install was attempted only from the runtime user, not with `sudo` or `adminuser`.
- [ ] If using the default LaunchAgent, the runtime user was logged in to the macOS GUI before forcing install.
- [ ] `openclaw doctor` was rerun after repairs and LaunchAgent changes.
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
