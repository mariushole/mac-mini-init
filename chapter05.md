[Back to main guide](README.md)

# Chapter 05 - Install and Configure OpenClaw

This chapter installs and configures OpenClaw over SSH after the headless preparation in Chapter 04 is complete.

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

Assumptions:

- You are logged in as the non-admin OpenClaw runtime user.
- Xcode Command Line Tools and Git work.
- GitHub public dependency fetches work over HTTPS.
- You are not inside an admin shell.

Confirm before installing:

```bash
whoami
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

For this secured Mac Mini, use the local prefix installer first. It keeps the runtime owned by the OpenClaw user and avoids unnecessary admin rights.

## 2. Install with the Local Prefix Installer

Stay logged in as the OpenClaw runtime user.

Download the installer to a temporary file first:

```bash
cd /tmp
curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install-cli.sh -o install-openclaw-cli.sh
chmod 700 install-openclaw-cli.sh
```

Optional but recommended: inspect the script before running it.

```bash
sed -n '1,220p' install-openclaw-cli.sh
```

Show available installer options:

```bash
./install-openclaw-cli.sh --help
```

Install OpenClaw under the default prefix:

```bash
./install-openclaw-cli.sh --prefix "$HOME/.openclaw" --version latest
```

If you want onboarding to run immediately:

```bash
./install-openclaw-cli.sh --prefix "$HOME/.openclaw" --version latest --onboard
```

The local prefix installer is designed to place OpenClaw under `~/.openclaw`, install a local Node runtime, and write an `openclaw` wrapper under `~/.openclaw/bin`.

## 3. Add OpenClaw to PATH

Add the local OpenClaw bin directory to your shell startup file.

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

If `openclaw` is still not found:

```bash
echo "$PATH"
ls -la "$HOME/.openclaw/bin"
```

## 4. Run Initial Health Checks

Run:

```bash
openclaw doctor
openclaw --version
```

Fresh installs commonly report two things:

- Bundled plugin runtime dependencies are missing.
- Gateway config has not been initialized yet.

If `doctor` asks to install missing bundled plugin runtime deps, choose **Yes**. Those packages are runtime dependencies for bundled plugins such as Bedrock, browser, Microsoft TTS, and MCP support. Installing them is normal.

If `doctor` says:

```text
gateway.mode is unset; gateway start will be blocked.
Gateway auth is off or missing a token.
Generate and configure a gateway token now?
```

choose **Yes** for the token prompt.

What this means:

- `gateway.mode` tells OpenClaw this host is allowed to run a local gateway.
- OpenClaw refuses to guess `local` if the config exists but the mode is missing.
- The gateway token is the shared secret clients must present when talking to the gateway, including loopback setups.
- Token auth is recommended even when the gateway binds only to `127.0.0.1`.

## 5. Set the Gateway Baseline

For this Mac Mini guide, the right gateway baseline is:

```text
gateway.mode: local
gateway.bind: loopback
gateway.auth: token enabled
```

Repair it directly if onboarding did not create the config yet:

```bash
openclaw config set gateway.mode local
openclaw config set gateway.bind loopback
openclaw doctor --fix
```

Then verify:

```bash
openclaw config get gateway.mode
openclaw config get gateway.bind
openclaw doctor
```

Expected:

```text
gateway.mode: local
gateway.bind: loopback
doctor no longer blocks gateway startup on missing mode/auth
```

If the token prompt appears again, answer **Yes** again unless you are deliberately managing `gateway.auth.token` through a SecretRef or environment variable. Do not choose **No** on a normal home Mac Mini install.

## 6. Onboard OpenClaw

Run onboarding as the OpenClaw runtime user:

```bash
openclaw onboard --mode local
```

For a secured home-network baseline, choose settings that keep the gateway local:

```text
Gateway mode: local
Gateway bind: loopback / 127.0.0.1
Gateway port: 18789 unless you need a different local port
Gateway auth: token
Channels: configure only what you intend to use
DM policy: pairing or allowlist, not open
Workspace: ~/.openclaw/workspace
```

If onboarding asks to install the daemon or service, decline until manual gateway startup works later in this chapter. The LaunchAgent should be installed only after `doctor` is clean and the gateway starts manually.

If `openclaw onboard --mode local` is not supported by your installed version, run:

```bash
openclaw onboard
openclaw config set gateway.mode local
openclaw config set gateway.bind loopback
openclaw doctor --fix
```

## 7. Store Provider Secrets for the Daemon

For a long-lived gateway host, API keys are usually the most predictable model-provider setup.

Create the OpenClaw config directory if needed:

```bash
mkdir -p ~/.openclaw
chmod 700 ~/.openclaw
```

Store provider keys in `~/.openclaw/.env` so the daemon can read them:

```bash
umask 077
nano ~/.openclaw/.env
```

Example:

```text
OPENAI_API_KEY=replace-me
ANTHROPIC_API_KEY=replace-me
```

Then lock down permissions:

```bash
chmod 600 ~/.openclaw/.env
```

Do not put API keys in this repository.

Check model auth:

```bash
openclaw models status
openclaw doctor
```

## 8. Start the Gateway Manually First

Before installing the background service, start the gateway manually:

```bash
openclaw gateway --port 18789
```

In a second SSH session to the Mac Mini, check:

```bash
openclaw gateway status
openclaw status
```

If you need to stop the foreground gateway, press `Ctrl-C` in the first session.

Default bind mode is loopback, which is what you want at this stage. Do not bind OpenClaw to `0.0.0.0`.

## 9. Test from Your Client with an SSH Tunnel

From your client machine, open a tunnel:

```bash
ssh -N -L 18789:127.0.0.1:18789 openclaw@<mac-mini-ip>
```

Then on the client, open:

```text
http://127.0.0.1:18789
```

Or test with:

```bash
curl -fsS http://127.0.0.1:18789 >/dev/null && echo "gateway reachable through tunnel"
```

An SSH tunnel keeps the OpenClaw gateway bound locally on the Mac Mini while still letting you administer it from your workstation.

## 10. Install the Gateway LaunchAgent

Install the managed gateway only after manual startup and `doctor` are clean.

Run as the OpenClaw runtime user:

```bash
openclaw gateway install
openclaw gateway status
```

If onboarding already installed the daemon, use:

```bash
openclaw gateway status
openclaw gateway restart
```

Operational commands:

```bash
openclaw gateway status
openclaw gateway status --deep
openclaw gateway restart
openclaw gateway stop
openclaw logs --follow
openclaw doctor
```

OpenClaw's docs identify the default macOS LaunchAgent label as `ai.openclaw.gateway`.

## 11. Reboot and Verify

Reboot from the admin account if the OpenClaw runtime user cannot:

```bash
su - adminuser
sudo shutdown -r now
```

Reconnect over SSH after the Mac Mini returns:

```bash
ssh openclaw@<mac-mini-ip>
```

Verify:

```bash
openclaw gateway status
openclaw doctor
openclaw logs --follow
```

If the gateway did not start, check whether the LaunchAgent is installed under the OpenClaw runtime user's context and rerun:

```bash
openclaw gateway install
openclaw gateway restart
openclaw gateway status --deep
```

## 12. Keep the Firewall Conservative

At this stage, the OpenClaw gateway should be loopback-only. The macOS firewall does not need a new LAN allow rule for OpenClaw yet.

Confirm SSH is still the only intended remote entry point:

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

## 13. Alternative: Standard Installer

Use this only if you are comfortable with the installer managing system prerequisites:

```bash
curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install.sh -o /tmp/install-openclaw.sh
chmod 700 /tmp/install-openclaw.sh
/tmp/install-openclaw.sh --no-onboard
```

Then run:

```bash
openclaw onboard
openclaw gateway install
openclaw gateway status
```

The standard installer may install Homebrew if missing and install Node 24 if needed. If it asks for admin credentials and you are logged in as the non-admin OpenClaw runtime user, stop and decide whether you really want the global path. The local prefix installer is usually cleaner for this guide.

## 14. Alternative: npm Global Install

Use this only if you already manage Node yourself.

Check Node:

```bash
node -v
npm -v
```

OpenClaw currently recommends Node 24. Node 22.14+ is supported.

Install:

```bash
npm install -g openclaw@latest
openclaw onboard --install-daemon
```

If `openclaw` is not found afterward:

```bash
npm prefix -g
echo "$PATH"
export PATH="$(npm prefix -g)/bin:$PATH"
```

Add that PATH export to `~/.zshrc` or `~/.bashrc` if needed.

## 15. Update Procedure

Run updates as the OpenClaw runtime user:

```bash
openclaw update --dry-run
openclaw update
openclaw doctor
openclaw gateway restart
openclaw health
```

If the update fails because the installation path is not writable, confirm you did not accidentally install OpenClaw as the admin user.

## 16. Install Record

Record:

```text
OpenClaw user:
Install method: local prefix / standard installer / npm / source
Install prefix:
OpenClaw version:
Node version:
Gateway port:
Gateway bind:
LaunchAgent installed:
Provider secrets location:
SSH tunnel command:
Admin user used for:
```

## End-of-Chapter Check

- [ ] OpenClaw is installed as the non-admin runtime user.
- [ ] Admin shell use was limited to system-level tasks.
- [ ] `openclaw --version` works over SSH.
- [ ] `openclaw doctor` runs cleanly enough to start the gateway.
- [ ] Missing bundled plugin runtime dependencies were installed if prompted.
- [ ] `gateway.mode` is `local`.
- [ ] `gateway.bind` is `loopback`.
- [ ] Gateway token auth is enabled.
- [ ] Provider secrets are stored outside the repository.
- [ ] The gateway starts manually.
- [ ] The gateway is installed as a user LaunchAgent only after manual startup works.
- [ ] The gateway survives reboot.
- [ ] Gateway access is loopback-only or otherwise deliberately documented.
- [ ] Remote administration works through SSH or an SSH tunnel.

## References

- [OpenClaw install overview](https://docs.openclaw.ai/install)
- [OpenClaw installer internals](https://docs.openclaw.ai/install/installer)
- [OpenClaw Node.js requirements](https://docs.openclaw.ai/install/node)
- [OpenClaw gateway runbook](https://docs.openclaw.ai/gateway)
- [OpenClaw authentication](https://docs.openclaw.ai/gateway/authentication)
- [OpenClaw updating](https://docs.openclaw.ai/install/updating)

---

Previous: [Chapter 04 - Prepare SSH and Headless Operations](chapter04.md)
Next: [Chapter 06 - OpenClaw Operations](chapter06.md)
[Back to main guide](README.md)
