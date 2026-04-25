# Mac Mini Init for OpenClaw

Step-by-step notes for preparing a new Mac Mini to run OpenClaw securely on a home network.

This guide assumes the Mac Mini is dedicated to OpenClaw or mostly dedicated to home automation / homelab use. The goal is a boring, repeatable setup: local admin access, conservative network exposure, automatic updates where appropriate, and enough documentation that the machine can be rebuilt later without guessing.

## Headless Readiness and Local-Access Requirements

There are two separate milestones:

```text
1. The Mac mini is remotely manageable over SSH.
2. OpenClaw is persistently manageable as a gateway service after reboot.
```

These are not the same.

You can move the Mac mini to its permanent cabled/headless location after Chapter 04 is complete and verified.

Chapter 05 makes local inference ready. Chapter 06 makes OpenClaw installed and doctor-repaired. Chapter 07 exposes the local MLX-LM model as a loopback API provider for OpenClaw.

OpenClaw itself should not be considered fully appliance-style/headless after reboot until persistent gateway behavior has been selected, configured, and tested in the later operations chapters.

| Phase / chapter | Local keyboard/mouse/monitor needed? | Can run over SSH? | Notes |
| --- | ---: | ---: | --- |
| Physical unpacking, power, monitor, keyboard, mouse | Yes | No | Required for first boot and macOS setup assistant. |
| macOS first-run setup | Yes | No | Create initial admin account, confirm network, complete Apple setup prompts. |
| Enable/verify wired network | Usually yes initially | Later yes | After SSH is working, network checks can be done remotely. |
| Enable Remote Login / SSH | Usually yes initially | After enabled, yes | Must be enabled before full headless operation. |
| Create/verify non-admin OpenClaw runtime user | Yes or SSH as admin | Yes after SSH works | Can be done from GUI or with admin shell commands, but must be verified. |
| Chapter 04 - Prepare SSH and Headless Operations | Maybe for first SSH enablement; otherwise no | Yes | This chapter proves the Mac is ready for headless operation. |
| Xcode Command Line Tools | Maybe | Yes with `softwareupdate` method | GUI `xcode-select --install` may require local GUI; headless fallback uses `softwareupdate`. |
| Chapter 05 - Install Local LLM Runtime for Headless OpenClaw | No | Yes | MLX-LM, Qwen 3.5 9B model selection, local inference test, and resource checks. |
| Chapter 06 - Install and Bootstrap OpenClaw | No | Yes | Installer, PATH, doctor repair, permissions, session store, token, local gateway config. |
| Manual foreground gateway test | No | Yes | Run from SSH using `openclaw gateway --port 18789`. |
| SSH tunnel test | No | Yes | Client workstation tunnels to Mac loopback gateway. |
| Default user LaunchAgent install | Sometimes yes | Sometimes no | May fail over pure SSH with launchctl error 125 unless the runtime user has a GUI login session. |
| Chapter 07 - Enable Local MLX-LM API Provider for OpenClaw | Sometimes | Mostly yes | Creates the local loopback MLX-LM API endpoint, optional user LaunchAgent, and OpenClaw local provider path. |
| Custom LaunchDaemon/headless supervisor | No, after SSH works | Yes | Advanced only; not the default OpenClaw-shipped path. |

## When Can I Remove Keyboard, Mouse, and Monitor?

The Mac mini can be placed permanently on wired network and managed remotely after all of these are true:

- You can SSH into the Mac mini from your workstation.
- You can SSH as the intended OpenClaw runtime user, for example `openclaw`.
- The runtime user is confirmed non-admin.
- You know the admin account name and can temporarily escalate with `su - adminuser`.
- Wired network/IP/DNS/default route are verified.
- Remote Login survives reboot.
- FileVault/reboot behavior is understood.
- Xcode Command Line Tools and Git are installed or have a documented headless install path.
- You have tested reconnecting after a reboot.

Verification commands:

```bash
whoami
id -Gn
hostname
scutil --get ComputerName
scutil --get LocalHostName
ifconfig | awk '/^[a-z0-9]+:/{iface=$1} /inet / && $2!="127.0.0.1"{print iface, $2}'
route -n get default
git --version
xcode-select -p
```

Reboot test:

```bash
su - adminuser
sudo shutdown -r now
```

Then from the workstation:

```bash
ssh openclaw@<mac-mini-ip>
```

## What May Still Require Local GUI Access Later?

- macOS first-run setup and recovery prompts.
- Accepting GUI prompts from `xcode-select --install` if not using the headless `softwareupdate` method.
- Signing in as the OpenClaw runtime user to create a GUI launchd domain if the default OpenClaw LaunchAgent install fails over SSH.
- Some macOS privacy/security prompts depending on future tools, channels, browser automation, local model apps, or provider integrations.
- FileVault unlock at boot if the Mac is fully powered off and does not support the desired remote-unlock workflow.
- Troubleshooting if network/SSH breaks.

> **Important: SSH Headless Is Not the Same as LaunchAgent-Ready**
>
> The Mac can be fully manageable over SSH while OpenClaw's default user LaunchAgent still cannot be installed from a pure SSH session.
>
> Observed error:
>
> ```text
> launchctl bootstrap failed: Bootstrap failed: 125: Domain does not support specified action
> LaunchAgent openclaw gateway install --force requires a logged-in macOS GUI session for this user.
> ```
>
> This is not an OpenClaw install failure. Do not fix it by running OpenClaw as admin or with `sudo`.
>
> If using the default LaunchAgent, sign in to the macOS desktop as the OpenClaw runtime user and rerun:
>
> ```bash
> openclaw gateway install --force
> ```
>
> If the goal is a true headless appliance that starts before GUI login, defer that to an advanced custom LaunchDaemon/supervisor design.

