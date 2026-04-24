[Back to main guide](README.md)

# Chapter 02 - Secure SSH Remote Access

This chapter prepares the Mac Mini for secure headless administration on the home network.

The target state is simple: FileVault on, macOS firewall on, stealth mode on, no internet port forwarding, and SSH enabled only for one chosen local user. Port 22 should be reachable only from trusted local networks.

Apple documents that Remote Login enables SSH/SFTP and can be limited to "Only these users." Apple also documents that FileVault adds password-gated protection on Apple silicon, and that stealth mode prevents the Mac from answering probing requests such as unauthorized ICMP/ping. See the references at the end of this chapter.

## 1. Confirm the Baseline

Before enabling SSH, confirm the Chapter 01 baseline:

- [ ] FileVault is enabled.
- [ ] The macOS firewall is enabled.
- [ ] Automatic security updates are enabled.
- [ ] No router port forward points to the Mac Mini.
- [ ] Remote Management is off unless deliberately required.
- [ ] Screen Sharing is off unless deliberately required.
- [ ] You have local keyboard/display access while testing headless recovery.

Check FileVault:

```bash
fdesetup status
```

Enable the macOS firewall and stealth mode:

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
```

Check the firewall state:

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode
```

If FileVault is not enabled, use the GUI:

```text
System Settings -> Privacy & Security -> FileVault -> Turn On
```

Store the recovery key outside the Mac Mini, preferably in a password manager plus a separate offline recovery record.

## 2. Create or Choose the SSH User

Use a dedicated standard user for remote access. The examples use:

```bash
SSH_USER="openclaw"
```

Create the user in the GUI:

```text
System Settings -> Users & Groups -> Add User -> Standard
```

Do not make this user an administrator unless there is a clear operational need. Use the admin account from Chapter 01 for system maintenance, and use the standard `openclaw` user for routine remote access.

List local short usernames:

```bash
dscl . list /Users | grep -v '^_'
```

Record the chosen user:

```text
SSH user:
Is admin?: no
Purpose: OpenClaw remote administration
```

## 3. Add SSH Public-Key Login

On your laptop or administration machine, create a dedicated key if you do not already have one:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/macmini_openclaw_ed25519
```

Show the public key:

```bash
cat ~/.ssh/macmini_openclaw_ed25519.pub
```

On the Mac Mini, as an admin user:

```bash
SSH_USER="openclaw"

sudo mkdir -p /Users/$SSH_USER/.ssh
sudo nano /Users/$SSH_USER/.ssh/authorized_keys
```

Paste the public key into `authorized_keys`, then fix ownership and permissions:

```bash
sudo chown -R $SSH_USER:staff /Users/$SSH_USER/.ssh
sudo chmod 700 /Users/$SSH_USER/.ssh
sudo chmod 600 /Users/$SSH_USER/.ssh/authorized_keys
```

Do not put private keys in this repository.

## 4. Enable Remote Login Only for That User

Use the GUI first, because it makes the access model visible:

```text
System Settings -> General -> Sharing -> Remote Login -> Info
Remote Login: On
Allow access for: Only these users
Add: openclaw / your chosen user
Allow full disk access for remote users: Off
```

The command-line equivalent is:

```bash
SSH_USER="openclaw"

sudo dseditgroup -o create -q com.apple.access_ssh 2>/dev/null || true
sudo dseditgroup -o edit -a "$SSH_USER" -t user com.apple.access_ssh
sudo dseditgroup -o checkmember -m "$SSH_USER" com.apple.access_ssh

sudo systemsetup -setremotelogin on
```

Check that SSH is listening:

```bash
sudo lsof -nP -iTCP:22 -sTCP:LISTEN
```

## 5. Harden SSH Server Config

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

From another machine on the LAN, test key-based login:

```bash
ssh -i ~/.ssh/macmini_openclaw_ed25519 openclaw@<mac-mini-ip>
```

Do not close your local console session until this test works.

## 6. Restrict SSH to Trusted Local Networks with pf

The macOS application firewall is useful, but it is not the right tool for subnet-based SSH restrictions. Use `pf` to limit port 22.

For initial setup, this chapter allows SSH from RFC1918 private networks:

```text
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
```

Long term, replace those broad ranges with your actual management networks, such as `192.168.10.0/24` or a trusted lab VPN subnet. RFC1918 does not always mean trusted. A hotel, office, client site, or guest network may also use private address space.

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

When you know the real trusted networks, tighten the table:

```pf
table <ssh_rfc1918> persist { 192.168.10.0/24, 10.20.30.0/24 }
```

## 7. Make pf Persistent After Reboot

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

## 8. Verify Access and Denial

Find the Mac Mini IP address:

```bash
ipconfig getifaddr en0
ipconfig getifaddr en1
```

From an allowed LAN host:

```bash
ssh -i ~/.ssh/macmini_openclaw_ed25519 openclaw@<mac-mini-ip>
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

## 9. Headless FileVault Note

On Apple silicon with macOS 26 or later, Apple says FileVault can be unlocked over SSH after restart if Remote Login is enabled and a network connection is available.

Treat this as a feature to test, not an assumption. Verify it while the Mac Mini is still connected to a keyboard, display, and trusted network. Document whether it works on your exact hardware, macOS version, and router/switch setup.

Record the result:

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
FileVault: ON
macOS firewall: ON
Stealth mode: ON
Remote Login: ON
Remote Login users: Only openclaw / chosen user
Remote full disk access: OFF
SSH password auth: OFF
SSH root login: OFF
SSH key auth: ON
pf: port 22 allowed only from actual trusted LAN subnets
Router: no public port forward to Mac Mini
OpenClaw gateway later: localhost only, token auth, no public bind
```

## References

- [Allow a remote computer to access your Mac - Apple Support](https://support.apple.com/en-kz/guide/mac-help/mchlp1066/mac)
- [Protect data on your Mac with FileVault - Apple Support](https://support.apple.com/en-lb/guide/mac-help/mh11785/mac)
- [Change Firewall settings on Mac - Apple Support](https://support.apple.com/en-om/guide/mac-help/mh11783/mac)
- [Managing FileVault in macOS - Apple Platform Security](https://support.apple.com/fr-lu/guide/security/sec8447f5049/web)

---

Previous: [Chapter 01 - First Boot and Initial macOS Setup](chapter01.md)  
Next: [Chapter 03 - macOS Hardening](chapter03.md)  
[Back to main guide](README.md)

