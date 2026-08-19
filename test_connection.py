"""Standalone connection test — no MCP, no Claude. Run this first to confirm
your credentials and that your Odoo plan exposes the external API.

    cp .env.example .env   # then fill in ODOO_USERNAME and ODOO_API_KEY
    uv run python test_connection.py
"""

from __future__ import annotations

import os
import sys

from dotenv import load_dotenv

from odoo_mcp.client import OdooClient, OdooError

load_dotenv()


def main() -> int:
    required = ["ODOO_URL", "ODOO_DB", "ODOO_USERNAME", "ODOO_API_KEY"]
    missing = [k for k in required if not os.environ.get(k)]
    if missing:
        print(f"❌ Missing in .env: {', '.join(missing)}")
        return 1

    client = OdooClient(
        os.environ["ODOO_URL"],
        os.environ["ODOO_DB"],
        os.environ["ODOO_USERNAME"],
        os.environ["ODOO_API_KEY"],
    )

    try:
        print(f"→ Server version: {client.version().get('server_version')}")
        print(f"→ Authenticated uid: {client.uid}")
        user = client.read("res.users", [client.uid], ["name", "login", "company_id"])[0]
        print(f"✅ Logged in as: {user['name']} <{user['login']}>")
        print(f"   Company: {(user.get('company_id') or [None, '-'])[1]}")
        print(f"   Partners in database: {client.search_count('res.partner')}")
        print(f"   Sales orders: {client.search_count('sale.order')}")
        print("\n✅ External API is enabled — you're ready to connect Claude.")
        return 0
    except OdooError as exc:
        print(f"❌ {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
