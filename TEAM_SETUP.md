# Odoo in Claude — setup

Connects Claude to our Odoo (`rw-andersen.odoo.com`) using **your own** Odoo login, so you
see your own data and permissions.

## One-line install

**macOS / Linux** — Terminal:
```bash
curl -fsSL https://raw.githubusercontent.com/irachrist1/odoo-claude/main/bootstrap.sh | bash
```

**Windows** — PowerShell:
```powershell
irm https://raw.githubusercontent.com/irachrist1/odoo-claude/main/bootstrap.ps1 | iex
```

It installs everything it needs (`uv` plus its own Python), no admin rights.

## The one thing it asks you for

Midway it opens Odoo in your browser and waits for an API key:

1. Click your photo (top-right) → **My Profile**
2. Open the **Account Security** tab
3. **New API Key**, name it `claude`, copy it
4. Paste it in the terminal, along with your Odoo email

The key goes straight into Claude's config on your machine. It is never written into the
downloaded folder and never leaves your laptop.

## Then

**Quit Claude completely** — not just the window — and reopen it. Ask:
*"Use odoo_whoami to confirm the Odoo connection."*

Both Claude Desktop and Claude Code are registered, so it works in either.

## Windows staff who don't use a terminal

Send them **[`WINDOWS_SETUP.md`](WINDOWS_SETUP.md)** — same result, written for people who
have never opened PowerShell. Short version: download the folder, double-click
**`Install.bat`**, restart Claude Desktop.

## What you can ask

The tools reach any Odoo app, not a fixed list of screens.

- "List my open sales orders this month and total them."
- "Summarize CRM leads with no activity in 2 weeks."
- "Show unpaid customer invoices over 30 days."
- "How many leave days do I have left?"

Ask Claude to run `odoo_list_models` when you're not sure which Odoo model holds
something, then `odoo_describe_model` to see its real field names.

## Notes

- **Read-only by default.** `odoo_create` / `odoo_update` refuse to run until
  `ODOO_ENABLE_WRITES=true` in `.env`.
- Sign-in failing? Check the email is your Odoo login (not a personal address) and that
  the key was copied whole. Three attempts, then re-run the installer.
- Claude shows no Odoo tools? You reopened it without fully quitting first.
