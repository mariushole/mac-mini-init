[Back to main guide](README.md)

# Chapter 09 - Telegram Bot Integration

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

`getMe` proves the bot token works.

The `id` returned by `getMe` is the bot's ID. Do not use it in `allowFrom`. The operator/user ID comes from `message.from.id` in `getUpdates` after you send a DM to the bot.

The bot ID is not the Telegram allowlist ID.

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

Optional explicit form that preserves pending updates:

```bash
TELEGRAM_BOT_TOKEN="$(cat ~/.openclaw/secrets/telegram-bot-token)"

curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/deleteWebhook?drop_pending_updates=false" \
| python3 -m json.tool
```

`drop_pending_updates=false` preserves pending updates. Use `drop_pending_updates=true` only if you intentionally want to discard old updates. For this guide, prefer clearing manual test updates later with `getUpdates?offset=...` after the operator ID has been recorded.

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

Load the token for this shell:

```bash
TELEGRAM_BOT_TOKEN="$(cat ~/.openclaw/secrets/telegram-bot-token)"
```

Open the Telegram bot directly and send:

```text
/start
hello openclaw test
```

Then check pending updates:

```bash
curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates" \
| python3 -m json.tool
```

Expected:

```text
"ok":true
the response includes a message from your Telegram account
```

Look for a message shaped like this:

```json
{
  "message": {
    "from": {
      "id": 123456789,
      "is_bot": false,
      "first_name": "Example",
      "username": "example_user"
    },
    "chat": {
      "id": 123456789,
      "type": "private"
    },
    "text": "hello openclaw test"
  }
}
```

Extract the relevant IDs without `jq`:

```bash
curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates" \
| python3 -c '
import json, sys

data = json.load(sys.stdin)

for update in data.get("result", []):
    msg = update.get("message") or update.get("edited_message") or {}
    user = msg.get("from", {})
    chat = msg.get("chat", {})
    text = msg.get("text", "")

    print("update_id:", update.get("update_id"))
    print("from.id:", user.get("id"))
    print("from.username:", user.get("username"))
    print("chat.id:", chat.get("id"))
    print("chat.type:", chat.get("type"))
    print("text:", text)
    print("---")
'
```

Expected example output:

```text
from.id: 123456789
from.username: example_user
chat.id: 123456789
chat.type: private
```

Record:

```text
Telegram operator username: value from message.from.username
Telegram numeric user ID: value from message.from.id
Allowed Telegram users: same numeric user ID
Allowed Telegram chats: for DM-only, same as message.chat.id
Chat type: private
```

Use `from.id` as the durable `allowFrom` value.

For a private DM-only setup, `chat.id` is normally the same value and can be recorded as the allowed private chat.

Do not use `@username` as the durable allowlist entry.

### Create a Local Telegram Evidence Log

Create a local setup log before clearing updates or enabling OpenClaw polling.

This log helps Section 10 hardening even if Telegram updates are later cleared. It is local to the OpenClaw runtime user, does not store the bot token, should be mode `600`, and is an install/debug artifact. Do not commit it to Git.

```bash
TELEGRAM_BOT_TOKEN="$(cat ~/.openclaw/secrets/telegram-bot-token)"
TELEGRAM_LOG="$HOME/.openclaw/telegramlog.md"

mkdir -p "$HOME/.openclaw"
touch "$TELEGRAM_LOG"
chmod 600 "$TELEGRAM_LOG"

python3 - <<'PY'
from pathlib import Path

log_path = Path.home() / ".openclaw" / "telegramlog.md"
if not log_path.exists() or log_path.stat().st_size == 0:
    log_path.write_text("# Telegram Setup Log\n\n", encoding="utf-8")
PY

{
  echo
  echo "## Telegram setup log update"
  echo
  echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "Token source: ~/.openclaw/secrets/telegram-bot-token"
  echo
  echo "Token value: not logged"
  echo
} >> "$TELEGRAM_LOG"

curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" \
| python3 -c '
import json
import sys
from pathlib import Path

data = json.load(sys.stdin)
result = data.get("result", {}) or {}

ok = data.get("ok")
bot_id = result.get("id")
bot_username = result.get("username")
bot_first_name = result.get("first_name")

log_path = Path.home() / ".openclaw" / "telegramlog.md"

with log_path.open("a", encoding="utf-8") as f:
    f.write("\n### getMe\n\n")
    f.write(f"ok: {ok}\n\n")
    f.write(f"bot.id: {bot_id}\n\n")
    f.write(f"bot.username: {bot_username}\n\n")
    f.write(f"bot.first_name: {bot_first_name}\n\n")

print("Logged getMe bot identity to ~/.openclaw/telegramlog.md")
'
```

