[Back to main guide](README.md)

# Chapter 04 - Prepare SSH and Headless Operations

This chapter prepares the Mac mini for a clean OpenClaw install over SSH. It stops before installing OpenClaw.

After this chapter is complete and SSH reconnect after reboot has been tested, the Mac mini may be moved to its permanent cabled/headless location.

Assumptions:

- Chapter 02 security bootstrap is complete.
- Chapter 03 SSH access works with your GitHub public key.
- You are connected over SSH.
- The OpenClaw runtime user is `openclaw` or another chosen non-admin user.
- The admin user is `adminuser` or another known admin account.

## 1. Confirm the SSH Session

Run:

```bash
whoami
id
id -Gn
dseditgroup -o checkmember -m "$(whoami)" admin
hostname
pwd
tty
echo "$SSH_CONNECTION"
```

Expected:

```text
whoami: openclaw or the chosen non-admin runtime user
id/id -Gn: user is not in the admin group
pwd: /Users/openclaw or that user's home directory
SSH_CONNECTION: not empty
```

If the runtime user is in the `admin` group, stop and decide whether to create a cleaner standard user before continuing.

Record:

```text
SSH user:
Runtime user:
Runtime user is admin?: no
Admin user:
Mac hostname:
Preparation date:
```

## 2. Use Admin Escalation Deliberately

Most OpenClaw-related work should run as the non-admin runtime user.

Use the admin account only for system-level tasks:

- Installing Apple Xcode Command Line Tools.
- Installing system package managers or packages.
- Changing firewall settings.
- Rebooting the Mac mini.
- Checking system-level launchd or security state.

Pattern:

```bash
su - adminuser
# run admin-only command
exit
```

Then verify return to the runtime user:

```bash
whoami
```

Do not run the OpenClaw installer from inside the admin shell.

## 3. Confirm Hostname, Shell, Home, Network, and DNS

Run:

```bash
scutil --get ComputerName
scutil --get LocalHostName
echo "$SHELL"
dscl . -read /Users/"$(whoami)" UserShell NFSHomeDirectory
ifconfig | awk '/^[a-z0-9]+:/{iface=$1} /inet / && $2!="127.0.0.1"{print iface, $2}'
route -n get default
curl -fsSL https://openclaw.ai >/dev/null && echo "openclaw.ai reachable"
```

If `curl` cannot reach the internet, fix DNS, routing, or firewall rules before continuing. Do not debug OpenClaw installer failures on top of a broken network.

Record:

```text
ComputerName:
LocalHostName:
Runtime shell:
Home directory:
Mac mini IP:
Default route:
openclaw.ai reachable:
```

## 4. Verify Xcode Command Line Tools and Git

Check:

```bash
xcode-select -p
git --version
```

Expected:

```text
/Library/Developer/CommandLineTools
git version ...
```

If both commands work, continue to the GitHub dependency rewrite section.

## 5. Install Xcode Command Line Tools over SSH

If Git or developer tools are missing, macOS may print:

```text
xcode-select: error: No developer tools were found and no install could be requested
possibly because there is no active GUI session
```

This means macOS developer tools are missing. `openclaw doctor` or npm/git dependency installation may trigger Git usage. `xcode-select --install` often needs a GUI prompt, so over SSH/headless use the `softwareupdate` method when the GUI prompt is unavailable.

First try the normal installer from the admin account:

```bash
su - adminuser
sudo xcode-select --install
```

If a GUI prompt appears on the Mac mini, complete it there. If no GUI prompt is available, use the headless method from the same admin shell:

```bash
sudo touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

softwareupdate --list --all | sed -n '/Command Line Tools/,+3p'

CLT_LABEL="$(softwareupdate --list --all 2>/dev/null | awk -F': ' '/Label: Command Line Tools for Xcode/ {print $2}' | tail -1)"

echo "$CLT_LABEL"

sudo softwareupdate --install "$CLT_LABEL" --verbose

sudo rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

sudo xcode-select --switch /Library/Developer/CommandLineTools
```

Verify:

```bash
xcode-select -p
git --version
```

Expected:

```text
/Library/Developer/CommandLineTools
git version ...
```

Return to the runtime user:

```bash
exit
whoami
```

Expected:

```text
openclaw
```

## 6. Force Public GitHub Dependencies over HTTPS

Some npm dependencies may reference public GitHub repositories through SSH URLs, for example:

```text
ssh://git@github.com/whiskeysockets/libsignal-node.git
```

