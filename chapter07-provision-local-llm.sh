#!/usr/bin/env bash
set -u

MODEL="${MODEL:-mlx-community/Qwen3.5-9B-OptiQ-4bit}"
LOCAL_LLM_DIR="${LOCAL_LLM_DIR:-$HOME/local-llm}"
VENV_PATH="${VENV_PATH:-$LOCAL_LLM_DIR/.venv}"
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
ENV_FILE="$OPENCLAW_DIR/.env"
RECORD_FILE="$OPENCLAW_DIR/local-llm-record.txt"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

info() {
  printf 'INFO: %s\n' "$1"
}

pass() {
  printf 'PASS: %s\n' "$1"
}

printf '== Chapter 07 local LLM handoff provision ==\n'
printf 'Model: %s\n' "$MODEL"
printf 'Runtime user: %s\n' "$(whoami)"

GROUPS_OUT="$(id -Gn 2>/dev/null || true)"
case " $GROUPS_OUT " in
  *" admin "*) fail "runtime user is in the admin group; run as the non-admin OpenClaw runtime user" ;;
  *) pass "runtime user is not in the admin group" ;;
esac

[ -d "$VENV_PATH" ] || fail "venv not found at $VENV_PATH; complete Chapter 05 first"

# shellcheck disable=SC1091
. "$VENV_PATH/bin/activate"

PYTHON_EXE="$(command -v python || true)"
[ -n "$PYTHON_EXE" ] || fail "python not found after activating $VENV_PATH"

PYTHON_VERSION="$(python --version 2>&1)"
SSL_LIBRARY="$(python -c 'import ssl; print(ssl.OPENSSL_VERSION)')"

case "$PYTHON_VERSION" in
  "Python 3.11"*|"Python 3.12"*|"Python 3.13"*) pass "Python version is acceptable: $PYTHON_VERSION" ;;
  *) fail "Python version is not acceptable for this guide: $PYTHON_VERSION" ;;
esac

case "$SSL_LIBRARY" in
  *LibreSSL*) fail "SSL backend is LibreSSL; rebuild Chapter 05 venv with Python 3.12 and OpenSSL" ;;
  *) pass "SSL backend is acceptable: $SSL_LIBRARY" ;;
esac

python -c "import mlx_lm" >/dev/null 2>&1 || fail "mlx_lm import failed; complete Chapter 05 first"
MLX_LM_VERSION="$(python -m pip show mlx-lm 2>/dev/null | awk -F': ' '/^Version:/ {print $2}')"
[ -n "$MLX_LM_VERSION" ] || MLX_LM_VERSION="unknown"

HF_CACHE="${HF_HOME:-$HOME/.cache/huggingface}"

MODEL_SHA="$(python - "$MODEL" <<'PY'
import sys
from huggingface_hub import model_info

info = model_info(sys.argv[1])
print(info.sha)
PY
)" || fail "could not read Hugging Face metadata for $MODEL"

mkdir -p "$OPENCLAW_DIR" || fail "could not create $OPENCLAW_DIR"
chmod 700 "$OPENCLAW_DIR" || fail "could not chmod 700 $OPENCLAW_DIR"

umask 077
cat > "$RECORD_FILE" <<EOF_RECORD
Local LLM runtime: MLX-LM
Runtime version: $MLX_LM_VERSION
Python executable: $PYTHON_EXE
Python version: $PYTHON_VERSION
SSL library: $SSL_LIBRARY
Virtual environment path: $VENV_PATH
Hugging Face cache path: $HF_CACHE
Model family: Qwen 3.5 9B
Exact model ID: $MODEL
Model SHA / revision: $MODEL_SHA
Provider path selected:
Notes: Local MLX-LM CLI inference is verified by Chapter 05. This record is not an OpenClaw provider configuration.
EOF_RECORD
chmod 600 "$RECORD_FILE" || fail "could not chmod 600 $RECORD_FILE"

if [ ! -e "$ENV_FILE" ]; then
  cat > "$ENV_FILE" <<'EOF_ENV'
# OpenClaw provider secrets.
# Keep this file mode 600 and never commit it to Git.
#
# Local MLX-LM CLI inference from Chapter 05 does not require an API key here.
# Do not invent MLX-LM .env variables unless OpenClaw's current provider docs require them.
#
# Cloud provider examples, only if used:
# OPENAI_API_KEY=replace-me
# ANTHROPIC_API_KEY=replace-me
EOF_ENV
  chmod 600 "$ENV_FILE" || fail "could not chmod 600 $ENV_FILE"
  pass "created locked provider secrets placeholder: $ENV_FILE"
else
  chmod 600 "$ENV_FILE" || fail "could not chmod 600 $ENV_FILE"
  pass "preserved existing provider secrets file and enforced mode 600: $ENV_FILE"
fi

printf '\n== Provisioned files ==\n'
ls -l "$RECORD_FILE" "$ENV_FILE"

printf '\n== Local LLM record ==\n'
cat "$RECORD_FILE"

printf '\n== Next step ==\n'
printf 'Choose the actual OpenClaw provider path supported by your installed OpenClaw version.\n'
printf 'If you only have MLX-LM CLI inference, there may be no provider secret to add yet.\n'
printf 'RESULT: PASS\n'
