[Back to main guide](README.md)

# Chapter 02 - Security Bootstrap

This chapter sets the security baseline before SSH, OpenClaw, or any other network service is exposed.

The goal is a Mac Mini that is encrypted, patched, quiet on the network, and not reachable from the internet. SSH setup comes next in [Chapter 03 - SSH Remote Access](chapter03.md).

Apple notes that Apple silicon Macs are already hardware encrypted, but FileVault adds password-gated protection against access without the login password. Apple also documents that stealth mode stops the Mac from responding to probing requests such as unauthorized ICMP/ping.

## 1. Baseline Target State

Before moving on, the Mac Mini should match this state:

```text
FileVault: ON
macOS firewall: ON
Stealth mode: ON
Automatic security updates: ON
Remote Login: OFF until Chapter 03
Remote Management: OFF unless deliberately required
Screen Sharing: OFF unless deliberately required
Router port forwarding: none
OpenClaw public exposure: none
```

## 2. Confirm FileVault

Check FileVault:

```bash
fdesetup status
```

If FileVault is not enabled, use the GUI:

```text
System Settings -> Privacy & Security -> FileVault -> Turn On
```

Store the recovery key outside the Mac Mini. A password manager is appropriate, but keep a separate recovery plan in case your password manager is not available during an outage.

Record:

```text
FileVault enabled:
Recovery key stored where:
Recovery tested or reviewed:
```

## 3. Enable Firewall and Stealth Mode

Enable the macOS firewall:

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
```

Enable stealth mode:

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
```

Confirm both:

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode
```

Do not enable **Block all incoming connections** if you plan to use SSH in the next chapter. That setting can prevent Remote Login from working.

## 4. Configure Automatic Updates

Open:

```text
System Settings -> General -> Software Update
```

Recommended baseline:

| Setting | Recommendation |
| --- | --- |
| Check for updates | On |
| Download new updates when available | On |
| Install Security Responses and system files | On |
| Install macOS updates | Your choice |
| Install application updates from the App Store | Your choice |

For a service host, automatic security responses are usually worth enabling. Full macOS version upgrades are often better installed manually after checking OpenClaw compatibility.

## 5. Disable Unneeded Sharing

Open:

```text
System Settings -> General -> Sharing
```

Recommended initial state:

| Service | State |
| --- | --- |
| Remote Login | Off until Chapter 03 |
| Remote Management | Off |
| Screen Sharing | Off unless needed for setup |
| File Sharing | Off |
| Media Sharing | Off |
| Printer Sharing | Off |
| AirDrop | Off |

If you temporarily enable Screen Sharing while preparing the machine, document it and turn it off when finished.

## 6. Create a Non-Admin Operating User

OpenClaw and routine remote access should not run from the daily admin account.

Create a standard user:

```text
System Settings -> Users & Groups -> Add User -> Standard
```

Example:

```text
Full name: OpenClaw
Account name: openclaw
Account type: Standard
```

Keep the Chapter 01 admin account for maintenance tasks that require privilege. Use the standard `openclaw` user for routine operation unless a later chapter identifies a specific reason to do otherwise.

List local short usernames:

```bash
dscl . list /Users | grep -v '^_'
```

Record:

```text
Admin user:
Operating user:
Operating user is admin?: no
```

## 7. Confirm No Public Exposure

On your router or firewall, confirm:

- No public port forward points to the Mac Mini.
- UPnP/NAT-PMP is not creating an unexpected inbound mapping.
- The Mac Mini is on the intended LAN, VLAN, or services network.
- Guest Wi-Fi clients cannot reach it unless that is intentional.

Do not expose SSH or OpenClaw directly to the internet. If remote access is needed later, document a VPN or other deliberate remote-access design.

## 8. Bootstrap Checklist

- [ ] FileVault is enabled.
- [ ] The FileVault recovery key is stored outside the Mac Mini.
- [ ] macOS firewall is enabled.
- [ ] Stealth mode is enabled.
- [ ] Automatic security responses are enabled.
- [ ] Unneeded sharing services are off.
- [ ] A standard operating user exists.
- [ ] The router has no public forwarding to the Mac Mini.
- [ ] Physical console access is still available for SSH setup and testing.

## References

- [Protect data on your Mac with FileVault - Apple Support](https://support.apple.com/en-lb/guide/mac-help/mh11785/mac)
- [Change Firewall settings on Mac - Apple Support](https://support.apple.com/en-om/guide/mac-help/mh11783/mac)

---

Previous: [Chapter 01 - First Boot and Initial macOS Setup](chapter01.md)  
Next: [Chapter 03 - SSH Remote Access](chapter03.md)
[Back to main guide](README.md)
