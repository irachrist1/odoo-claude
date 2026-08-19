#!/usr/bin/env bash
# One-command install for macOS and Linux. Counterpart to bootstrap.ps1.
#
#   curl -fsSL https://raw.githubusercontent.com/irachrist1/odoo-claude/main/bootstrap.sh | bash
#
set -euo pipefail

ZIP_URL="${ODOO_MCP_ZIP:-https://codeload.github.com/irachrist1/odoo-claude/zip/refs/heads/main}"
DEST="${ODOO_MCP_DEST:-$HOME/.local/share/odoo-claude}"

say()  { printf '\033[36m-> %s\033[0m\n' "$1"; }
ok()   { printf '\033[32mOK %s\033[0m\n' "$1"; }
die()  { printf '\033[31m!! %s\033[0m\n' "$1" >&2
         printf '\033[90mNothing was broken. If you are stuck, send Christian this message.\033[0m\n' >&2
         exit 1; }

echo
echo "===  Odoo in Claude - installer  ==="
echo

# Checked by shape, not by comparing against the placeholder text: the placeholder
# also appears in the assignment above, so a find-and-replace of it would rewrite
# both spots and make a sentinel comparison match forever.
case "$ZIP_URL" in
  http://*|https://*) ;;
  *) die "This installer link hasn't been configured yet. Ask Christian for the correct command." ;;
esac

command -v curl >/dev/null 2>&1 || die "curl is required but not installed."
command -v unzip >/dev/null 2>&1 || die "unzip is required but not installed."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "Downloading..."
curl -fsSL "$ZIP_URL" -o "$TMP/bundle.zip" || die "Download failed. Check your internet connection, or ask Christian whether the link has changed."

say "Unpacking..."
unzip -q "$TMP/bundle.zip" -d "$TMP/x" || die "The downloaded file isn't a valid archive. Ask Christian to check the install link."

# Archive hosts wrap everything in a single top-level folder; step into it.
ROOT="$TMP/x"
if [ "$(find "$TMP/x" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ]; then
  ONLY="$(find "$TMP/x" -mindepth 1 -maxdepth 1)"
  [ -d "$ONLY" ] && ROOT="$ONLY"
fi
[ -f "$ROOT/install.sh" ] || die "The download doesn't look like the Odoo connector. Ask Christian to check the install link."

say "Installing to $DEST"
rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
cp -R "$ROOT" "$DEST"
chmod +x "$DEST"/*.sh 2>/dev/null || true

# Under 'curl | bash' our stdin IS the script stream, already at EOF, so any prompt
# further down would read nothing. Hand the installer the real terminal instead.
# Test by actually opening it: /dev/tty passes -r even where it can't be opened.
if (exec 3< /dev/tty) 2>/dev/null; then
  exec bash "$DEST/install.sh" < /dev/tty
else
  exec bash "$DEST/install.sh"
fi