Send these messages to the bot in Telegram:

```text
/start
hello openclaw test
```

Then log and summarize `getUpdates`:

```bash
TELEGRAM_BOT_TOKEN="$(cat ~/.openclaw/secrets/telegram-bot-token)"
TELEGRAM_LOG="$HOME/.openclaw/telegramlog.md"

curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates" \
| python3 -c '
import json
import sys
from pathlib import Path

data = json.load(sys.stdin)
updates = data.get("result", []) or []
log_path = Path.home() / ".openclaw" / "telegramlog.md"

users = {}

with log_path.open("a", encoding="utf-8") as f:
    f.write("\n### getUpdates summary\n\n")
    ok = data.get("ok")
    f.write(f"ok: {ok}\n\n")
    f.write(f"update.count: {len(updates)}\n\n")

    for update in updates:
        msg = update.get("message") or update.get("edited_message") or {}
        user = msg.get("from") or {}
        chat = msg.get("chat") or {}
        text = msg.get("text", "")

        update_id = update.get("update_id")
        user_id = user.get("id")
        username = user.get("username")
        first_name = user.get("first_name")
        is_bot = user.get("is_bot")
        chat_id = chat.get("id")
        chat_type = chat.get("type")

        f.write("---\n\n")
        f.write(f"update.id: {update_id}\n\n")
        f.write(f"from.id: {user_id}\n\n")
        f.write(f"from.username: {username}\n\n")
        f.write(f"from.first_name: {first_name}\n\n")
        f.write(f"from.is_bot: {is_bot}\n\n")
        f.write(f"chat.id: {chat_id}\n\n")
        f.write(f"chat.type: {chat_type}\n\n")
        f.write(f"text: {text}\n\n")

        if user_id is None:
            continue
        if is_bot is True:
            continue
        if chat_type != "private":
            continue

        user_id = str(user_id)
        users.setdefault(user_id, {
            "username": username,
            "first_name": first_name,
            "chat_ids": set(),
            "update_ids": [],
            "texts": []
        })
        users[user_id]["chat_ids"].add(str(chat_id))
        users[user_id]["update_ids"].append(update_id)
        if text:
            users[user_id]["texts"].append(text)

    f.write("\n### Operator ID detection\n\n")

    if not users:
        f.write("result: no human private-message Telegram user IDs found\n\n")
    elif len(users) == 1:
        user_id, details = next(iter(users.items()))
        f.write("result: exactly one human private-message Telegram user ID found\n\n")
        f.write(f"selected.from.id: {user_id}\n\n")
        f.write(f"selected.from.username: {details.get('username')}\n\n")
        f.write(f"selected.from.first_name: {details.get('first_name')}\n\n")
        f.write(f"selected.chat.ids: {sorted(details.get('chat_ids', []))}\n\n")
        f.write(f"selected.update.ids: {details.get('update_ids')}\n\n")
    else:
        f.write("result: more than one human private-message Telegram user ID found\n\n")
        for user_id, details in sorted(users.items()):
            f.write("---\n\n")
            f.write(f"candidate.from.id: {user_id}\n\n")
            f.write(f"candidate.from.username: {details.get('username')}\n\n")
            f.write(f"candidate.from.first_name: {details.get('first_name')}\n\n")
            f.write(f"candidate.chat.ids: {sorted(details.get('chat_ids', []))}\n\n")
            f.write(f"candidate.update.ids: {details.get('update_ids')}\n\n")

print("Logged getUpdates summary to ~/.openclaw/telegramlog.md")

if not users:
    print("No human private-message Telegram user IDs found.")
elif len(users) == 1:
    user_id, details = next(iter(users.items()))
    print(f"Detected one candidate operator user ID: {user_id}")
    print(f"Username: {details.get('username')}")
    print(f"Private chat IDs: {sorted(details.get('chat_ids', []))}")
else:
    print("More than one candidate operator user ID found. Review ~/.openclaw/telegramlog.md before allowlisting.")
'
```

