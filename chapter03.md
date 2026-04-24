[Back to main guide](README.md)

# Chapter 03 - SSH Remote Access

This chapter enables and tests SSH for one local user.

Do this from the Mac Mini local console or GUI, not over SSH. Keep keyboard, display, and local admin access available until SSH works from a second machine and survives a reboot.

Apple documents that Remote Login enables SSH/SFTP and can be limited to "Only these users." On Apple silicon with macOS 26 or later, Apple says FileVault can be unlocked over SSH after restart if Remote Login is enabled and a network connection is available. Treat that as something to test locally, not something to assume.

## 1. Confirm the SSH User

Use the standard operating user created in Chapter 02. The examples use:

```bash
SSH_USER="openclaw"
```

Confirm the local short username:

```bash
dscl . list /Users | grep -v '^_'
```

Record:

```text
SSH user:
Is admin?: no
Purpose: OpenClaw remote administration
```

## 2. Install Public Keys from GitHub

Preferred pattern: fetch the public SSH keys already published on your GitHub account and install them for the local Mac user.

GitHub exposes public SSH keys at:

```bash
curl https://github.com/<username>.keys
```

Example:

```bash
curl https://github.com/torvalds.keys
```

This returns public keys only. It does not expose private keys. It works only if the GitHub user has uploaded SSH keys to GitHub.

From the Mac Mini, logged in as the local user you want to SSH into:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
curl -fsSL https://github.com/<your-github-username>.keys >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

If you are setting this up from an admin account for another local user:

```bash
SSH_USER="openclaw"
GITHUB_USER="<your-github-username>"

sudo mkdir -p /Users/$SSH_USER/.ssh
curl -fsSL https://github.com/$GITHUB_USER.keys | sudo tee -a /Users/$SSH_USER/.ssh/authorized_keys >/dev/null
sudo chown -R $SSH_USER:staff /Users/$SSH_USER/.ssh
sudo chmod 700 /Users/$SSH_USER/.ssh
sudo chmod 600 /Users/$SSH_USER/.ssh/authorized_keys
```

Optionally save a copy for review before installing:

```bash
curl -fsSL https://github.com/<your-github-username>.keys > github-<your-github-username>.keys
cat github-<your-github-username>.keys
```

Do not blindly install keys from a GitHub account you do not control.

Manual fallback: on your laptop or administration machine, create a dedicated key if you do not already have one:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/macmini_openclaw_ed25519
cat ~/.ssh/macmini_openclaw_ed25519.pub
```

Then paste the public key into the Mac user's `authorized_keys` file and set the same permissions shown above. Do not put private keys in this repository.

## 3. Enable Remote Login Only for That User

Use the GUI first, because it makes the access model visible:

```text
System Settings -> General -> Sharing -> Remote Login -> Info
Remote Login: On
Allow access for: Only these users
Add: openclaw / your chosen user
Allow full disk access for remote users: Off
```

Command-line equivalent:

```bash
SSH_USER="openclaw"

sudo dseditgroup -o create -q com.apple.access_ssh 2>/dev/null || true
sudo dseditgroup -o edit -a "$SSH_USER" -t user com.apple.access_ssh
sudo dseditgroup -o checkmember -m "$SSH_USER" com.apple.access_ssh

sudo systemsetup -setremotelogin on
sudo systemsetup -getremotelogin
```

Expected:

```text
Remote Login: On
```

## 4. Confirm SSH Is Listening Locally

Still on the Mac Mini local console:

```bash
nc -vz 127.0.0.1 22
```

Expected:

```text
Connection to 127.0.0.1 port 22 [tcp/ssh] succeeded
```

If localhost SSH fails, restart the SSH launch service:

```bash
sudo launchctl enable system/com.openssh.sshd
sudo launchctl kickstart -k system/com.openssh.sshd
nc -vz 127.0.0.1 22
```

Do not troubleshoot from a remote machine until localhost port 22 works on the Mac Mini itself.

## 5. Find the Mac Mini IP Address

Use the current address, not an old DHCP lease:

```bash
ifconfig | awk '/^[a-z0-9]+:/{iface=$1} /inet / && $2!="127.0.0.1"{print iface, $2}'
route -n get default | grep interface
```

You can also check common macOS interfaces:

```bash
ipconfig getifaddr en0
ipconfig getifaddr en1
```

Record:

```text
Mac Mini IP:
Default interface:
Router DHCP reservation created?: yes/no
```

## 6. Test from a Client Machine

From macOS or Linux:

```bash
ping <mac-mini-ip>
nc -vz <mac-mini-ip> 22
ssh <user>@<mac-mini-ip>
```

If you created a dedicated local key instead of relying on your default SSH agent:

```bash
ssh -i ~/.ssh/macmini_openclaw_ed25519 <user>@<mac-mini-ip>
```

On Windows PowerShell:

```powershell
Test-NetConnection <mac-mini-ip> -Port 22
ssh <user>@<mac-mini-ip>
```

Keep the local console session open while testing.

## 7. Harden SSH Server Config

Back up the SSH daemon config:

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d-%H%M%S)
```

Edit the config:

```bash
sudo nano /etc/ssh/sshd_config
```

Add or set these lines near the end:

```sshconfig
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
X11Forwarding no
AllowTcpForwarding no
PermitTunnel no
StrictModes yes
ClientAliveInterval 300
ClientAliveCountMax 2
LogLevel VERBOSE

AllowUsers openclaw
```

Replace `openclaw` with the real SSH username.

Restart SSH:

```bash
sudo launchctl kickstart -k system/com.openssh.sshd
```

Test again from a client machine before closing the local console.

