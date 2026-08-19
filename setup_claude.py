"""Register the Odoo connector in Claude Desktop's config file.

Cross-platform (Windows / macOS / Linux) and idempotent — re-running it updates the
"odoo" entry and leaves any other connectors alone.

Credentials come from .env next to this file. Setting ODOO_USERNAME and ODOO_API_KEY
in the environment overrides them, which is how the per-user installers pass a
personal key without writing it to disk.
"""

from __future__ import annotations

import json
import os
import platform
import shutil
import sys
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parent


def claude_code_config_path() -> Path:
    """Claude Code keeps user-scope MCP servers at the top level of ~/.claude.json.

    Separate app, separate config: installing for Claude Desktop does nothing for
    Claude Code, which is why people saw "no Odoo tools" after a clean install.
    """
    return Path.home() / ".claude.json"


def claude_config_path() -> Path:
    """Where Claude Desktop keeps its config on this OS."""
    system = platform.system()
    if system == "Windows":
        # APPDATA is set on any normal Windows session; fall back for odd shells.
        base = os.environ.get("APPDATA") or str(Path.home() / "AppData" / "Roaming")
        return Path(base) / "Claude" / "claude_desktop_config.json"
    if system == "Darwin":
        return Path.home() / "Library" / "Application Support" / "Claude" / "claude_desktop_config.json"
    return Path.home() / ".config" / "Claude" / "claude_desktop_config.json"


def find_uv() -> str:
    """Absolute path to uv.

    Claude Desktop launches connectors without the user's shell PATH, so a bare "uv"
    in the config works on some machines and silently fails on others. Always pin it.
    """
    found = shutil.which("uv")
    if found:
        return str(Path(found).resolve())

    exe = "uv.exe" if platform.system() == "Windows" else "uv"
    candidates = [
        Path.home() / ".local" / "bin" / exe,       # uv's own installer (all platforms)
        Path.home() / ".cargo" / "bin" / exe,       # older uv installs
        Path("/opt/homebrew/bin") / exe,
        Path("/usr/local/bin") / exe,
    ]
    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)

    raise SystemExit(
        "Could not find 'uv' on this machine. Install it, then re-run this installer:\n"
        "  Windows:  irm https://astral.sh/uv/install.ps1 | iex\n"
        "  macOS:    curl -LsSf https://astral.sh/uv/install.sh | sh"
    )


def read_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def build_env() -> dict[str, str]:
    """Connector credentials: .env as the base, real environment variables win."""
    env = read_env_file(REPO_DIR / ".env")
    for key in ("ODOO_URL", "ODOO_DB", "ODOO_USERNAME", "ODOO_API_KEY", "ODOO_ENABLE_WRITES"):
        if os.environ.get(key):
            env[key] = os.environ[key]

    missing = [k for k in ("ODOO_URL", "ODOO_DB", "ODOO_USERNAME", "ODOO_API_KEY") if not env.get(k)]
    if missing:
        raise SystemExit(
            f"Missing credentials: {', '.join(missing)}.\n"
            "The .env file next to this script should carry them — the bundle may be incomplete."
        )

    return {
        "ODOO_URL": env["ODOO_URL"],
        "ODOO_DB": env["ODOO_DB"],
        "ODOO_USERNAME": env["ODOO_USERNAME"],
        "ODOO_API_KEY": env["ODOO_API_KEY"],
        "ODOO_ENABLE_WRITES": env.get("ODOO_ENABLE_WRITES", "false"),
    }


def load_existing(config_file: Path) -> dict:
    try:
        data = json.loads(config_file.read_text(encoding="utf-8-sig"))
    except (FileNotFoundError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def register(config_file: Path, entry: dict, label: str) -> list[str]:
    """Merge the odoo entry into one app's config, leaving everything else alone."""
    config = load_existing(config_file)
    servers = config.get("mcpServers")
    if not isinstance(servers, dict):
        servers = {}
    other = [name for name in servers if name != "odoo"]

    servers["odoo"] = entry
    config["mcpServers"] = servers

    config_file.parent.mkdir(parents=True, exist_ok=True)
    # No BOM: Claude Desktop's JSON parser rejects it.
    config_file.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    print(f"   {label}: {config_file}")
    return other


def main() -> int:
    uv_path = find_uv()
    env = build_env()

    # Absolute --directory, never a bare "uv" or a cwd-relative path: neither app
    # launches connectors from this folder or with the user's shell PATH.
    entry = {
        "command": uv_path,
        "args": ["--directory", str(REPO_DIR), "run", "odoo-mcp"],
        "env": env,
    }

    other = register(claude_config_path(), entry, "Claude Desktop")
    other += register(claude_code_config_path(), dict(entry, type="stdio"), "Claude Code  ")

    print(f"   folder:  {REPO_DIR}")
    print(f"   uv:      {uv_path}")
    print(f"   odoo as: {env['ODOO_USERNAME']}")
    if env["ODOO_ENABLE_WRITES"].lower() in ("1", "true", "yes", "on"):
        print("   writes:  *** ENABLED - Claude can CREATE and CHANGE Odoo records ***")
    else:
        print("   writes:  off (read-only)")
    if other:
        print(f"   kept {len(other)} other connector(s): {', '.join(sorted(other))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
