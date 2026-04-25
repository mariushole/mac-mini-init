# Codex Instructions for This Repository

This repository is a Markdown guide for securely preparing a Mac mini to run OpenClaw on a home network. Keep future edits operational, security-first, and consistent with the existing chapter structure.

## Account Naming Rules

- Use `openclaw` as the example OpenClaw runtime user.
- Use `adminuser` as the example administrator account.
- Do not use personal or local usernames from chat history as examples.
- Prefer descriptive labels when examples are not needed: runtime user, admin user, workstation, Mac mini, router, trusted LAN.

## Security Baseline

Preserve this baseline throughout the guide:

- OpenClaw runs as a standard non-admin runtime user.
- Admin access is temporary and only for system-level tasks.
- OpenClaw files, config, sessions, tokens, logs, and secrets belong to the runtime user.
- Gateway mode is `local`.
- Gateway bind is `loopback`.
- Gateway auth uses a token.
- Remote access uses SSH or an SSH tunnel.
- The macOS firewall stays conservative.
- No public router port forward points to OpenClaw.
- Do not recommend running OpenClaw as root, with `sudo`, or as the admin account.

## Chapter Boundaries

Keep the current split clear:

- Chapter 04 prepares SSH/headless operation and must stop before installing OpenClaw.
- Chapter 05 bootstraps OpenClaw installation and `openclaw doctor`.
- Chapter 06 configures gateway, providers, channels, security audit, and persistent service behavior.

Do not move provider secrets, channel setup, persistent service design, or LaunchAgent final setup back into Chapter 05.

## Local Access vs SSH

Always make the local-vs-SSH boundary explicit:

- Local keyboard/mouse/monitor is required for initial macOS setup.
- The Mac mini can move to permanent wired/headless location after Chapter 04 is complete and SSH reconnect after reboot has been tested.
- SSH-ready does not mean OpenClaw is persistent-service-ready.
- OpenClaw is not appliance-style/headless until Chapter 06 persistent gateway behavior is selected, configured, and tested.

## LaunchAgent Guidance

Preserve the LaunchAgent distinction:

- `openclaw gateway install` uses a user LaunchAgent.
- Pure SSH/headless sessions may not have the target user's GUI launchd domain.
- LaunchAgent error 125 is a macOS session/domain limitation, not a failed OpenClaw install.
- Do not fix LaunchAgent problems by using `sudo` or the admin account.
- If using the default LaunchAgent, run it as the OpenClaw runtime user, and use a GUI login session if macOS requires one.
- Treat custom LaunchDaemon or external supervisor designs as advanced, not the initial safe baseline.

## Command Style

- Keep commands copy/paste-safe.
- Use fenced code blocks with language tags.
- Prefer commands that work over SSH for Chapters 04-06 unless a local GUI requirement is explicitly stated.
- Use `su - adminuser` only where admin escalation is required, then show `exit` back to the runtime user.
- Do not invent OpenClaw commands. If uncertain, describe the assumption or verify against official OpenClaw docs before adding commands.

## Documentation Style

- Keep language direct, practical, and security-first.
- Explain what prompts mean, what answer to choose, and why.
- Separate install success, doctor repair, manual gateway test, persistent service install, provider/channel configuration, and security audit.
- Keep chapter previous/next links and README tables synchronized.
- Update checklists when behavior or chapter scope changes.
- Do not duplicate large sections between chapters.

## Git Hygiene

- Commit only intentional guide files.
- Do not commit local Codex scratch files or private environment notes.
- Keep `.codex` and similar local agent state ignored.

