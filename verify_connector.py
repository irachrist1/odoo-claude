"""Prove the connector works the way Claude Desktop will actually run it.

Reads the entry that was just written into claude_desktop_config.json, launches it
with exactly that command, args and environment, and performs a real MCP handshake.

The point is to fail here, in a window the user is already looking at, rather than
silently inside Claude Desktop where the only symptom is "Claude has no Odoo tools".
"""

from __future__ import annotations

import json
import os
import queue
import subprocess
import sys
import threading
import time

from setup_claude import claude_config_path

TIMEOUT_SECONDS = 90


def main() -> int:
    config_file = claude_config_path()
    try:
        config = json.loads(config_file.read_text(encoding="utf-8-sig"))
        entry = config["mcpServers"]["odoo"]
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        print("   Could not read the Odoo entry back from Claude's config.")
        return 1

    env = dict(os.environ)
    env.update(entry.get("env") or {})

    # tools/list alone is a weak check: the tool list is static, so it succeeds even
    # with dead credentials. Calling odoo_whoami drives a real query to Odoo through
    # the same path Claude Desktop will use.
    handshake = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                    "clientInfo": {"name": "installer-check", "version": "1"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
         "params": {"name": "odoo_whoami", "arguments": {}}},
    ]
    payload = "".join(json.dumps(m) + "\n" for m in handshake)

    try:
        proc = subprocess.Popen(
            [entry["command"], *entry.get("args", [])],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
    except FileNotFoundError:
        print(f"   Claude Desktop won't be able to start it: '{entry['command']}' not found.")
        return 1

    # Stdin stays open until the reply lands: the server shuts down on EOF, and
    # closing it early kills the tool call mid-flight while it waits on Odoo.
    # A reader thread rather than select(), which doesn't take pipes on Windows.
    lines: "queue.Queue[str | None]" = queue.Queue()

    def pump() -> None:
        for line in proc.stdout:  # type: ignore[union-attr]
            lines.put(line)
        lines.put(None)

    threading.Thread(target=pump, daemon=True).start()

    tools: list[str] = []
    whoami = ""
    try:
        proc.stdin.write(payload)  # type: ignore[union-attr]
        proc.stdin.flush()  # type: ignore[union-attr]

        deadline = time.monotonic() + TIMEOUT_SECONDS
        while time.monotonic() < deadline:
            try:
                line = lines.get(timeout=1.0)
            except queue.Empty:
                continue
            if line is None:
                break
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            if message.get("id") == 2:
                tools = [t.get("name", "?") for t in message.get("result", {}).get("tools", [])]
            elif message.get("id") == 3:
                for block in message.get("result", {}).get("content", []):
                    whoami += block.get("text", "")
                break
    except (BrokenPipeError, OSError):
        pass
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()

    if not tools:
        print("   The connector started but returned no tools.")
        detail = (proc.stderr.read() if proc.stderr else "").strip().splitlines()
        if detail:
            print(f"   {detail[-1][:200]}")
        return 1

    try:
        identity = json.loads(whoami)
    except json.JSONDecodeError:
        identity = {}

    if not identity.get("connected"):
        print("   The connector started, but Odoo rejected it:")
        print(f"   {(whoami or 'no response').strip()[:200]}")
        return 1

    print(f"   Claude Desktop can start it and sees {len(tools)} Odoo tools.")
    print(f"   Live check: connected to Odoo as {identity.get('user')} ({identity.get('company')}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
