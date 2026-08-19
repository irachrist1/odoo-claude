#!/usr/bin/env bash
# Sets up the Odoo connector using the person's OWN Odoo login.
# Credentials go straight into Claude's config and are never written to disk here.
#
# ODOO_FALLBACK_OK=1 means the caller has a shared account to fall back on, so
# skipping or failing exits 2 instead of being fatal.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$REPO_DIR/.env"
ODOO_URL="${ODOO_URL:-https://rw-andersen.odoo.com}"
ODOO_DB="${ODOO_DB:-rw-andersen}"
FALLBACK="${ODOO_FALLBACK_OK:-}"

# Credentials can arrive in the environment instead of by typing. That is the only way
# this works with no terminal attached — an AI agent's shell, CI, or `curl | bash` where
# /dev/tty can't be opened — because `read` there returns EOF instantly and the prompt
# loop burns its three attempts on empty input.
PRESET_USERNAME="${ODOO_USERNAME:-}"
PRESET_API_KEY="${ODOO_API_KEY:-}"

writes_on() { [ -f "$ENV_FILE" ] && grep -qiE '^ODOO_ENABLE_WRITES=(1|true|yes|on)[[:space:]]*$' "$ENV_FILE"; }

register_and_finish() {
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
  exit 0
}

# When called directly (no fallback available) we own the whole install, banner included.
if [ -z "$FALLBACK" ]; then
  echo
  echo "===  Odoo in Claude - Maj Andersen (RW) Ltd  ==="
  echo

  if ! command -v uv >/dev/null 2>&1; then
    if [ -x "$HOME/.local/bin/uv" ]; then
      export PATH="$HOME/.local/bin:$PATH"
    else
      echo "→ Installing uv (one-time, ~20 seconds)…"
      curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || {
        echo "❌ Could not install uv. Run this, then try again:"
        echo "     curl -LsSf https://astral.sh/uv/install.sh | sh"
        exit 1
      }
      export PATH="$HOME/.local/bin:$PATH"
    fi
  fi

  echo "→ Installing dependencies (first run downloads Python, be patient)…"
  ( cd "$REPO_DIR" && uv sync >/dev/null )
fi

if [ -n "$PRESET_USERNAME" ] && [ -n "$PRESET_API_KEY" ]; then
  echo
  echo "→ Using the Odoo credentials from the environment…"
  export ODOO_USERNAME="$PRESET_USERNAME" ODOO_API_KEY="$PRESET_API_KEY" ODOO_URL ODOO_DB
  if ( cd "$REPO_DIR" && uv run python test_connection.py ); then
    register_and_finish
  fi
  echo
  echo "❌ Those credentials didn't work. Check ODOO_USERNAME is the Odoo login email and"
  echo "   that ODOO_API_KEY is the full key from My Profile → Account Security."
  if [ -n "$FALLBACK" ]; then
    exit 2
  fi
  exit 1
fi

echo
echo "Sign in with your own Odoo account so Claude sees your data."
echo
echo "Opening Odoo in your browser. Once it loads:"
echo "  1. Click your photo (top-right)  →  My Profile"
echo "  2. Open the  Account Security  tab"
echo "  3. Click  New API Key , name it 'claude', and copy the key"
echo
# ODOO_MCP_NO_BROWSER=1 for automated runs: 'open' escapes any HOME sandbox and
# launches the real browser on the real desktop.
if [ "${ODOO_MCP_NO_BROWSER:-}" = "1" ]; then
  echo "  (Open $ODOO_URL yourself)"
else
  ( open "$ODOO_URL" 2>/dev/null || xdg-open "$ODOO_URL" 2>/dev/null ) >/dev/null 2>&1 || \
    echo "  (Open $ODOO_URL yourself)"
fi

export ODOO_URL ODOO_DB

if [ -n "$FALLBACK" ]; then
  skip_hint=" (or press Enter to use the shared company account)"
else
  skip_hint=""
fi

ok=0
for attempt in 1 2 3; do
  printf 'Your Odoo email%s: ' "$skip_hint"
  read -r ODOO_USERNAME || ODOO_USERNAME=""

  if [ -z "${ODOO_USERNAME:-}" ] && [ -n "$FALLBACK" ]; then
    exit 2
  fi

  printf 'Paste your API key (hidden): '
  read -r -s ODOO_API_KEY || ODOO_API_KEY=""
  echo; echo

  if [ -z "${ODOO_USERNAME:-}" ] || [ -z "${ODOO_API_KEY:-}" ]; then
    echo "Both are needed - let's try again."; echo
    continue
  fi

  export ODOO_USERNAME ODOO_API_KEY
  echo "→ Checking your login…"
  if ( cd "$REPO_DIR" && uv run python test_connection.py ); then
    ok=1
    break
  fi
  if [ "$attempt" -lt 3 ]; then
    echo
    echo "That didn't work. Check the email is your Odoo login and that the key was"
    echo "copied completely, then try again ($((3 - attempt)) left)."
    echo
  fi
done

if [ "$ok" -ne 1 ]; then
  echo
  if [ -n "$FALLBACK" ]; then
    exit 2
  fi
  echo "❌ Couldn't sign in to Odoo. Ask Christian to check your Odoo account is active."
  exit 1
fi

register_and_finish