This log is the durable setup evidence for the Telegram operator ID. Section 10 can use it even if pending Telegram updates are later cleared.

If the log shows more than one candidate `from.id`, do not guess. Investigate which Telegram account is the intended operator before enabling `dmPolicy: "allowlist"`.

### If getUpdates Returns an Empty Result

If `getUpdates` returns:

```json
{"ok": true, "result": []}
```

check:

- You sent the message to your bot, not to BotFather.
- You pressed or sent `/start` in the bot chat.
- You sent a new message after checking `getUpdates`.
- No other process is already polling the same bot token.
- OpenClaw Telegram integration is not already running with the same bot token.

If OpenClaw may already be polling, stop the gateway temporarily:

```bash
openclaw gateway stop
```

Then send a new Telegram message to the bot and rerun:

```bash
curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates" \
| python3 -m json.tool
```

After recording the numeric user ID, restart OpenClaw later in the correct step.

### Clear Manual Test Updates Before OpenClaw Polling

Manual `getUpdates` calls are useful before OpenClaw is enabled, but the bot may still have old `/start` or test messages pending. Clear those updates before starting OpenClaw Telegram polling so the first OpenClaw run does not process old manual test messages.

Only clear updates after you have recorded the numeric Telegram user ID.

```bash
TELEGRAM_BOT_TOKEN="$(cat ~/.openclaw/secrets/telegram-bot-token)"

LAST_UPDATE_ID="$(curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates" \
| python3 -c '
import json, sys

data = json.load(sys.stdin)
results = data.get("result", [])

if not results:
    print("")
else:
    print(results[-1]["update_id"])
')"

if [ -n "$LAST_UPDATE_ID" ]; then
  NEXT_OFFSET=$((LAST_UPDATE_ID + 1))
  curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates?offset=${NEXT_OFFSET}" \
  | python3 -m json.tool
else
  echo "No pending Telegram updates to clear"
fi
```

Verify:

```bash
curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates" \
| python3 -m json.tool
```

Expected:

```json
{
  "ok": true,
  "result": []
}
```

## 7. Configure OpenClaw Telegram Channel in openclaw.json

Back up the OpenClaw config:

```bash
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak.$(date +%Y%m%d-%H%M%S)
chmod 600 ~/.openclaw/openclaw.json*
python3 -m json.tool ~/.openclaw/openclaw.json >/tmp/openclaw-current.json
```

Get the runtime user's home directory:

```bash
HOME_DIR="$(dscl . -read "/Users/$(whoami)" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
test -n "$HOME_DIR" || HOME_DIR="$(cd ~ && pwd)"
echo "$HOME_DIR"
```

The `tokenFile` path in JSON must use the actual runtime user's home path. JSON does not expand `~` or `$HOME`.

### Bootstrap Config: Pairing

Do not replace the whole `openclaw.json` with the snippets below. Merge only the `channels.telegram` block into the existing config. Preserve existing `gateway`, `models`, `agents`, `wizard`, and `meta` blocks from earlier chapters.

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

Preferred merge helper:

```bash
HOME_DIR="$(dscl . -read "/Users/$(whoami)" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
test -n "$HOME_DIR" || HOME_DIR="$(cd ~ && pwd)"

python3 - <<PY
import json
from pathlib import Path

config_path = Path.home() / ".openclaw" / "openclaw.json"
data = json.loads(config_path.read_text())

data.setdefault("channels", {})
data["channels"]["telegram"] = {
    "enabled": True,
    "tokenFile": f"{Path.home()}/.openclaw/secrets/telegram-bot-token",
    "dmPolicy": "pairing",
    "groups": {
        "*": {
            "requireMention": True
        }
    },
    "configWrites": False
}

config_path.write_text(json.dumps(data, indent=2) + "\n")
PY

python3 -m json.tool ~/.openclaw/openclaw.json >/dev/null && echo "openclaw.json valid"
```

