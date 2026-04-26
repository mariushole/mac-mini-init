[Back to main guide](README.md)

# Chapter 08 - Telegram Bot Integration

This chapter enables Telegram direct-message access to the local OpenClaw Mac mini.

Target state for the first secure build:

```text
Telegram DM only
long polling/default mode
bot token stored in a token file
dmPolicy pairing for first contact
then dmPolicy allowlist with numeric Telegram user ID
groups disabled
OpenClaw gateway remains loopback-only
MLX-LM API remains loopback-only
no webhook
no router port forward
```

Security baseline:

```text
Telegram bot token is a secret
preferred token storage: ~/.openclaw/secrets/telegram-bot-token
optional env fallback: TELEGRAM_BOT_TOKEN only if the gateway environment reliably loads it
OpenClaw gateway remains loopback-only
MLX-LM API remains loopback-only
no router port forward for first setup
no public webhook for first setup
```

This chapter uses OpenClaw's documented Telegram configuration model: `channels.telegram.enabled`, `tokenFile` or `botToken`, `dmPolicy`, `allowFrom`, `groups`, and Telegram pairing commands. If the installed OpenClaw version differs, prefer `openclaw --help`, `openclaw channels --help`, and the current OpenClaw docs.

## 1. Choose Polling First

OpenClaw's Telegram channel uses long polling by default. Webhook mode is optional.

For the first secure Mac mini setup, use polling. Polling needs outbound HTTPS to Telegram and does not require exposing the Mac mini to the internet.

Webhook setup is deferred to Chapter 99 because it requires:

- public HTTPS endpoint
- DNS/TLS decisions
- `channels.telegram.webhookUrl`
- `channels.telegram.webhookSecret`
- deliberate ingress exposure

Telegram's Bot API does not allow `getUpdates` polling while a webhook is active.

## 2. Create the Bot with BotFather

In Telegram:

1. Open a chat with `@BotFather`.
2. Run `/newbot`.
3. Choose a display name.
4. Choose a bot username ending in `bot`.
5. Copy the bot token.

Recommended BotFather posture for the first build:

- keep Privacy Mode enabled
- keep group joins disabled unless you intentionally need groups later
- do not add the bot to groups yet

Relevant BotFather toggles:

```text
/setprivacy
/setjoingroups
```

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

## 3. Store the Telegram Token in a Token File

For a persistent gateway, use a token file. This is more deterministic than relying only on `.env`, because a LaunchAgent process may not load the same shell environment as your interactive SSH session.

Run as the OpenClaw runtime user:

```bash
mkdir -p ~/.openclaw/secrets
chmod 700 ~/.openclaw ~/.openclaw/secrets
umask 077
nano ~/.openclaw/secrets/telegram-bot-token
```

Paste only the token, on one line. Then:

```bash
chmod 600 ~/.openclaw/secrets/telegram-bot-token
stat -f "%Su %Sp %N" ~/.openclaw ~/.openclaw/secrets ~/.openclaw/secrets/telegram-bot-token
```

Expected:

```text
owner is the OpenClaw runtime user
~/.openclaw is owner-only, typically drwx------
~/.openclaw/secrets is owner-only, typically drwx------
telegram-bot-token is owner read/write only, typically -rw-------
```

Do not make the token file a symlink. OpenClaw expects `tokenFile` to point to a regular file.

Optional/default-account fallback:

```bash
nano ~/.openclaw/.env
```

```text
TELEGRAM_BOT_TOKEN=replace-me
```

Use this only if you know the OpenClaw gateway environment reliably loads it. This fallback applies to the default Telegram account only. Config values and token files are preferred for the guide baseline.

## 4. Verify the Token Without Exposing It

Load the token into the current shell only for manual Telegram API checks:

```bash
TELEGRAM_BOT_TOKEN="$(cat ~/.openclaw/secrets/telegram-bot-token)"
test -n "$TELEGRAM_BOT_TOKEN" && echo "Telegram token loaded for this shell"
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

## 5. Clear Webhook for Polling

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

## 6. Send a Test Message and Identify Your Numeric Telegram User ID

Use manual `getUpdates` before enabling the OpenClaw Telegram channel, or stop the OpenClaw gateway while manually inspecting updates. Do not have OpenClaw polling and manual `getUpdates` troubleshooting compete for the same bot token.

From the Telegram app, send a direct message to the bot.

Then check pending updates:

```bash
curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates"
```

Expected:

```text
"ok":true
the response includes a message from your Telegram account
```

Record the numeric user ID from `message.from.id`:

```text
Telegram operator username:
Telegram numeric user ID:
Allowed Telegram users:
Allowed Telegram chats:
```

Do not use `@username` as the durable allowlist entry. Use the numeric Telegram user ID.

## 7. Configure OpenClaw Telegram Channel in openclaw.json

Back up the OpenClaw config:

```bash
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak.$(date +%Y%m%d-%H%M%S)
chmod 600 ~/.openclaw/openclaw.json*
```

Get the runtime user's home directory:

```bash
HOME_DIR="$(dscl . -read "/Users/$(whoami)" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
test -n "$HOME_DIR" || HOME_DIR="$(cd ~ && pwd)"
echo "$HOME_DIR"
```

### Bootstrap Config: Pairing

Use pairing for the first direct-message contact:

```json
{
  "channels": {
    "telegram": {
      "enabled": true,
      "tokenFile": "/Users/openclaw/.openclaw/secrets/telegram-bot-token",
      "dmPolicy": "pairing",
      "groups": {
        "*": {
          "requireMention": true
        }
      },
      "configWrites": false
    }
  }
}
```

Replace `/Users/openclaw` with the value of `$HOME_DIR`.

`configWrites: false` is intentional for the first secure build. Telegram-triggered config writes are useful later, but they are not needed for a single-operator bootstrap.

The `groups` block keeps mention behavior explicit if the bot is accidentally added to a group. Do not add the bot to groups during the first DM-only setup.

Open the config and merge the `channels.telegram` block carefully:

```bash
nano ~/.openclaw/openclaw.json
```

Do not replace unrelated `models`, `gateway`, `agents`, or provider configuration from earlier chapters.

Validate JSON syntax:

```bash
python3 -m json.tool ~/.openclaw/openclaw.json >/dev/null && echo "openclaw.json valid"
```

## 8. Restart Gateway and Check Telegram Diagnostics

Restart:

```bash
openclaw gateway restart
sleep 3
openclaw doctor
```

Run channel diagnostics:

```bash
openclaw channels --channel telegram 2>/dev/null || openclaw channels
```

If the installed OpenClaw version uses a different flag shape, inspect:

```bash
openclaw channels --help
```

Expected:

```text
Telegram token/config is detected
long polling/default mode is active
no webhook is required for this setup
```

## 9. Pair the First Direct Message

Send a direct message to the bot from the intended operator account.

List pending Telegram pairings:

```bash
openclaw pairing list telegram
```

Approve the expected code:

```bash
openclaw pairing approve telegram <CODE>
```

Pairing codes expire after 1 hour. If the code changed, rerun:

```bash
openclaw pairing list telegram
```

Do not approve unknown or unexpected pairings.

## 10. Harden to Numeric Allowlist

After the first operator's numeric Telegram user ID is known, switch from pairing to allowlist.

Use this end-state for the first build:

```json
{
  "channels": {
    "telegram": {
      "enabled": true,
      "tokenFile": "/Users/openclaw/.openclaw/secrets/telegram-bot-token",
      "dmPolicy": "allowlist",
      "allowFrom": ["123456789"],
      "groupPolicy": "disabled",
      "groups": {
        "*": {
          "requireMention": true
        }
      },
      "configWrites": false,
      "actions": {
        "deleteMessage": false,
        "sticker": false
      }
    }
  }
}
```

Replace:

```text
/Users/openclaw -> the actual runtime user's home path
123456789 -> your numeric Telegram user ID
```

Validate and restart:

```bash
python3 -m json.tool ~/.openclaw/openclaw.json >/dev/null && echo "openclaw.json valid"
openclaw gateway restart
sleep 3
openclaw doctor
openclaw channels --channel telegram 2>/dev/null || openclaw channels
```

## 11. Do Not Configure Groups Yet

For the first build, keep Telegram DM-only.

Group setup is deferred until direct messages are working and the access model is understood.

When groups are configured later:

- group chat IDs belong under `channels.telegram.groups`
- negative group/supergroup IDs are group IDs
- `allowFrom` and `groupAllowFrom` are numeric Telegram user IDs
- do not put group IDs in `groupAllowFrom`
- group messages require mention by default

Example group shape for later:

```json
{
  "channels": {
    "telegram": {
      "groups": {
        "-1001234567890": {
          "requireMention": true
        }
      }
    }
  }
}
```

Do not use this group config during the first DM-only build.

## 12. Verify End to End

After OpenClaw Telegram integration is configured:

1. Send a short Telegram DM to the bot from the allowed operator account.
2. Confirm OpenClaw receives it.
3. Confirm OpenClaw uses the local provider path from Chapter 07.
4. Confirm the reply returns in Telegram.

Verify host state:

```bash
openclaw doctor
openclaw models status
openclaw channels --channel telegram 2>/dev/null || openclaw channels
curl -fsS http://127.0.0.1:8080/v1/models
lsof -nP -iTCP:8080 -sTCP:LISTEN
lsof -nP -iTCP:18789 -sTCP:LISTEN
```

Expected:

```text
MLX-LM listens on 127.0.0.1:8080
OpenClaw gateway listens on loopback
Telegram channel diagnostics are clean
no Telegram webhook is active
```

## 13. Troubleshooting

If `getUpdates` reports a webhook conflict, delete the webhook:

```bash
curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/deleteWebhook"
```

If `getMe` fails:

```bash
curl -v "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"
```

If the bot receives messages but OpenClaw does not:

- confirm `channels.telegram.enabled` is `true`
- confirm `tokenFile` points to a regular file
- confirm `dmPolicy` and `allowFrom` match your bootstrap or hardened phase
- rerun `openclaw doctor`
- run `openclaw channels --channel telegram 2>/dev/null || openclaw channels`
- check OpenClaw logs

If pairing does not appear:

```bash
openclaw pairing list telegram
openclaw doctor
```

If OpenClaw responds but uses the wrong model:

- check Chapter 07 provider config
- check `openclaw models status`
- confirm `http://127.0.0.1:8080/v1/models` works