Do not put a GitHub private key on the OpenClaw host just to fetch public dependencies. Configure Git for the runtime user to rewrite GitHub SSH URLs to HTTPS.

Run this as the runtime user, not the admin user:

```bash
git config --global url."https://github.com/".insteadOf ssh://git@github.com/
git config --global url."https://github.com/".insteadOf git@github.com:
git config --global --get-regexp '^url\..*insteadOf'
```

Test:

```bash
git ls-remote https://github.com/whiskeysockets/libsignal-node.git >/dev/null && echo "GitHub HTTPS dependency fetch works"
```

If this fails, fix GitHub HTTPS access before installing OpenClaw.

## 7. Permission Model Overview

The OpenClaw runtime directory should belong to the intended non-admin runtime user.

Baseline:

- `~/.openclaw` should belong to `openclaw` or the chosen runtime user.
- The runtime user should not be in the macOS `admin` group.
- OpenClaw should not be installed or run from the admin account.
- The secure baseline is owner-only access to the OpenClaw config/runtime directory.

Check:

```bash
whoami
id -Gn
ls -ld "$HOME"
ls -ld "$HOME/.openclaw" 2>/dev/null || echo "~/.openclaw does not exist yet"
```

If `~/.openclaw` already exists, verify ownership:

```bash
stat -f "%Su %Sp %N" "$HOME/.openclaw"
```

Expected:

```text
owner: the OpenClaw runtime user
permissions: owner-only or at least not group/world-readable
```

> **Permission Baseline: Why 700 Matters**
>
> `chmod 700 ~/.openclaw` means only the owning user can read, write, or enter the directory.
>
> This is desirable because the directory may contain OpenClaw config, gateway tokens, provider secrets, logs, runtime state, and `.env` files.
>
> It does not protect against the admin user, root, or malware already running as the same user.
>
> It is still the correct baseline for a single-operator Mac mini OpenClaw host.

Permission baseline pros:

- Prevents other local macOS users from reading OpenClaw config, tokens, logs, and runtime files.
- Supports the single-operator, least-privilege model.
- Reduces accidental exposure from loose default permissions.
- Aligns with storing provider secrets outside the repository.

Permission baseline cons:

- Other non-admin users cannot inspect or share the OpenClaw directory.
- Group-shared workflows will not work without deliberate design.
- Backup, sync, or indexing tools running as another user may not access the directory.
- It does not protect against the admin account, root, or compromise of the OpenClaw runtime user.
- If OpenClaw was installed as the wrong user, tightening permissions protects the wrong user's directory.

## 8. Session Store Model Overview

OpenClaw uses local session/runtime state for the main agent under:

```text
~/.openclaw/agents/main/sessions
```

This is normal OpenClaw local state. It should be created under the non-admin runtime user, not under the admin account. It is not repository content and should not be committed to Git.

Actual creation is handled in Chapter 06 during `openclaw doctor`.

## 9. What Not to Do Yet

- Do not install OpenClaw yet.
- Do not rerun the OpenClaw installer as the admin user.
- Do not install the OpenClaw LaunchAgent yet.
- Do not bind the OpenClaw gateway to `0.0.0.0`.
- Do not put GitHub private keys on this host unless explicitly needed.
- Do not proceed to long-lived gateway setup until the runtime account and prerequisites are clean.

## Ready for Chapter 05 Checklist

- [ ] SSH login works.
- [ ] Runtime user is confirmed.
- [ ] Runtime user is non-admin.
- [ ] Admin user exists and works for system-level tasks.
- [ ] Network, DNS, and internet access work.
- [ ] Xcode Command Line Tools are installed or have a documented headless install path.
- [ ] Git works.
- [ ] GitHub public dependency fetch works over HTTPS.
- [ ] The user is back in the non-admin runtime account.
- [ ] `~/.openclaw` permission model is understood.
- [ ] Session store location is understood.
- [ ] No OpenClaw LaunchAgent has been installed yet.
- [ ] No OpenClaw gateway has been bound to `0.0.0.0`.
- [ ] SSH reconnect after reboot has been tested.
- [ ] Mac mini is ready to move to permanent cabled/headless location.

After this chapter, the Mac mini may be moved to its permanent cabled/headless location, provided SSH reconnect after reboot has been tested.

---

Previous: [Chapter 03 - SSH Remote Access](chapter03.md)
Next: [Chapter 05 - Install Local LLM Runtime for Headless OpenClaw](chapter05.md)
[Back to main guide](README.md)
