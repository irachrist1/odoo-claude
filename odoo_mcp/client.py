"""Thin, dependency-free wrapper around Odoo's External XML-RPC API.

Works on Odoo 14-18 (and 19, which also adds JSON-2). Authentication uses an
API key in place of the password, so the real account password is never stored.
"""

from __future__ import annotations

import xmlrpc.client
from functools import cached_property
from typing import Any


class OdooError(Exception):
    """Raised for connection, auth, or ORM-level failures, with a readable message."""


class OdooClient:
    def __init__(self, url: str, db: str, username: str, api_key: str):
        self.url = url.rstrip("/")
        self.db = db
        self.username = username
        self.api_key = api_key
        self._uid: int | None = None

    @cached_property
    def _common(self) -> xmlrpc.client.ServerProxy:
        return xmlrpc.client.ServerProxy(f"{self.url}/xmlrpc/2/common", allow_none=True)

    @cached_property
    def _object(self) -> xmlrpc.client.ServerProxy:
        return xmlrpc.client.ServerProxy(f"{self.url}/xmlrpc/2/object", allow_none=True)

    def version(self) -> dict[str, Any]:
        """Unauthenticated server version handshake — useful as a reachability check."""
        try:
            return self._common.version()
        except Exception as exc:  # noqa: BLE001 - surface any transport error cleanly
            raise OdooError(f"Could not reach Odoo at {self.url}: {exc}") from exc

    @property
    def uid(self) -> int:
        """Authenticate once and cache the user id."""
        if self._uid is None:
            try:
                uid = self._common.authenticate(self.db, self.username, self.api_key, {})
            except Exception as exc:  # noqa: BLE001
                raise OdooError(f"Could not reach Odoo at {self.url}: {exc}") from exc
            if not uid:
                raise OdooError(
                    "Authentication failed. Check ODOO_DB, ODOO_USERNAME and ODOO_API_KEY. "
                    "If everything looks right, your Odoo Online plan may not expose the "
                    "external API (Standard plan blocks it; Custom plan allows it)."
                )
            self._uid = int(uid)
        return self._uid

    def execute_kw(
        self,
        model: str,
        method: str,
        args: list[Any],
        kwargs: dict[str, Any] | None = None,
    ) -> Any:
        """Low-level ORM call: model.method(*args, **kwargs) as the authenticated user."""
        try:
            return self._object.execute_kw(
                self.db, self.uid, self.api_key, model, method, args, kwargs or {}
            )
        except xmlrpc.client.Fault as exc:
            raise OdooError(f"Odoo error on {model}.{method}: {exc.faultString}") from exc

    # --- convenience helpers ------------------------------------------------

    def search_read(
        self,
        model: str,
        domain: list | None = None,
        fields: list[str] | None = None,
        limit: int = 80,
        offset: int = 0,
        order: str | None = None,
    ) -> list[dict[str, Any]]:
        kwargs: dict[str, Any] = {"limit": limit, "offset": offset}
        if fields:
            kwargs["fields"] = fields
        if order:
            kwargs["order"] = order
        return self.execute_kw(model, "search_read", [domain or []], kwargs)

    def search_count(self, model: str, domain: list | None = None) -> int:
        return self.execute_kw(model, "search_count", [domain or []])

    def read(self, model: str, ids: list[int], fields: list[str] | None = None) -> list[dict]:
        kwargs = {"fields": fields} if fields else {}
        return self.execute_kw(model, "read", [ids], kwargs)

    def fields_get(self, model: str) -> dict[str, Any]:
        return self.execute_kw(
            model,
            "fields_get",
            [],
            {"attributes": ["string", "type", "help", "required", "readonly", "relation", "selection"]},
        )

    def name_search(self, model: str, name: str, limit: int = 10) -> list:
        return self.execute_kw(model, "name_search", [name], {"limit": limit})

    def create(self, model: str, values: dict[str, Any]) -> int:
        return self.execute_kw(model, "create", [values])

    def write(self, model: str, ids: list[int], values: dict[str, Any]) -> bool:
        return self.execute_kw(model, "write", [ids, values])