This creates or replaces only `channels.telegram`. It preserves existing `gateway`, `models`, `agents`, `wizard`, and `meta`.

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
PAIRING_CODE="replace-with-code-from-pairing-list"
openclaw pairing approve telegram "$PAIRING_CODE"
```

Do not paste angle-bracket code placeholders into `zsh`. Replace the variable value first.

Pairing codes expire after 1 hour. If the code changed, rerun:

```bash
openclaw pairing list telegram
```

Do not approve unknown or unexpected pairings.

## 10. Harden to Numeric Allowlist

After the first operator's numeric Telegram user ID is known, switch from pairing to allowlist.

Section 10 must be safe to paste into an interactive SSH shell. The shell snippets below do not use shell-level `exit`; if detection is unsafe, they leave `TELEGRAM_USER_ID` empty and skip the config merge.

### Detect the Operator ID from the Local Telegram Log

Prefer the local evidence log from Section 6. It still works after pending Telegram updates have been consumed or cleared.

```bash
TELEGRAM_LOG="$HOME/.openclaw/telegramlog.md"

TELEGRAM_USER_ID="$(python3 - <<'PY'
from pathlib import Path
import re
import sys

log_path = Path.home() / ".openclaw" / "telegramlog.md"

if not log_path.exists():
    print("Telegram log not found: ~/.openclaw/telegramlog.md", file=sys.stderr)
    sys.exit(1)

text = log_path.read_text(encoding="utf-8", errors="replace")

selected = re.findall(r"^selected\.from\.id:\s*([0-9]+)\s*$", text, flags=re.MULTILINE)
candidates = re.findall(r"^(?:candidate\.from\.id|from\.id):\s*([0-9]+)\s*$", text, flags=re.MULTILINE)

ids = selected if selected else candidates
unique_ids = sorted(set(ids))

if len(unique_ids) == 1:
    print(unique_ids[0])
    sys.exit(0)

if len(unique_ids) == 0:
    print("No numeric Telegram user ID found in ~/.openclaw/telegramlog.md", file=sys.stderr)
    sys.exit(1)

print("Multiple Telegram user IDs found in ~/.openclaw/telegramlog.md:", file=sys.stderr)
for value in unique_ids:
    print(f"- {value}", file=sys.stderr)
print("Review the log and choose the intended operator manually.", file=sys.stderr)
sys.exit(2)
PY
)"

if [ -n "$TELEGRAM_USER_ID" ]; then
  echo "Detected TELEGRAM_USER_ID from telegramlog.md: $TELEGRAM_USER_ID"
else
  echo "TELEGRAM_USER_ID was not detected from telegramlog.md."
  echo "Review ~/.openclaw/telegramlog.md or refresh it from getUpdates before hardening."
fi
```

### Refresh the Telegram Log if Needed

Use this only if `telegramlog.md` is missing, empty, or stale.

Stop OpenClaw gateway first if it may already be polling, send a fresh `/start` and test DM to the bot, then rerun the Section 6 getUpdates logging command.

```bash
openclaw gateway stop 2>/dev/null || true

echo "Send these messages to the Telegram bot now:"
echo "/start"
echo "hello openclaw test"

echo "Then rerun the Section 6 getUpdates logging command."
```

### Manual Fallback After Review

Use the manual fallback only after reviewing `~/.openclaw/telegramlog.md` or raw `getUpdates` output.

```bash
TELEGRAM_USER_ID="replace-with-reviewed-numeric-from-id"
```

The value must be the numeric `message.from.id`.

Do not use:

- the bot ID from `getMe`
- `@username`
- a group chat ID

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
123456789 -> the numeric Telegram user ID from message.from.id
```

Preferred allowlist merge helper. This assumes `TELEGRAM_USER_ID` was set by the extraction step above:

```bash
if [ -z "$TELEGRAM_USER_ID" ]; then
  echo "TELEGRAM_USER_ID is empty. Not modifying openclaw.json."
  echo "Review ~/.openclaw/telegramlog.md, then rerun this section."
else
  if printf '%s' "$TELEGRAM_USER_ID" | grep -Eq '^[0-9]+$'; then
    echo "TELEGRAM_USER_ID is numeric: $TELEGRAM_USER_ID"
  else
    echo "TELEGRAM_USER_ID must be numeric. Not modifying openclaw.json."
    TELEGRAM_USER_ID=""
  fi
fi

if [ -n "$TELEGRAM_USER_ID" ]; then
  cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak.$(date +%Y%m%d-%H%M%S)
  chmod 600 ~/.openclaw/openclaw.json*

  python3 - <<PY
import json
from pathlib import Path

telegram_user_id = "${TELEGRAM_USER_ID}"

if not telegram_user_id.isdigit():
    raise SystemExit("TELEGRAM_USER_ID must be a numeric Telegram user ID")

config_path = Path.home() / ".openclaw" / "openclaw.json"
data = json.loads(config_path.read_text())

data.setdefault("channels", {})
data["channels"]["telegram"] = {
    "enabled": True,
    "tokenFile": f"{Path.home()}/.openclaw/secrets/telegram-bot-token",
    "dmPolicy": "allowlist",
    "allowFrom": [telegram_user_id],
    "groupPolicy": "disabled",
    "groups": {
        "*": {
            "requireMention": True
        }
    },
    "configWrites": False,
    "actions": {
        "deleteMessage": False,
        "sticker": False
    }
}

config_path.write_text(json.dumps(data, indent=2) + "\n")
PY

  python3 -m json.tool ~/.openclaw/openclaw.json >/dev/null && echo "openclaw.json valid"

  openclaw gateway restart
  sleep 3
  openclaw doctor
  openclaw channels --channel telegram 2>/dev/null || openclaw channels
else
  echo "Skipped hardened allowlist merge because TELEGRAM_USER_ID is not safely detected."
fi
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

### Running Section 10 Closed My SSH Session

Cause:

- An older version of this guide used shell-level `exit` in a copy/paste block.
- Running `exit` in an interactive SSH shell closes the shell and drops the session.

Fix:

- Reconnect over SSH.
- Activate the virtual environment again if needed.
- Pull the updated guide.
- Use the revised Section 10, which does not use shell-level `exit`.

### `telegramlog.md` Does Not Exist

Cause:

- Section 6 log creation was not run.
- The setup was started before this chapter introduced the log file.

Fix:

```bash
mkdir -p ~/.openclaw
touch ~/.openclaw/telegramlog.md
chmod 600 ~/.openclaw/telegramlog.md
```

Then stop OpenClaw polling, send a fresh Telegram DM to the bot, and rerun the Section 6 getUpdates logging command.

### `telegramlog.md` Has No User ID

Cause:

- No private DM was sent to the bot.
- The message was sent to BotFather instead of the bot.
- OpenClaw was already polling and consumed the update before manual logging.
- Updates were cleared before logging.

Fix:

```bash
openclaw gateway stop 2>/dev/null || true
```

Then send:

```text
/start
hello openclaw test
```

Then rerun the Section 6 getUpdates logging command.

### `telegramlog.md` Has Multiple User IDs

Cause:

- More than one Telegram user has messaged the bot.
- The bot was reused or tested by multiple accounts.

Fix:

- Do not auto-allowlist.
- Review `~/.openclaw/telegramlog.md`.
- Identify the intended operator.
- Set `TELEGRAM_USER_ID` manually using the numeric `message.from.id`.
- Do not use `@username`, bot ID, or group chat ID.

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

Diagnostics order after enabling Telegram:

```bash
openclaw doctor
openclaw channels --channel telegram 2>/dev/null || openclaw channels
openclaw pairing list telegram 2>/dev/null || true
tail -n 120 ~/.openclaw/logs/gateway.log 2>/dev/null || true
```

Then send a Telegram DM to the bot.

### `getMe` works but `getUpdates` is empty

Cause:

- The bot has not received a visible message.
- `/start` was not sent.
- The test message was sent to BotFather instead of the bot.
- OpenClaw or another process already consumed the updates.

Fix:

```bash
openclaw gateway stop

TELEGRAM_BOT_TOKEN="$(cat ~/.openclaw/secrets/telegram-bot-token)"

curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates" \
| python3 -m json.tool
```

Then DM the bot again with:

```text
/start
hello openclaw test
```

Then rerun `getUpdates`.

### OpenClaw does not respond after manual getUpdates worked

Cause:

- Manual polling and OpenClaw polling may be competing.
- `channels.telegram` may not be enabled.
- The token path may be wrong.
- `dmPolicy` may be blocking the sender.
- The OpenClaw gateway may need restart.

Fix:

```bash
python3 -m json.tool ~/.openclaw/openclaw.json >/dev/null && echo "json ok"
openclaw gateway restart
sleep 3
openclaw doctor
openclaw channels --channel telegram 2>/dev/null || openclaw channels
tail -n 120 ~/.openclaw/logs/gateway.log 2>/dev/null || true
```

### `dmPolicy: allowlist` blocks all DMs

Cause:

- `allowFrom` is missing.
- `allowFrom` is empty.
- `allowFrom` contains `@username` instead of a numeric Telegram user ID.
- The bot ID from `getMe` was used instead of `message.from.id`.

Fix:

- Use `message.from.id`.
- Set `allowFrom` to a list containing the numeric Telegram user ID as a string.

Example:

```json
"allowFrom": ["123456789"]
```

### Pairing code command fails in zsh

Cause:

- A literal angle-bracket code placeholder was pasted into `zsh`.

Fix:

```bash
PAIRING_CODE="replace-with-code-from-pairing-list"
openclaw pairing approve telegram "$PAIRING_CODE"
```

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
Bot ID from getMe:
Bot username from getMe:
Telegram operator username from getUpdates:
Telegram numeric user ID from message.from.id:
Telegram private chat ID from message.chat.id:
Telegram token location: ~/.openclaw/secrets/telegram-bot-token
Token file mode:
Telegram setup log path: ~/.openclaw/telegramlog.md
Telegram setup log mode:
Operator ID source: telegramlog.md / manual review / live getUpdates
Operator ID detection result: exactly one / none / multiple
Shell-level exit avoided in Section 10: yes/no
Last manual update ID cleared:
Webhook active: yes/no
Polling mode: yes/no
Telegram config phase: pairing / allowlist
Bootstrap dmPolicy:
Hardened dmPolicy:
Allowed Telegram numeric user IDs:
Groups enabled: no
OpenClaw Telegram config path:
OpenClaw Telegram diagnostics result:
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
- [ ] `getMe` was understood as bot identity only.
- [ ] No webhook is active for polling-first setup.
- [ ] Operator sent `/start` and a test message to the bot.
- [ ] Manual `getUpdates` was used only before enabling OpenClaw polling or while gateway was stopped.
- [ ] `~/.openclaw/telegramlog.md` was created with mode `600`.
- [ ] The Telegram setup log does not contain the bot token.
- [ ] Numeric Telegram user ID was extracted from `message.from.id`.
- [ ] The numeric operator ID was derived from `message.from.id`.
- [ ] Private chat ID was extracted from `message.chat.id`.
- [ ] `@username` was not used as durable allowlist entry.
- [ ] Manual test updates were cleared with `getUpdates` offset after recording the operator ID.
- [ ] `channels.telegram` was merged into `openclaw.json` without deleting existing `gateway`, `models`, `agents`, `wizard`, or `meta` config.
- [ ] Token file path is absolute and points to a regular file.
- [ ] Bootstrap config used `dmPolicy: "pairing"`.
- [ ] Pairing commands use a `PAIRING_CODE` variable, not a literal angle-bracket placeholder.
- [ ] First DM pairing was approved with `openclaw pairing approve telegram "$PAIRING_CODE"`.
- [ ] Section 10 did not use shell-level `exit`.
- [ ] If multiple Telegram user IDs were found, allowlist hardening was paused for human review.
- [ ] Pairing approval uses `PAIRING_CODE`, not a literal angle-bracket placeholder.
- [ ] Hardened config uses `dmPolicy: "allowlist"` and numeric `allowFrom`.
- [ ] Hardened allowlist uses the numeric Telegram user ID.
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

Previous: [Chapter 08 - Prepare, Tune, and Proxy the Local LLM](chapter08.md)
Next: [Chapter 99 - Deferred Advanced Operations](chapter99.md)
[Back to main guide](README.md)
