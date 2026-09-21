"""An MCP server over stdio using nothing but the Python standard library.

The SDK version in `server.py` is the same tools; this exists for machines where
installing packages is not an option. It speaks JSON-RPC over stdin and stdout, which
is all the stdio transport is.

It opens no sockets and reads nothing but the mirror folder. `python3 -m
olai_mcp.standalone` is the whole dependency list.
"""

from __future__ import annotations

import json
import sys
import traceback
from typing import Any

from . import tools

SERVER = {"name": "olai", "version": "0.1.0"}
SUPPORTED_PROTOCOLS = ["2025-06-18", "2025-03-26", "2024-11-05"]


def _log(message: str) -> None:
    # stdout carries the protocol; anything else has to go to stderr.
    print(message, file=sys.stderr, flush=True)


def _result(request_id: Any, result: dict[str, Any]) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": request_id, "result": result}


def _error(request_id: Any, code: int, message: str) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}}


def _public(entries: list[dict[str, Any]], keys: tuple[str, ...]) -> list[dict[str, Any]]:
    return [{key: entry[key] for key in keys if key in entry} for entry in entries]


def handle(message: dict[str, Any]) -> dict[str, Any] | None:
    method = message.get("method")
    request_id = message.get("id")
    params = message.get("params") or {}

    # Notifications carry no id and get no reply.
    if request_id is None:
        return None

    if method == "initialize":
        asked = params.get("protocolVersion")
        version = asked if asked in SUPPORTED_PROTOCOLS else SUPPORTED_PROTOCOLS[-1]
        return _result(
            request_id,
            {
                "protocolVersion": version,
                "capabilities": {"tools": {}, "prompts": {}},
                "serverInfo": SERVER,
            },
        )

    if method == "ping":
        return _result(request_id, {})

    if method == "tools/list":
        return _result(
            request_id,
            {"tools": _public(tools.TOOLS, ("name", "description", "inputSchema"))},
        )

    if method == "prompts/list":
        return _result(
            request_id,
            {"prompts": _public(tools.PROMPTS, ("name", "description", "arguments"))},
        )

    if method == "tools/call":
        run = tools.find(tools.TOOLS, params.get("name", ""))
        if run is None:
            return _error(request_id, -32602, f"No tool named {params.get('name')!r}")
        try:
            text = run(**(params.get("arguments") or {}))
        except Exception as error:  # a bad argument should not kill the server
            return _result(
                request_id,
                {"content": [{"type": "text", "text": f"{type(error).__name__}: {error}"}],
                 "isError": True},
            )
        return _result(request_id, {"content": [{"type": "text", "text": text}]})

    if method == "prompts/get":
        run = tools.find(tools.PROMPTS, params.get("name", ""))
        if run is None:
            return _error(request_id, -32602, f"No prompt named {params.get('name')!r}")
        text = run(**(params.get("arguments") or {}))
        return _result(
            request_id,
            {
                "description": params.get("name"),
                "messages": [{"role": "user", "content": {"type": "text", "text": text}}],
            },
        )

    return _error(request_id, -32601, f"Unknown method {method!r}")


def main() -> None:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            _log(f"ignoring a line that is not JSON: {line[:80]}")
            continue

        try:
            reply = handle(message)
        except Exception:
            _log(traceback.format_exc())
            reply = _error(message.get("id"), -32603, "Internal error")

        if reply is not None:
            print(json.dumps(reply), flush=True)


if __name__ == "__main__":
    main()
