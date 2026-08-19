"""MCP server exposing Odoo to Claude.

Design notes:
- Model-agnostic by design. A small set of ORM-level tools (search, read,
  describe, count, name_search) lets Claude drive ANY Odoo app — Sales, CRM,
  Project, Accounting — instead of needing a bespoke tool per screen.
- Read-only by default. create/update only run when ODOO_ENABLE_WRITES=true.
- Complex arguments (domains, value dicts) are passed as JSON strings to keep the
  tool schemas simple and unambiguous for the model.
"""

from __future__ import annotations

import json
import os
from typing import Any

from dotenv import load_dotenv
from mcp.server.fastmcp import FastMCP

from .client import OdooClient, OdooError

load_dotenv()

mcp = FastMCP("odoo")


def _writes_enabled() -> bool:
    return os.environ.get("ODOO_ENABLE_WRITES", "false").strip().lower() in ("1", "true", "yes", "on")


def _client() -> OdooClient:
    cfg = {
        "ODOO_URL": os.environ.get("ODOO_URL"),
        "ODOO_DB": os.environ.get("ODOO_DB"),
        "ODOO_USERNAME": os.environ.get("ODOO_USERNAME"),
        "ODOO_API_KEY": os.environ.get("ODOO_API_KEY"),
    }
    missing = [k for k, v in cfg.items() if not v]
    if missing:
        raise OdooError(
            f"Missing configuration: {', '.join(missing)}. "
            "Set these in your .env file or in the Claude MCP server config."
        )
    return OdooClient(cfg["ODOO_URL"], cfg["ODOO_DB"], cfg["ODOO_USERNAME"], cfg["ODOO_API_KEY"])


def _dump(obj: Any) -> str:
    return json.dumps(obj, indent=2, default=str, ensure_ascii=False)


def _parse_json(raw: str, name: str, expect: type) -> Any:
    raw = (raw or "").strip()
    if not raw:
        return expect()
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise OdooError(f"`{name}` must be valid JSON. {exc}") from exc
    if not isinstance(value, expect):
        raise OdooError(f"`{name}` must be a JSON {expect.__name__}, got {type(value).__name__}.")
    return value


# --- read tools -------------------------------------------------------------


@mcp.tool()
def odoo_whoami() -> str:
    """Verify the Odoo connection. Returns server version, the logged-in user,
    their company, and whether write access is enabled. Run this first."""
    try:
        client = _client()
        version = client.version().get("server_version", "unknown")
        user = client.read("res.users", [client.uid], ["name", "login", "company_id", "lang", "tz"])[0]
        return _dump(
            {
                "connected": True,
                "odoo_url": client.url,
                "server_version": version,
                "user": user.get("name"),
                "login": user.get("login"),
                "company": (user.get("company_id") or [None, None])[1],
                "writes_enabled": _writes_enabled(),
            }
        )
    except OdooError as exc:
        return f"Connection failed: {exc}"


@mcp.tool()
def odoo_list_models(keyword: str = "", limit: int = 40) -> str:
    """Find Odoo model technical names by keyword (e.g. 'sale', 'invoice',
    'project', 'lead'). Use this to discover which model a request maps to,
    then pass that technical name to odoo_search."""
    try:
        client = _client()
        domain = []
        if keyword.strip():
            domain = ["|", ("model", "ilike", keyword), ("name", "ilike", keyword)]
        records = client.search_read(
            "ir.model", domain, fields=["model", "name"], limit=limit, order="model"
        )
        return _dump(records)
    except OdooError as exc:
        return f"Error: {exc}"


@mcp.tool()
def odoo_describe_model(model: str) -> str:
    """List the fields of a model (name, label, type, relation, selection
    options). Use before filtering or writing so you know real field names."""
    try:
        client = _client()
        fields = client.fields_get(model)
        slim = {
            name: {k: meta.get(k) for k in ("string", "type", "relation", "selection", "required") if meta.get(k) not in (None, [], False)}
            for name, meta in sorted(fields.items())
        }
        return _dump(slim)
    except OdooError as exc:
        return f"Error: {exc}"