## Remote/Headless Maturity Levels

| Level | Meaning | Operational status |
| --- | --- | --- |
| Level 0 - Local setup | Requires keyboard/mouse/monitor | macOS setup not complete. |
| Level 1 - SSH-ready Mac | Mac can be managed over SSH | Safe to move Mac to permanent wired location after Chapter 04. |
| Level 2 - Local LLM runtime ready | MLX-LM and Qwen 3.5 9B work locally | Chapter 05 complete; local inference baseline is ready. |
| Level 3 - OpenClaw bootstrap-ready | OpenClaw installed and doctor repaired over SSH | Chapter 06 complete; OpenClaw runtime state is healthy. |
| Level 4 - Remote OpenClaw operation | Gateway reachable through SSH tunnel and provider path is configured | Good for controlled operator use; may still be manual after reboot. |
| Level 5 - Persistent gateway | Gateway starts after reboot/login | Requires validated LaunchAgent or deliberate custom service model. |
| Level 6 - Appliance-style headless | Gateway and local model runtime start after reboot without GUI login | Advanced; likely needs custom service/supervisor design and security review. |

For the first safe build, target Level 4 first: SSH-ready Mac, local Qwen model working, OpenClaw installed, gateway reachable through SSH tunnel, and no public exposure. Do not rush to appliance-style Level 6.

## Why Local LLM Comes Before OpenClaw Provider Setup

OpenClaw can be installed before a local model runtime exists, but provider onboarding becomes cleaner if the intended local runtime and model are already installed and tested. Otherwise onboarding may push the operator into temporary or GUI-oriented provider choices.

The local model runtime is a dependency for a clean OpenClaw operating setup, even if it is not strictly required for installing the OpenClaw CLI.

## Guide Structure

| Chapter | Status | Topic |
| --- | --- | --- |
| [01 - First Boot and Initial macOS Setup](chapter01.md) | Drafted | Unbox, initialize macOS, create the first admin user, and apply baseline security settings. |
| [02 - Security Bootstrap](chapter02.md) | Drafted | Turn on FileVault, firewall, stealth mode, updates, and create the non-admin operating user. |
| [03 - SSH Remote Access](chapter03.md) | Drafted | Enable SSH from the local console, install GitHub public keys, restrict access, and troubleshoot lockouts. |
| [04 - Prepare SSH and Headless Operations](chapter04.md) | Drafted | Get the Mac mini ready to run permanently without keyboard/mouse/monitor and verify SSH, users, network, Git, and headless prerequisites. |
| [05 - Install Local LLM Runtime for Headless OpenClaw](chapter05.md) | Drafted | Install and test the local model runtime before OpenClaw provider onboarding, using MLX-LM and Qwen 3.5 9B as the April 2026 baseline for a Mac mini M4 with 16 GB unified memory. |
| [06 - Install and Bootstrap OpenClaw](chapter06.md) | Drafted | Install OpenClaw as the non-admin runtime user, repair first-run doctor findings, set local/loopback/token gateway baseline, and verify local OpenClaw runtime state. |
| [07 - Enable Local MLX-LM API Provider for OpenClaw](chapter07.md) | Drafted | Expose the local MLX-LM model through a loopback OpenAI-compatible API endpoint and configure OpenClaw to use it. |
| [08 - Telegram Bot Integration](chapter08.md) | Started | Create a Telegram bot, store its token securely, verify Bot API access, and prepare OpenClaw channel wiring without public exposure. |
| [09 - Backup, Updates, and Recovery](chapter09.md) | Scaffold | Back up config, document restore steps, and maintain the host over time. |
| [99 - Deferred Advanced Operations](chapter99.md) | Parking lot | Cloud provider secrets, device pairing, channels, home network access, broad audits, LaunchAgent policy, reboot checks, and update procedures. |

## Security Principles

- Keep OpenClaw reachable only from the home network unless there is a deliberate remote-access design.
- Prefer one dedicated service account for OpenClaw instead of running everything from a daily admin account.
- Turn on FileVault before the machine contains long-lived credentials.
- Disable sharing services you do not actively use.
- Keep a written record of hostnames, static IP reservations, installed tools, and recovery steps.
- Treat router port forwarding as a last resort.

## Naming Used in This Guide

Replace these examples with your own values as you work through the chapters:

| Item | Example |
| --- | --- |
| Mac hostname | `openclaw-mini` |
| Admin user | `adminuser` |
| OpenClaw runtime user | `openclaw` |
| LAN domain | `home.arpa` |
| LAN address | DHCP reservation, for example `192.168.1.50` |

## Progress Checklist

- [ ] Chapter 01: Complete first boot and initial macOS setup.
- [ ] Chapter 02: Apply the security bootstrap.
- [ ] Chapter 03: Configure SSH remote access.
- [ ] Chapter 04: Prepare SSH and headless operations.
- [ ] Chapter 05: Install and test the local LLM runtime.
- [ ] Chapter 06: Bootstrap OpenClaw install and doctor.
- [ ] Chapter 07: Enable the local MLX-LM API provider for OpenClaw.
- [ ] Chapter 08: Start Telegram bot integration.
- [ ] Chapter 09: Document backup and recovery.
- [ ] Chapter 99: Review deferred advanced operations when needed.
