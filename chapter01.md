[Back to main guide](README.md)

# Chapter 01 - First Boot and Initial macOS Setup

This chapter covers the out-of-box setup for a new Mac Mini before installing OpenClaw or exposing any service on the home network.

The outcome should be a clean macOS install with a known hostname, a local admin account, updates applied, disk encryption enabled, and unnecessary sharing disabled.

## Before You Start

Have these ready:

- A keyboard, mouse or trackpad, and display.
- A wired Ethernet connection if possible.
- Your Wi-Fi credentials, if Ethernet is not available.
- Your Apple ID decision: either sign in now, or intentionally skip it for a dedicated server-style Mac.
- A hostname you will recognize later, such as `openclaw-mini`.
- A password manager ready for the local admin password and recovery details.

## 1. Connect the Mac Mini

1. Place the Mac Mini somewhere with good ventilation.
2. Connect power, display, keyboard, and mouse or trackpad.
3. Connect Ethernet to your home router or switch if available.
4. Power on the Mac Mini.

Prefer Ethernet for a home service host. Wi-Fi can work, but wired networking is easier to troubleshoot and less likely to change behavior after router updates.

## 2. Select Region, Language, and Accessibility

1. Choose your country or region.
2. Choose your preferred language and keyboard layout.
3. Configure accessibility options only if needed.

Keep the setup ordinary here. Most hardening happens after the first login, when all relevant settings are available.

## 3. Connect to the Network

1. If using Ethernet, confirm the Mac is connected.
2. If using Wi-Fi, join your trusted home Wi-Fi network.
3. Do not join guest Wi-Fi for this machine unless your network design intentionally isolates OpenClaw there.

At this stage, do not create router port forwards, firewall exceptions, or public DNS records. The machine should only need outbound internet access for setup and updates.

## 4. Migration Assistant

When asked whether to transfer data from another Mac:

1. Choose **Set Up as New**.
2. Do not import a personal user profile.
3. Do not import old login items, background services, or unknown developer tools.

A clean setup makes the future OpenClaw installation easier to audit.

## 5. Apple ID Choice

For a dedicated OpenClaw host, either option can be reasonable:

- Sign in with an Apple ID if you want standard macOS conveniences such as Find My, App Store access, and easier recovery.
- Skip Apple ID during setup if you want the machine to be less tied to a personal account.

If you skip Apple ID now, you can still sign in later from **System Settings**.

Avoid using a shared family Apple ID or an account where multiple people know the password.

## 6. Create the First Admin Account

Create a local administrator account for maintaining the Mac:

| Field | Recommended approach |
| --- | --- |
| Full name | Something clear, such as `Mac Admin` |
| Account name | Short and boring, such as `admin` |
| Password | Unique, long, and stored in a password manager |
| Password hint | Leave blank or use a non-sensitive hint |

Do not use this account as the future OpenClaw service account. The service account should be created later with only the access it needs.

## 7. Privacy, Analytics, and Siri

Use conservative choices:

1. Disable Location Services unless you need Find My or location-aware features.
2. Disable analytics sharing.
3. Disable Siri if this is a headless or server-style Mac.
4. Disable Screen Time unless you intentionally use it for administration.

These settings are not the core security boundary, but a minimal host is easier to reason about.

## 8. Reach the Desktop

After the first login:

1. Wait a few minutes for macOS to finish first-run background tasks.
2. Open **System Settings**.
3. Confirm you are logged in as the local admin account.

Do not install OpenClaw yet. First apply the base operating system settings below.

## 9. Set the Computer Name

Set a stable name before reserving an IP address or writing router rules.

1. Open **System Settings**.
2. Go to **General**.
3. Open **About**.
4. Set **Name** to your chosen hostname, for example `openclaw-mini`.

Then confirm the local hostname:

1. Go to **System Settings**.
2. Open **General**.
3. Open **Sharing**.
4. Confirm the local network name matches what you expect.

Document the name in your own notes:

```text
Mac hostname:
Local network name:
Serial number:
Purchase date:
Physical location:
```

## 10. Install macOS Updates

Update macOS before installing services.

1. Open **System Settings**.
2. Go to **General**.
3. Open **Software Update**.
4. Install all available macOS updates.
5. Reboot when prompted.
6. Repeat the check until no further updates are offered.

Then configure automatic updates:

1. In **Software Update**, open the automatic update options.
2. Enable checks for updates.
3. Enable security responses and system files.
4. Decide whether full macOS version upgrades should install automatically.

For a service host, automatic security updates are usually desirable. Full major upgrades may be better handled manually after confirming OpenClaw compatibility.

## 11. Enable FileVault

FileVault protects data at rest if the Mac Mini is stolen or removed from the home.

1. Open **System Settings**.
2. Go to **Privacy & Security**.
3. Open **FileVault**.
4. Turn FileVault on.
5. Store the recovery key in your password manager.

Confirm you can find the recovery key before moving on. Do not store it only on the Mac Mini.

## 12. Review Lock Screen Settings

1. Open **System Settings**.
2. Go to **Lock Screen**.
3. Require a password soon after sleep or screen saver begins.
4. Disable automatic login if it is available.

Suggested baseline:

| Setting | Suggested value |
| --- | --- |
| Require password after screen saver or display sleep | Immediately or 5 seconds |
| Turn display off on power adapter | Your preference |
| Start screen saver when inactive | Your preference |
| Show password hints | Off |
| Automatic login | Off |

## 13. Disable Unneeded Sharing

Before OpenClaw is installed, sharing should be off unless you need it for setup.

1. Open **System Settings**.
2. Go to **General**.
3. Open **Sharing**.
4. Turn off services you are not using.

Recommended initial state:

| Service | Initial state | Notes |
| --- | --- | --- |
| AirDrop | Off | Not needed for a service host. |
| File Sharing | Off | Enable later only if required. |
| Media Sharing | Off | Not needed. |
| Printer Sharing | Off | Not needed. |
| Remote Login | Off | Enable in a later chapter if using SSH. |
| Remote Management | Off | Enable only if you understand the management path. |
| Screen Sharing | Off | Enable in a later chapter if needed. |

If you must enable Screen Sharing temporarily during setup, turn it off again when finished or document why it remains enabled.

## 14. Turn On the macOS Firewall

1. Open **System Settings**.
2. Go to **Network**.
3. Open **Firewall**.
4. Turn the firewall on.
5. Open firewall options.
6. Keep incoming connections blocked unless a known service needs them.

Do not add OpenClaw firewall rules yet. Add them only after the install chapter identifies the ports and bind addresses actually required.

## 15. Confirm Date, Time, and Time Zone

1. Open **System Settings**.
2. Go to **General**.
3. Open **Date & Time**.
4. Enable automatic date and time.
5. Confirm the time zone is correct.

Accurate time matters for logs, certificates, updates, and troubleshooting.

## 16. Create a Setup Record

Create a private note in your password manager or homelab documentation with:

```text
Hostname:
Admin account name:
FileVault recovery key location:
Network connection type:
Router/switch port:
macOS version:
Automatic update choices:
Sharing services left enabled:
Firewall enabled:
Setup completed by:
Setup date:
```

Do not put passwords or recovery keys in this repository.

## 17. End-of-Chapter Check

Before continuing, verify:

- [ ] The Mac Mini was set up as new.
- [ ] A dedicated local admin account exists.
- [ ] The computer has a stable name.
- [ ] macOS updates have been installed.
- [ ] FileVault is enabled and the recovery key is stored safely.
- [ ] The macOS firewall is enabled.
- [ ] Unneeded sharing services are off.
- [ ] The setup record exists outside this repository.

## Next Step

Continue to [Chapter 02 - Network Plan and Router Prep](chapter02.md).

---

Previous: [Main Guide](README.md)  
Next: [Chapter 02 - Network Plan and Router Prep](chapter02.md)  
[Back to main guide](README.md)