## 14. Install Record

Record:

```text
Telegram bot display name:
Telegram bot username:
Telegram token location: ~/.openclaw/secrets/telegram-bot-token
Token file mode:
Webhook active: yes/no
Polling mode: yes/no
Bootstrap dmPolicy:
Hardened dmPolicy:
Allowed Telegram numeric user IDs:
Groups enabled: no
OpenClaw Telegram config path:
OpenClaw local provider:
Test date:
Notes:
```

## End-of-Chapter Check

- [ ] Telegram bot was created with BotFather.
- [ ] Privacy mode remains enabled for first setup.
- [ ] Group joins remain disabled unless deliberately needed later.
- [ ] Bot token is stored in `~/.openclaw/secrets/telegram-bot-token`.
- [ ] Token file is a regular file, not a symlink.
- [ ] Token file is mode `600`.
- [ ] `getMe` returns `"ok":true`.
- [ ] No webhook is active for polling-first setup.
- [ ] Manual `getUpdates` was used only before enabling OpenClaw polling or while gateway was stopped.
- [ ] Numeric Telegram user ID was recorded.
- [ ] Bootstrap config used `dmPolicy: "pairing"`.
- [ ] First DM pairing was approved with `openclaw pairing approve telegram <CODE>`.
- [ ] Hardened config uses `dmPolicy: "allowlist"` and numeric `allowFrom`.
- [ ] Groups are disabled for the first build.
- [ ] `configWrites` is `false`.
- [ ] `openclaw channels --channel telegram` or `openclaw channels` was checked.
- [ ] OpenClaw still binds to loopback.
- [ ] MLX-LM still binds to `127.0.0.1`.
- [ ] No public router port forward was added.

## References

- [OpenClaw Telegram channel](https://docs.openclaw.ai/channels/telegram)
- [OpenClaw channel pairing](https://docs.openclaw.ai/channels/pairing)
- [OpenClaw group channel behavior](https://docs.openclaw.ai/channels/groups)
- [OpenClaw channels CLI](https://docs.openclaw.ai/cli/channels)
- [Telegram Bot API](https://core.telegram.org/bots/api)
- [Telegram BotFather guide](https://core.telegram.org/bots/features#botfather)

---

Previous: [Chapter 07 - Enable Local MLX-LM API Provider for OpenClaw](chapter07.md)
Next: [Chapter 09 - Backup, Updates, and Recovery](chapter09.md)
[Back to main guide](README.md)
