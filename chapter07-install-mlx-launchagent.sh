#!/usr/bin/env bash
set -u

MODEL="${MODEL:-mlx-community/Qwen3.5-9B-OptiQ-4bit}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
LABEL="ai.openclaw.mlx-lm"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$1"
}

info() {
  printf 'INFO: %s\n' "$1"
}

HOME_DIR="$(dscl . -read "/Users/$(whoami)" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
[ -n "$HOME_DIR" ] || HOME_DIR="$(cd ~ && pwd)"
[ -n "$HOME_DIR" ] || fail "could not determine home directory"

OPENCLAW_DIR="$HOME_DIR/.openclaw"
LOCAL_LLM_DIR="$HOME_DIR/local-llm"
VENV_PATH="$LOCAL_LLM_DIR/.venv"
WRAPPER="$OPENCLAW_DIR/bin/start-mlx-lm-server.sh"
PLIST_DIR="$HOME_DIR/Library/LaunchAgents"
PLIST="$PLIST_DIR/$LABEL.plist"
LOG_OUT="$OPENCLAW_DIR/logs/mlx-lm-server.log"
LOG_ERR="$OPENCLAW_DIR/logs/mlx-lm-server.err"

printf '== MLX-LM LaunchAgent installer ==\n'
printf 'Runtime user: %s\n' "$(whoami)"
printf 'Home: %s\n' "$HOME_DIR"
printf 'Model: %s\n' "$MODEL"
printf 'Endpoint: http://%s:%s\n' "$HOST" "$PORT"

GROUPS_OUT="$(id -Gn 2>/dev/null || true)"
case " $GROUPS_OUT " in
  *" admin "*) fail "runtime user is in the admin group; run as the non-admin OpenClaw runtime user" ;;
  *) pass "runtime user is not in the admin group" ;;
esac

[ -d "$VENV_PATH" ] || fail "venv not found at $VENV_PATH; complete Chapter 05 first"

mkdir -p "$OPENCLAW_DIR/bin" "$OPENCLAW_DIR/logs" "$PLIST_DIR" || fail "could not create required directories"
chmod 700 "$OPENCLAW_DIR" || fail "could not chmod 700 $OPENCLAW_DIR"

cat > "$WRAPPER" <<EOF_WRAPPER
#!/bin/zsh
set -euo pipefail

cd "$LOCAL_LLM_DIR"
source "$VENV_PATH/bin/activate"

MODEL="$MODEL"
HOST="$HOST"
PORT="$PORT"

exec mlx_lm.server \\
  --model "\$MODEL" \\
  --host "\$HOST" \\
  --port "\$PORT"
EOF_WRAPPER

chmod 700 "$WRAPPER" || fail "could not chmod 700 $WRAPPER"

cat > "$PLIST" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>$LABEL</string>

    <key>ProgramArguments</key>
    <array>
      <string>/bin/zsh</string>
      <string>-lc</string>
      <string>$WRAPPER</string>
    </array>

    <key>WorkingDirectory</key>
    <string>$LOCAL_LLM_DIR</string>

    <key>EnvironmentVariables</key>
    <dict>
      <key>PATH</key>
      <string>$VENV_PATH/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
      <key>PYTHONUNBUFFERED</key>
      <string>1</string>
    </dict>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>$LOG_OUT</string>

    <key>StandardErrorPath</key>
    <string>$LOG_ERR</string>
  </dict>
</plist>
EOF_PLIST

chmod 600 "$PLIST" || fail "could not chmod 600 $PLIST"

if grep -n '\$HOME' "$PLIST" >/dev/null 2>&1; then
  grep -n '\$HOME' "$PLIST"
  fail "plist still contains literal HOME placeholders"
fi
pass "plist contains absolute paths"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$PLIST" || fail "plist validation failed"
fi

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST" || fail "launchctl bootstrap failed; sign in to the macOS GUI as this runtime user if the GUI domain is unavailable"
launchctl kickstart -k "gui/$UID/$LABEL" || fail "launchctl kickstart failed"

sleep 5

if curl -fsS "http://$HOST:$PORT/v1/models" >/dev/null; then
  pass "MLX-LM server responds on http://$HOST:$PORT/v1/models"
else
  tail -n 80 "$LOG_OUT" 2>/dev/null || true
  tail -n 80 "$LOG_ERR" 2>/dev/null || true
  fail "MLX-LM server did not respond on http://$HOST:$PORT/v1/models"
fi

printf '\n== Installed files ==\n'
ls -l "$WRAPPER" "$PLIST" "$LOG_OUT" "$LOG_ERR" 2>/dev/null || true

printf '\n== launchctl summary ==\n'
launchctl print "gui/$UID/$LABEL" 2>/dev/null | sed -n '1,80p' || true

printf '\nRESULT: PASS\n'
