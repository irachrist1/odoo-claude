#!/usr/bin/env bash
# Sets up the Odoo connector for Claude Desktop.
#
# Identity is decided by .env:
#   no ODOO_API_KEY            -> ask the person for their own Odoo login
#   ODOO_PREFER_PERSONAL=true  -> ask, but fall back to the bundled key if that fails
#   otherwise                  -> use the bundled key, ask nothing
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$REPO_DIR/.env"

has_key() { [ -f "$ENV_FILE" ] && grep -qE '^ODOO_API_KEY=.+$' "$ENV_FILE"; }
prefer_personal() { [ -f "$ENV_FILE" ] && grep -qiE '^ODOO_PREFER_PERSONAL=(1|true|yes|on)[[:space:]]*$' "$ENV_FILE"; }
writes_on() { [ -f "$ENV_FILE" ] && grep -qiE '^ODOO_ENABLE_WRITES=(1|true|yes|on)[[:space:]]*$' "$ENV_FILE"; }

# Hand over before printing a banner, so the personal installer doesn't print a second one.
if ! has_key; then
  exec bash "$REPO_DIR/install-personal.sh"
fi

echo
echo "===  Odoo in Claude - Maj Andersen (RW) Ltd  ==="
echo

# uv brings its own Python, so it's the only prerequisite — install it if absent.
if ! command -v uv >/dev/null 2>&1; then
  if [ -x "$HOME/.local/bin/uv" ]; then
    export PATH="$HOME/.local/bin:$PATH"
  else
    echo "→ Installing uv (one-time, ~20 seconds)…"
    curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || {
      echo "❌ Could not install uv automatically. Run this, then try again:"
      echo "     curl -LsSf https://astral.sh/uv/install.sh | sh"
      exit 1
    }
    export PATH="$HOME/.local/bin:$PATH"
    command -v uv >/dev/null 2>&1 || {
      echo "❌ uv installed but isn't on PATH. Close this window, open a new one, and re-run."
      exit 1
    }
  fi
fi

echo "→ Installing dependencies (first run downloads Python, be patient)…"
( cd "$REPO_DIR" && uv sync >/dev/null )

# Try the person's own login first when asked to, but never dead-end on it: exit 2
# from the personal installer means "couldn't sign in", and we continue below with
# the bundled account rather than leaving them with nothing.
if prefer_personal; then
  set +e
  ODOO_FALLBACK_OK=1 bash "$REPO_DIR/install-personal.sh"
  personal_rc=$?
  set -e
  if [ "$personal_rc" -eq 0 ]; then
    exit 0
  elif [ "$personal_rc" -ne 2 ]; then
    exit "$personal_rc"
  fi
  echo
  echo "→ Setting up with the shared company account instead…"
  echo
fi

echo "→ Testing the connection…"
if ! ( cd "$REPO_DIR" && uv run python test_connection.py ); then
  echo
  echo "❌ Connection test failed. The bundled key may have been rotated —"
  echo "   ask Christian for a refreshed link."
  exit 1
fi

echo
echo "→ Registering the connector in Claude Desktop…"
( cd "$REPO_DIR" && uv run python setup_claude.py )

echo
echo "→ Checking Claude Desktop can start it…"
if ! ( cd "$REPO_DIR" && uv run python verify_connector.py ); then
  echo
  echo "❌ The connector was registered but wouldn't start. Send Christian this output."
  exit 1
fi

echo
echo "✅ Done. Quit Claude Desktop completely, reopen it, then ask it about Odoo."
if writes_on; then
  echo "   ⚠️  WRITES ARE ENABLED — Claude can create and change real Odoo records."
else
  echo "   Claude can read Odoo but not change anything."
fi
