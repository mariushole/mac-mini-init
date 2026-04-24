# Mac Mini Init for OpenClaw

Step-by-step notes for preparing a new Mac Mini to run OpenClaw securely on a home network.

This guide assumes the Mac Mini is dedicated to OpenClaw or mostly dedicated to home automation / homelab use. The goal is a boring, repeatable setup: local admin access, conservative network exposure, automatic updates where appropriate, and enough documentation that the machine can be rebuilt later without guessing.

## Guide Structure

| Chapter | Status | Topic |
| --- | --- | --- |
| [01 - First Boot and Initial macOS Setup](chapter01.md) | Drafted | Unbox, initialize macOS, create the first admin user, and apply baseline security settings. |
| [02 - Network Plan and Router Prep](chapter02.md) | Scaffold | Decide where the Mac Mini lives on the home network before installing services. |
| [03 - macOS Hardening](chapter03.md) | Scaffold | Tighten sharing, firewall, FileVault, updates, accounts, and local access. |
| [04 - Remote Administration](chapter04.md) | Scaffold | Set up SSH or screen sharing safely for maintenance. |
| [05 - OpenClaw Prerequisites](chapter05.md) | Scaffold | Install the package managers, runtimes, and system tools OpenClaw needs. |
| [06 - OpenClaw Install](chapter06.md) | Scaffold | Install OpenClaw and keep its files, secrets, and logs organized. |
| [07 - Home Network Access](chapter07.md) | Scaffold | Expose OpenClaw only where needed on the LAN, with DNS, TLS, or reverse proxy notes. |
| [08 - Backup, Updates, and Recovery](chapter08.md) | Scaffold | Back up config, document restore steps, and maintain the host over time. |

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
| Admin user | `admin` |
| OpenClaw service user | `openclaw` |
| LAN domain | `home.arpa` |
| LAN address | DHCP reservation, for example `192.168.1.50` |

## Progress Checklist

- [ ] Chapter 01: Complete first boot and initial macOS setup.
- [ ] Chapter 02: Reserve an IP address and decide the network placement.
- [ ] Chapter 03: Apply macOS hardening.
- [ ] Chapter 04: Configure remote administration.
- [ ] Chapter 05: Install prerequisites.
- [ ] Chapter 06: Install OpenClaw.
- [ ] Chapter 07: Configure LAN access.
- [ ] Chapter 08: Document backup and recovery.

