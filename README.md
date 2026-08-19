# Odoo in Claude — MCP server

Connects **Claude** to our **Odoo 18 Enterprise** instance (`rw-andersen.odoo.com`) so you
can drive ERP workflows — sales, CRM, projects, accounting/reconciliation — in plain
language, and pull live Odoo data into reports, meetings, and proposals.

It talks to Odoo over the standard **External XML-RPC API** — no Enterprise "AI" add-on,
nothing installed on the Odoo server. Claude acts **as you**: you sign in with your own
Odoo API key, so it can see and do exactly what your Odoo account can, and nothing more.
**Read-only by default.**

## Install

One line. Installs everything, asks for your Odoo login, registers the connector in both
Claude Desktop and Claude Code.

**macOS / Linux** — Terminal:
```bash
curl -fsSL https://raw.githubusercontent.com/irachrist1/odoo-claude/main/bootstrap.sh | bash
```

**Windows** — PowerShell:
```powershell
irm https://raw.githubusercontent.com/irachrist1/odoo-claude/main/bootstrap.ps1 | iex
```

Partway through it opens Odoo and asks for an API key. Generate one in 30 seconds:
avatar (top-right) → **My Profile** → **Account Security** → **New API Key** → name it
`claude` → copy → paste it back in the terminal. Then quit Claude completely and reopen it.

Nothing else is needed — the installer fetches `uv` and its own Python, and never asks for
admin rights. Non-technical Windows staff can use
[`WINDOWS_SETUP.md`](WINDOWS_SETUP.md) instead, which assumes no terminal experience.

## What Claude can do through it

A small set of model-agnostic tools lets Claude work across *any* Odoo app:

| Tool | Purpose |
|------|---------|
| `odoo_whoami` | Verify the connection / who Claude is acting as |
| `odoo_list_models` | Find the right model (e.g. `sale.order`, `crm.lead`) |
| `odoo_describe_model` | Inspect a model's fields before querying |
| `odoo_search` | Search & read records from any model (the workhorse) |
| `odoo_count` | Count matching records (totals, KPIs) |
| `odoo_read` | Read specific records by id |
| `odoo_name_search` | Resolve a name (e.g. "Acme Ltd") to a record id |
| `odoo_create` *(gated)* | Create a record — only if writes are enabled |
| `odoo_update` *(gated)* | Update records — only if writes are enabled |

## Verify

Ask Claude: *"Use odoo_whoami to confirm the Odoo connection."* Or from the repo:
```bash
uv run python test_connection.py
```
- ✅ "External API is enabled" → good to go.
- ❌ auth error → the email must be your Odoo login and the key must be pasted whole.
  Re-run the installer to try again.
- ❌ no Odoo tools in Claude → you reopened Claude without fully quitting it first.

## Example prompts

- "List Maj Andersen's open sales orders over 1,000 this quarter and total them."
- "Show CRM leads with no activity in 14 days and summarize them for a follow-up."
- "Pull this month's draft vendor bills and flag any without a purchase order."
- "How many leave days do I have left?"

Ask Claude to run `odoo_list_models` when you're not sure which Odoo model holds
something, then `odoo_describe_model` to see its real field names.

## Enabling writes

Writes (`odoo_create`, `odoo_update`) are **off** by default and refuse to run until
`ODOO_ENABLE_WRITES=true` is set in `.env` or the Claude config. Turn it on deliberately.
Your Odoo user permissions are the real guardrail — Claude cannot exceed them.

## Manual install

If you'd rather not pipe a script, clone and run the installer directly:
```bash
git clone https://github.com/irachrist1/odoo-claude.git
cd odoo-claude
./install.sh          # Windows: double-click Install.bat
```

## Security

No credentials are committed to this repo. Each person supplies their own API key, and
the installer writes it straight into the local Claude config — never to a file in the
repo, and never back to git. Odoo permissions and the audit trail stay per-person.

An API key is password-equivalent: don't paste yours into chat, tickets, or a shared
document. Revoke it under **My Profile → Account Security** if it ever leaks.