## 8. If SSH Fails, Check the macOS Firewall

Temporarily disable the macOS application firewall only to isolate the problem:

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off
```

Retry SSH from the client.

If SSH works with the firewall off, re-enable the firewall safely:

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall off
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/libexec/sshd-keygen-wrapper
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /usr/libexec/sshd-keygen-wrapper
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
```

Important: **Block all incoming connections** must be off if you want SSH to work.

## 9. Restrict SSH to Trusted Local Networks with pf

The macOS application firewall is useful, but it is not the right tool for subnet-based SSH restrictions. Use `pf` to limit port 22.

For initial setup, you can allow SSH from RFC1918 private networks:

```text
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
```

Long term, narrow this to the actual management subnet, such as `192.168.1.0/24`. RFC1918 does not always mean trusted.

Create a `pf` anchor:

```bash
sudo tee /etc/pf.anchors/ssh-rfc1918 >/dev/null <<'EOF'
# Allow SSH only from RFC1918/private networks.
# Prefer replacing these broad ranges with your actual lab/home subnets if possible.

table <ssh_rfc1918> persist { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 }

pass in quick proto tcp from <ssh_rfc1918> to any port 22 keep state
block drop in quick proto tcp from any to any port 22
EOF
```

Back up `/etc/pf.conf` and load the anchor:

```bash
sudo cp /etc/pf.conf /etc/pf.conf.backup.$(date +%Y%m%d-%H%M%S)

if ! grep -q 'ssh-rfc1918' /etc/pf.conf; then
  printf '\nanchor "ssh-rfc1918"\nload anchor "ssh-rfc1918" from "/etc/pf.anchors/ssh-rfc1918"\n' | sudo tee -a /etc/pf.conf
fi
```

Validate and enable:

```bash
sudo pfctl -n -f /etc/pf.conf
sudo pfctl -f /etc/pf.conf
sudo pfctl -e 2>/dev/null || true
sudo pfctl -sr | grep -E 'ssh|22|rfc1918'
```

A tighter rule for a real management subnet is better:

```pf
pass in quick proto tcp from 192.168.1.0/24 to any port 22 keep state
```

Do not enable a default-deny `pf` policy until you have tested the allow rule from a second terminal while still having local console access.

## 10. If pf Breaks SSH

If SSH returns "No route to host" or stops working after `pf` changes, check:

```bash
sudo pfctl -s info
sudo pfctl -sr
```

Temporarily disable `pf`:

```bash
sudo pfctl -d
```

Then retry SSH.

If SSH works after `pfctl -d`, the `pf` rules are wrong. Reintroduce rules one at a time from the local console.

## 11. Make pf Persistent After Reboot

After a reboot, test whether the rule is active:

```bash
sudo pfctl -s info
sudo pfctl -sr | grep -E 'ssh|22|rfc1918'
```

If the rule is not active after reboot, create a LaunchDaemon:

```bash
sudo tee /Library/LaunchDaemons/local.pf.load.plist >/dev/null <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>local.pf.load</string>
    <key>ProgramArguments</key>
    <array>
      <string>/sbin/pfctl</string>
      <string>-e</string>
      <string>-f</string>
      <string>/etc/pf.conf</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
  </dict>
</plist>
EOF

sudo chown root:wheel /Library/LaunchDaemons/local.pf.load.plist
sudo chmod 644 /Library/LaunchDaemons/local.pf.load.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/local.pf.load.plist
sudo launchctl kickstart -k system/local.pf.load
```

Reboot once while you still have physical access, then confirm the `pf` rule loads automatically.

## 12. Most Likely Immediate Fix

If you are locked out during setup, run this on the Mac Mini local console:

```bash
sudo systemsetup -setremotelogin on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall off
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/libexec/sshd-keygen-wrapper
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /usr/libexec/sshd-keygen-wrapper
sudo pfctl -d
```

Then from your client:

```bash
ssh <local-user>@<mac-mini-ip>
```

Once access is restored, reintroduce firewall rules one at a time.

## 13. Verify Access and Denial

From an allowed LAN host:

```bash
ssh <user>@<mac-mini-ip>
```

Check SSH logs:

```bash
log show --predicate 'process == "sshd"' --last 1h
```

Check `pf` rules and active states:

```bash
sudo pfctl -sr
sudo pfctl -ss | grep ':22'
```

Also test from a network that should not be allowed if you have one available. The desired result is that port 22 is unreachable from untrusted networks.

## 14. Headless FileVault Test

On Apple silicon with macOS 26 or later, test FileVault unlock over SSH while you still have physical access.

Record:

```text
macOS version:
Remote Login enabled:
FileVault unlock over SSH tested:
Works after reboot?: yes/no
Fallback local access plan:
```

## Least-Regret Final State

Use this target state before moving on:

```text
Remote Login: ON
Remote Login users: Only openclaw / chosen user
Remote full disk access: OFF
SSH password auth: OFF
SSH root login: OFF
SSH key auth: ON
macOS firewall: ON
Firewall block all incoming: OFF
Stealth mode: ON
pf: port 22 allowed only from actual trusted LAN subnets
Router: no public port forward to Mac Mini
```

## References

- [Allow a remote computer to access your Mac - Apple Support](https://support.apple.com/en-kz/guide/mac-help/mchlp1066/mac)
- [Managing FileVault in macOS - Apple Platform Security](https://support.apple.com/fr-lu/guide/security/sec8447f5049/web)

---

Previous: [Chapter 02 - Security Bootstrap](chapter02.md)
Next: [Chapter 04 - macOS Hardening](chapter04.md)
[Back to main guide](README.md)
