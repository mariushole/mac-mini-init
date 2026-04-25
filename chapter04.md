[Back to main guide](README.md)

# Chapter 04 - Prepare SSH and Headless Operations

This chapter prepares the Mac Mini for a clean OpenClaw install over SSH. It stops before installing OpenClaw.

The goal is to make sure the runtime user, admin escalation path, network, developer tools, Git, and GitHub dependency fetching are all clean before Chapter 05 starts.

Assumptions:

- Chapter 02 security bootstrap is complete.
- Chapter 03 SSH access works with your GitHub public key.
- You are connected over SSH.
- You have a standard non-admin runtime user, for example `openclaw`.
- You have a separate admin account, for example `adminuser`.

## 1. Confirm the SSH Session

Run:

```bash
whoami
id
hostname
pwd
tty
echo "$SSH_CONNECTION"
```

Expected:

```text
whoami: openclaw / your chosen runtime user
pwd: /Users/openclaw or that user's home directory
SSH_CONNECTION: not empty
```

Record:

```text
SSH user:
Runtime user:
Admin user:
Mac hostname:
Preparation date:
```

## 2. Confirm the Runtime User Is Non-Admin

The OpenClaw runtime user should be a standard user. OpenClaw files, config, secrets, and the LaunchAgent should belong to this user.

Check group membership:

```bash
id
groups
```

If the runtime user is in the `admin` group, stop and decide whether to create a cleaner standard user before continuing.

Recommended baseline:

```text
Runtime user: openclaw
Runtime user is admin: no
Admin user: adminuser
```

## 3. Use Admin Escalation Deliberately

Most commands in the next chapter should run as the non-admin runtime user.

Use the admin account only for system-level tasks:

- Installing Apple Xcode Command Line Tools.
- Installing system package managers or system packages.
- Changing firewall settings.
- Rebooting the Mac Mini.
- Checking system-level launchd or security state.

Pattern:

```bash
su - adminuser
# run admin-only command
exit
```

Example:

```bash
su - adminuser
# run admin-only command
exit
```

After leaving the admin shell, confirm you are back as the runtime user:

```bash
whoami
pwd
```

Do not run the OpenClaw installer from inside the admin shell.

## 4. Confirm Hostname, Shell, and Home Directory

Run:

```bash
scutil --get ComputerName
scutil --get LocalHostName
echo "$SHELL"
dscl . -read /Users/"$(whoami)" UserShell NFSHomeDirectory
pwd
```

Expected:

```text
ComputerName and LocalHostName match your setup notes.
UserShell is a normal shell such as /bin/zsh or /bin/bash.
NFSHomeDirectory points to /Users/<runtime-user>.
```

Fix account or hostname surprises before installing OpenClaw.

## 5. Confirm Network, Route, DNS, and Internet

Run:

```bash
ifconfig | awk '/^[a-z0-9]+:/{iface=$1} /inet / && $2!="127.0.0.1"{print iface, $2}'
route -n get default | grep interface
scutil --dns | sed -n '1,80p'
ping -c 3 github.com
curl -fsSL https://openclaw.ai >/dev/null && echo "openclaw.ai reachable"
curl -fsSL https://github.com >/dev/null && echo "github.com reachable"
```

If these fail, fix DNS, routing, or firewall rules before continuing. Do not debug OpenClaw installer failures on top of a broken network.

Record:

```text
Mac Mini IP:
Default interface:
DNS works:
GitHub reachable:
openclaw.ai reachable:
```

## 6. Verify Xcode Command Line Tools and Git

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

## 7. Install Xcode Command Line Tools over SSH

If Git or developer tools are missing, macOS may print:

```text
xcode-select: error: No developer tools were found and no install could be requested
possibly because there is no active GUI session
```

This means the Apple developer tools are missing and `xcode-select --install` cannot show the GUI prompt from the current headless SSH session.

First try the normal installer from the admin account:

```bash
su - adminuser
sudo xcode-select --install
```

If a GUI prompt appears on the Mac Mini, complete it there. If no GUI prompt is available, use the headless `softwareupdate` method from the same admin shell:

```bash
sudo touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

softwareupdate --list --all | sed -n '/Command Line Tools/,+3p'

CLT_LABEL="$(softwareupdate --list --all 2>/dev/null | awk -F': ' '/Label: Command Line Tools for Xcode/ {print $2}' | tail -1)"

echo "$CLT_LABEL"

sudo softwareupdate --install "$CLT_LABEL" --verbose

sudo rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

sudo xcode-select --switch /Library/Developer/CommandLineTools
```

Verify while still in the admin shell:

```bash
xcode-select -p
git --version
```

Expected:

```text
/Library/Developer/CommandLineTools
git version ...
```

Return to the OpenClaw runtime user:

```bash
exit
whoami
```

Expected:

```text
openclaw
```

## 8. Force Public GitHub Dependencies over HTTPS

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

## 9. What Not to Do Yet

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
- [ ] Xcode Command Line Tools are installed.
- [ ] Git works.
- [ ] GitHub public dependency fetch works over HTTPS.
- [ ] You are back in the non-admin runtime account.
- [ ] No OpenClaw LaunchAgent has been installed yet.

---

Previous: [Chapter 03 - SSH Remote Access](chapter03.md)
Next: [Chapter 05 - Install and Configure OpenClaw](chapter05.md)
[Back to main guide](README.md)
