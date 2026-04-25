[Back to main guide](README.md)

# Chapter 08 - Telegram Bot Integration

This chapter starts Telegram bot integration for the local OpenClaw Mac mini.

Goal:

```text
Telegram app
-> Telegram Bot API
-> local OpenClaw Telegram integration
-> OpenClaw gateway on loopback
-> local MLX-LM provider from Chapter 07
```

Security baseline:

```text
Telegram bot token is a secret
bot token lives in ~/.openclaw/.env
OpenClaw gateway remains loopback-only
MLX-LM API remains loopback-only
no router port forward for first setup
no public webhook for first setup
```

Important distinction:

```text
Telegram bot creation is a Telegram/BotFather task.
OpenClaw channel wiring depends on the installed OpenClaw version.
```

This chapter documents the safe host-side preparation and verification. Do not invent OpenClaw Telegram commands. If your installed OpenClaw version documents a Telegram channel command, use that documented command and record it in the install record.

## 1. Choose Polling First

Telegram supports two update delivery modes:

- `getUpdates`: the bot process polls Telegram over outbound HTTPS.
- `setWebhook`: Telegram sends HTTPS POST requests to a public URL.

For the first secure Mac mini setup, prefer polling if OpenClaw's Telegram integration supports it. Polling only needs outbound HTTPS to Telegram and does not require exposing the Mac mini to the internet.

Webhook setup is deferred to Chapter 99 because it requires a public HTTPS endpoint, DNS/TLS decisions, and a deliberate exposure model.

## 2. Create the Bot with BotFather

In Telegram:

1. Open a chat with `@BotFather`.
2. Run `/newbot`.
3. Choose a display name.
4. Choose a bot username ending in `bot`.
5. Copy the bot token.

Treat the token like a password. Anyone with the token can control the bot.

Record non-secret metadata:

```text
Bot display name:
Bot username:
Bot owner:
Created date:
Intended use:
Allowed operators:
```

Do not put the bot token in this repository.

## 3. Store the Telegram Token

Run as the OpenClaw runtime user:

```bash
mkdir -p ~/.openclaw
chmod 700 ~/.openclaw
umask 077
nano ~/.openclaw/.env
```

Add:

```text
TELEGRAM_BOT_TOKEN=replace-me
```

Then:

```bash
chmod 600 ~/.openclaw/.env
stat -f "%Su %Sp %N" ~/.openclaw ~/.openclaw/.env
```

Expected:

```text
owner is the OpenClaw runtime user
~/.openclaw is owner-only, typically drwx------
~/.openclaw/.env is owner read/write only, typically -rw-------
```

## 4. Verify the Token Without Exposing It

Load the token into the current shell without printing it:

```bash
set -a
source ~/.openclaw/.env
set +a
```

Check that it exists without showing the value:

```bash
test -n "${TELEGRAM_BOT_TOKEN:-}" && echo "Telegram token is loaded"
```

Call Telegram's `getMe` endpoint:

```bash
curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"
```

Expected:

```text
"ok":true
```

If this fails, check:

- token was copied correctly
- outbound HTTPS works from the Mac mini
- DNS resolves `api.telegram.org`
- the token was not revoked in BotFather

## 5. Ensure No Webhook Is Active

For a polling-first setup, make sure no webhook is active:

```bash
curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo"
```

If a webhook URL is set and you want polling, delete it:

```bash
curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/deleteWebhook"
```

Then verify:

```bash
curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo"
```

Expected:

```text
url is empty
```

Telegram's Bot API does not allow `getUpdates` polling while a webhook is active.

## 6. Send a Test Message to the Bot

From the Telegram app, send a message to the bot.

Then check pending updates:

```bash
curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates"
```

Expected:

```text
"ok":true
the response includes a message from your Telegram account
```

Record the operator chat ID if needed by the OpenClaw integration:

```text
Telegram operator username:
Telegram operator chat ID:
Allowed Telegram users:
Allowed Telegram chats:
```

Do not approve broad group/channel access during first setup.

## 7. Connect Telegram to OpenClaw

