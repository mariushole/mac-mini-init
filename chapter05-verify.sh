#!/usr/bin/env bash
set -u

MODEL="${MODEL:-mlx-community/Qwen3.5-9B-OptiQ-4bit}"
EXPECTED_VENV="${HOME}/local-llm/.venv"
FAILURES=0
WARNINGS=0

section() {
  printf '\n== %s ==\n' "$1"
}

pass() {
  printf 'PASS: %s\n' "$1"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf 'WARN: %s\n' "$1"
}

fail() {
  FAILURES=$((FAILURES + 1))
  printf 'FAIL: %s\n' "$1"
}

run_value() {
  printf '%s: %s\n' "$1" "$2"
}

section "Chapter 05 Local LLM Verification"
run_value "Model" "$MODEL"
run_value "User" "$(whoami)"
run_value "Home" "$HOME"

section "User and Shell"
GROUPS_OUT="$(id -Gn 2>/dev/null || true)"
run_value "Groups" "$GROUPS_OUT"
case " $GROUPS_OUT " in
  *" admin "*) fail "runtime user is in the admin group" ;;
  *) pass "runtime user is not in the admin group" ;;
esac

section "Virtual Environment"
if [ "${VIRTUAL_ENV:-}" = "$EXPECTED_VENV" ]; then
  pass "active venv is $EXPECTED_VENV"
else
  fail "active venv is '${VIRTUAL_ENV:-unset}', expected '$EXPECTED_VENV'"
fi

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python)"
  run_value "python" "$PYTHON_BIN"
else
  fail "python is not on PATH"
  PYTHON_BIN=""
fi

if command -v mlx_lm.generate >/dev/null 2>&1; then
  run_value "mlx_lm.generate" "$(command -v mlx_lm.generate)"
else
  fail "mlx_lm.generate is not on PATH"
fi

section "Python and SSL"
if [ -n "$PYTHON_BIN" ]; then
  python - <<'PY'
import ssl
import sys

print("python_version:", sys.version.split()[0])
print("python_executable:", sys.executable)
print("ssl:", ssl.OPENSSL_VERSION)
print("version_ok:", sys.version_info >= (3, 11))
print("openssl_ok:", "LibreSSL" not in ssl.OPENSSL_VERSION)
PY

  if python - <<'PY'
import sys
raise SystemExit(0 if sys.version_info >= (3, 11) else 1)
PY
  then
    pass "Python version is acceptable"
  else
    fail "Python is too old; rebuild venv with Python 3.12"
  fi

  if python - <<'PY'
import ssl
raise SystemExit(0 if "LibreSSL" not in ssl.OPENSSL_VERSION else 1)
PY
  then
    pass "SSL backend is not LibreSSL"
  else
    fail "SSL backend is LibreSSL; rebuild venv with Python 3.12"
  fi
fi

section "MLX-LM"
if python -c "import mlx_lm" >/dev/null 2>&1; then
  pass "mlx_lm imports"
  python -m pip show mlx-lm 2>/dev/null | sed -n '1,8p'
else
  fail "mlx_lm import failed"
fi

section "Hugging Face Model Metadata"
if python - "$MODEL" <<'PY'
import sys
from huggingface_hub import model_info

model_id = sys.argv[1]
info = model_info(model_id)
print("model_id:", info.modelId)
print("sha:", info.sha)
print("tags:", ", ".join(info.tags or []))
PY
then
  pass "model metadata is reachable"
else
  warn "model metadata check failed; check DNS/internet or Hugging Face availability"
fi

section "Local Model Cache"
if python - "$MODEL" <<'PY'
import sys
from huggingface_hub import snapshot_download

model_id = sys.argv[1]
path = snapshot_download(repo_id=model_id, local_files_only=True)
print("cached_snapshot:", path)
PY
then
  pass "model snapshot is present in local Hugging Face cache"
else
  warn "model snapshot is not fully cached yet; generation may download files"
fi

section "Disk and Memory"
df -h / || true
du -sh "${HF_HOME:-$HOME/.cache/huggingface}" 2>/dev/null || warn "Hugging Face cache path not found"
du -sh "$HOME/local-llm" 2>/dev/null || warn "~/local-llm not found"
if command -v vm_stat >/dev/null 2>&1; then
  vm_stat | sed -n '1,8p'
else
  warn "vm_stat is unavailable on this host"
fi

section "Local Generation Smoke Test"
if [ "$FAILURES" -ne 0 ]; then
  warn "skipping generation because earlier hard checks failed"
elif mlx_lm.generate --model "$MODEL" --prompt "Reply with exactly: local model ok" --max-tokens 20; then
  pass "local generation command completed"
else
  fail "local generation command failed"
fi

section "Result"
if [ "$FAILURES" -eq 0 ]; then
  if [ "$WARNINGS" -eq 0 ]; then
    printf 'RESULT: PASS\n'
  else
    printf 'RESULT: PASS with %s warning(s)\n' "$WARNINGS"
  fi
  exit 0
fi

printf 'RESULT: FAIL with %s failure(s) and %s warning(s)\n' "$FAILURES" "$WARNINGS"
exit 1
