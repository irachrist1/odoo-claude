# Connecting Claude to Odoo — Windows

Takes about two minutes. You don't need to install anything first, and you don't need
admin rights. Claude gets **read-only** access — it can't change data in Odoo.

You sign in with your **own** Odoo account, so Claude sees your data and your permissions.

---

## The easy way: one command

Press the **Windows key**, type `powershell`, press Enter, then paste this and press Enter:

```powershell
irm https://raw.githubusercontent.com/irachrist1/odoo-claude/main/bootstrap.ps1 | iex
```

## Or: double-click

1. Save the **`odoo-claude`** folder somewhere you'll keep it — Documents is fine. If you
   got it as a `.zip`, right-click it → **Extract All** first.
   *(Don't skip extracting. Running it from inside the zip won't work.)*
2. Open the folder and double-click **`Install.bat`**.
3. If Windows shows a blue **"Windows protected your PC"** box, click **More info** →
   **Run anyway**. That warning just means the file came from the internet.

---

## The part where it asks you something

The installer opens Odoo in your browser and waits for an **API key** — a password just
for Claude, which you can revoke any time:

1. Click your photo (top-right) → **My Profile**
2. Open the **Account Security** tab
3. Click **New API Key**, name it `claude`, and copy it
4. Back in the black window, type your Odoo email, then paste the key and press Enter
   *(the key stays invisible as you paste — that's normal)*

Then:

5. When it says **Done**, **quit Claude Desktop completely** — right-click its icon near
   the clock (bottom-right) → **Quit**. Closing the window isn't enough.
6. Open Claude Desktop again.

---

## Check it worked

In Claude, ask:

> Use odoo_whoami to confirm the Odoo connection.

It should reply with your Odoo account. Now you can ask things like:

- *"How many open sales orders do we have this month?"*
- *"Show unpaid customer invoices over 30 days old."*
- *"How many leave days do I have left?"*

If Claude says it has no Odoo tools, it wasn't fully restarted — quit it from the taskbar
icon (step 5) and open it again.

---

## If something goes wrong

Nothing the installer does is permanent or risky — you can close the window and re-run it
as many times as you like.

| What you see | What to do |
|---|---|
| "Windows protected your PC" | **More info** → **Run anyway** |
| "running scripts is disabled on this system" | Handled automatically — if you still hit it you're on an older copy, so ask Christian for the current link |
| Window flashes and vanishes | Right-click `install.ps1` → **Run with PowerShell** |
| "couldn't sign in to Odoo" | Use your Odoo login email, and make sure the whole key was copied. Three tries, then just re-run it |
| "missing its .env file" | Your copy is incomplete — re-run the one-command install above |
| Claude has no Odoo tools | Quit Claude from the taskbar icon, not the window, then reopen |

Still stuck? Take a photo of the black window and send it to Christian.

---

## About your API key

It's password-equivalent for Odoo, so don't paste it into chat, email, or a shared
document. The installer puts it straight into Claude's settings on your own machine —
it isn't stored in the downloaded folder. Revoke it any time under
**My Profile → Account Security**.