This is intentionally version-dependent.

Before configuring the channel, inspect what your installed OpenClaw version supports:

```bash
openclaw --help
openclaw channels --help 2>/dev/null || true
openclaw configure --help 2>/dev/null || true
openclaw doctor
```

Use OpenClaw's current Telegram/channel documentation or command help. Record the exact command used.

Required local baseline before enabling Telegram:

```bash
openclaw config get gateway.mode
openclaw config get gateway.bind
curl -fsS http://127.0.0.1:8080/v1/models
openclaw models status
openclaw doctor
```

Expected:

```text
gateway.mode: local
gateway.bind: loopback
MLX-LM endpoint responds locally
OpenClaw local provider is configured
doctor has no blocking install/bootstrap findings
```

If OpenClaw asks for a Telegram token, use the value already stored in `~/.openclaw/.env`. Do not paste the token into shell history if the command supports reading from env or config.

## 8. Scope and Abuse Controls

For the first Telegram integration:

- allow only one known operator account
- avoid groups until direct messages work
- avoid file upload/download features until reviewed
- avoid administrative commands from Telegram until explicitly approved
- keep OpenClaw and MLX-LM bound to loopback
- keep router port forwarding off

If OpenClaw supports channel allowlists, configure the Telegram user/chat allowlist before enabling the bot for normal use.

## 9. Verify End to End

After OpenClaw Telegram integration is configured:

1. Send a short Telegram message to the bot.
2. Confirm OpenClaw receives it.
3. Confirm OpenClaw uses the local provider path from Chapter 07.
4. Confirm the reply returns in Telegram.

Verify host state:

```bash
openclaw doctor
openclaw models status
curl -fsS http://127.0.0.1:8080/v1/models
lsof -nP -iTCP:8080 -sTCP:LISTEN
lsof -nP -iTCP:18789 -sTCP:LISTEN
```

Expected:

```text
MLX-LM listens on 127.0.0.1:8080
OpenClaw gateway listens on loopback
no Telegram webhook is active unless deliberately configured later
```

## 10. Troubleshooting

If `getUpdates` reports a webhook conflict, delete the webhook:

```bash
curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/deleteWebhook"
```

If `getMe` fails:

```bash
curl -v "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"
```

If the bot receives messages but OpenClaw does not:

- confirm the Telegram integration is enabled in OpenClaw
- confirm the token is available to the OpenClaw runtime process
- rerun `openclaw doctor`
- check OpenClaw logs
- confirm channel/user allowlists are not blocking the operator

If OpenClaw responds but uses the wrong model:

- check Chapter 07 provider config
- check `openclaw models status`
- confirm `http://127.0.0.1:8080/v1/models` works

## 11. Install Record

Record:

```text
Telegram bot display name:
Telegram bot username:
Telegram token location: ~/.openclaw/.env
Webhook active: yes/no
Polling mode: yes/no
Allowed Telegram users:
Allowed Telegram chats:
OpenClaw Telegram command/config used:
OpenClaw local provider:
Test date:
Notes:
```

## End-of-Chapter Check

- [ ] Telegram bot was created with BotFather.
- [ ] Bot token is stored in `~/.openclaw/.env`.
- [ ] `~/.openclaw/.env` is mode `600`.
- [ ] `getMe` returns `"ok":true`.
- [ ] No webhook is active for polling-first setup.
- [ ] `getUpdates` sees a test message.
- [ ] OpenClaw Telegram/channel command was taken from installed docs/help, not guessed.
- [ ] Telegram access is limited to known operator users/chats.
- [ ] OpenClaw still binds to loopback.
- [ ] MLX-LM still binds to `127.0.0.1`.
- [ ] No public router port forward was added.

## References

- [Telegram Bot API](https://core.telegram.org/bots/api)
- [Telegram BotFather guide](https://core.telegram.org/bots/features#botfather)

---

Previous: [Chapter 07 - Enable Local MLX-LM API Provider for OpenClaw](chapter07.md)
Next: [Chapter 09 - Backup, Updates, and Recovery](chapter09.md)
[Back to main guide](README.md)
