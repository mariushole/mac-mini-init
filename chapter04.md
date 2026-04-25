[Back to main guide](README.md)

# Chapter 04 - Install OpenClaw over SSH

This chapter installs OpenClaw on the Mac Mini from an SSH session.

Assumptions:

- Chapter 02 security bootstrap is complete.
- Chapter 03 SSH access works with your GitHub public key.
- You are logged in over SSH as the non-admin operating user, for example `openclaw`.
- The admin user still exists, but OpenClaw should not be installed or run from that admin account.

Use the admin account only when a command genuinely needs system privileges. If the current SSH user is not an administrator, switch to the admin account with:

```bash
su - adminuser
```

Replace `adminuser` with the short name of the admin account created during Mac setup. When the admin task is done, return to the OpenClaw user with:

```bash
exit
```

Do not install OpenClaw while still inside the admin shell. The OpenClaw files, config, secrets, and LaunchAgent should belong to the standard OpenClaw user.

## 1. Confirm Where You Are Logged In

Run:

```bash
whoami
id
hostname
pwd
```

Expected:

```text
whoami: openclaw / your chosen operating user
id: user is not in the admin group
pwd: /Users/openclaw or that user's home directory
```

Record:

```text
SSH user:
Admin user:
Mac hostname:
Install date:
```

## 2. Keep Admin Escalation Deliberate

Most OpenClaw commands should run as the OpenClaw user.

Use `su - adminuser` only for tasks like:

- Installing Apple command line tools if missing.
- Installing Homebrew or system packages if you choose the global installer path.
- Changing firewall settings.
- Checking system logs or launchd state that requires admin rights.

Pattern:

```bash
su - adminuser
# run the admin-only command
exit
```

Then confirm you are back as the OpenClaw user:

```bash
whoami
```

## 3. Confirm Network and DNS

From the SSH session:

```bash
scutil --get ComputerName
scutil --get LocalHostName
ifconfig | awk '/^[a-z0-9]+:/{iface=$1} /inet / && $2!="127.0.0.1"{print iface, $2}'
route -n get default | grep interface
curl -fsSL https://openclaw.ai >/dev/null && echo "openclaw.ai reachable"
```

If `curl` cannot reach the internet, fix DNS, routing, or firewall rules before continuing.

## 4. Choose the Install Method

OpenClaw's official docs currently list these relevant install paths:

| Method | Use when | Notes |
| --- | --- | --- |
| Local prefix installer | Recommended here | Installs OpenClaw and a local Node runtime under `~/.openclaw`; no root required. |
| Standard installer | Good for interactive personal Macs | Detects the OS, installs Node if needed, installs OpenClaw, and can run onboarding. May install Homebrew/Node globally on macOS. |
| npm global install | Good if you already manage Node yourself | Requires Node 24 recommended or Node 22.14+. |
| Source install | For development or pinned forks | Requires `pnpm` and a local checkout. |

For this secured Mac Mini, use the local prefix installer first. It keeps the runtime owned by the OpenClaw user and avoids unnecessary admin rights.

## 5. Install with the Local Prefix Installer

Stay logged in as the OpenClaw user.

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

Run a dry run if supported by the installer version:

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

## 6. Add OpenClaw to PATH

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

## 7. Run Initial Health Checks

Run:

```bash
openclaw doctor
openclaw --version
```

If `doctor` reports missing config, continue with onboarding. If it reports PATH or Node issues, fix those before installing a background service.

## 8. Onboard OpenClaw

Run onboarding as the OpenClaw user:

```bash
openclaw onboard
```

For a secured home-network baseline, choose settings that keep the gateway local:

```text
Gateway bind: loopback / 127.0.0.1
Gateway port: 18789 unless you need a different local port
Gateway auth: enabled
Channels: configure only what you intend to use
DM policy: pairing or allowlist, not open
Workspace: ~/.openclaw/workspace
```

If onboarding asks to install the daemon or service, accept only if it will install for the current OpenClaw user. Do not install it as the admin user.

## 9. Store Provider Secrets for the Daemon

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

## 10. Start the Gateway Manually First

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

Default bind mode is loopback, which is what you want at this stage. Do not bind OpenClaw to `0.0.0.0` in this chapter.

## 11. Test from Your Client with an SSH Tunnel

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

## 12. Install the Gateway LaunchAgent

Once manual startup works, install the managed gateway for the OpenClaw user:

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

## 13. Reboot and Verify

Reboot from the admin account if the OpenClaw user cannot:

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

If the gateway did not start, check whether the LaunchAgent is installed under the OpenClaw user's context and rerun:

```bash
openclaw gateway install
openclaw gateway restart
openclaw gateway status --deep
```

## 14. Keep the Firewall Conservative

At this stage, the OpenClaw gateway should be loopback-only. That means the macOS firewall does not need a new LAN allow rule for OpenClaw yet.

Confirm SSH is still the only intended remote entry point:

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode
sudo lsof -nP -iTCP -sTCP:LISTEN
```

If the OpenClaw user cannot run `sudo`, switch to the admin user:

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

## 15. Alternative: Standard Installer

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

The standard installer may install Homebrew if missing and install Node 24 if needed. If it asks for admin credentials and you are logged in as the non-admin OpenClaw user, stop and decide whether you really want the global path. The local prefix installer is usually cleaner for this guide.

## 16. Alternative: npm Global Install

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

## 17. Update Procedure

Run updates as the OpenClaw user:

```bash
openclaw update --dry-run
openclaw update
openclaw doctor
openclaw gateway restart
openclaw health
```

If the update fails because the installation path is not writable, confirm you did not accidentally install OpenClaw as the admin user.

## 18. Install Record

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

- [ ] OpenClaw is installed as the non-admin operating user.
- [ ] Admin shell use was limited to system-level tasks.
- [ ] `openclaw --version` works over SSH.
- [ ] `openclaw doctor` runs.
- [ ] Provider secrets are stored outside the repository.
- [ ] The gateway starts manually.
- [ ] The gateway is installed as a user LaunchAgent.
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

Previous: [Chapter 03 - SSH Remote Access](chapter03.md)
Next: [Chapter 05 - OpenClaw Configuration and Channels](chapter05.md)
[Back to main guide](README.md)