@mcp.tool()
def odoo_search(
    model: str,
    domain: str = "[]",
    fields: str = "[]",
    limit: int = 50,
    order: str = "",
) -> str:
    """Search and read records from any Odoo model — the main workhorse.

    Args:
        model: technical name, e.g. 'sale.order', 'crm.lead', 'project.task',
            'account.move', 'res.partner'.
        domain: Odoo domain as a JSON array of [field, operator, value] triples,
            e.g. '[["state","=","sale"],["amount_total",">",1000]]'. '[]' = all.
        fields: JSON array of field names to return, e.g. '["name","amount_total"]'.
            '[]' returns a default set.
        limit: max records (default 50).
        order: optional sort, e.g. 'date_order desc'.
    """
    try:
        client = _client()
        parsed_domain = _parse_json(domain, "domain", list)
        parsed_fields = _parse_json(fields, "fields", list)
        records = client.search_read(
            model,
            domain=parsed_domain,
            fields=parsed_fields or None,
            limit=limit,
            order=order or None,
        )
        return _dump({"model": model, "count_returned": len(records), "records": records})
    except OdooError as exc:
        return f"Error: {exc}"


@mcp.tool()
def odoo_count(model: str, domain: str = "[]") -> str:
    """Count records matching a domain without fetching them. Cheap for totals,
    e.g. how many open invoices or won leads this month."""
    try:
        client = _client()
        parsed_domain = _parse_json(domain, "domain", list)
        total = client.search_count(model, parsed_domain)
        return _dump({"model": model, "count": total})
    except OdooError as exc:
        return f"Error: {exc}"


@mcp.tool()
def odoo_read(model: str, ids: str, fields: str = "[]") -> str:
    """Read specific records by id. `ids` is a JSON array like '[12, 15]'."""
    try:
        client = _client()
        parsed_ids = _parse_json(ids, "ids", list)
        parsed_fields = _parse_json(fields, "fields", list)
        records = client.read(model, parsed_ids, parsed_fields or None)
        return _dump(records)
    except OdooError as exc:
        return f"Error: {exc}"


@mcp.tool()
def odoo_name_search(model: str, name: str, limit: int = 10) -> str:
    """Resolve a human label to record id(s), e.g. find the partner id for
    'Acme Ltd' before linking it. Returns [id, display_name] pairs."""
    try:
        client = _client()
        return _dump(client.name_search(model, name, limit=limit))
    except OdooError as exc:
        return f"Error: {exc}"


# --- write tools (gated) ----------------------------------------------------


@mcp.tool()
def odoo_create(model: str, values: str) -> str:
    """Create a record. `values` is a JSON object of field->value, e.g.
    '{"name":"New lead","partner_id":42}'. Disabled unless ODOO_ENABLE_WRITES=true."""
    if not _writes_enabled():
        return ("Writes are disabled. Set ODOO_ENABLE_WRITES=true and restart the "
                "server to allow create/update. (Read-only is the default for safety.)")
    try:
        client = _client()
        parsed = _parse_json(values, "values", dict)
        new_id = client.create(model, parsed)
        return _dump({"created": True, "model": model, "id": new_id})
    except OdooError as exc:
        return f"Error: {exc}"


@mcp.tool()
def odoo_update(model: str, ids: str, values: str) -> str:
    """Update records. `ids` is a JSON array '[12]'; `values` a JSON object of
    field->value. Disabled unless ODOO_ENABLE_WRITES=true."""
    if not _writes_enabled():
        return ("Writes are disabled. Set ODOO_ENABLE_WRITES=true and restart the "
                "server to allow create/update. (Read-only is the default for safety.)")
    try:
        client = _client()
        parsed_ids = _parse_json(ids, "ids", list)
        parsed_values = _parse_json(values, "values", dict)
        ok = client.write(model, parsed_ids, parsed_values)
        return _dump({"updated": bool(ok), "model": model, "ids": parsed_ids})
    except OdooError as exc:
        return f"Error: {exc}"


def main() -> None:
    transport = os.environ.get("MCP_TRANSPORT", "stdio").strip().lower()
    if transport in ("http", "streamable-http"):
        mcp.run(transport="streamable-http")
    else:
        mcp.run()


if __name__ == "__main__":
    main()
