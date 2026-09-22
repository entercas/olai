"""The Olai MCP server: read-only tools over the Markdown mirror.

Transport is stdio. The root comes from OLAI_ROOT, defaulting to ~/Olai. Nothing
here writes to the mirror -- the app owns it, and v1 is export-only.
"""

from __future__ import annotations

from mcp.server.mcpserver import MCPServer

from . import tools

# MCP 2.x: FastMCP was renamed MCPServer. Pin mcp<2 if an older runtime is needed.
mcp = MCPServer("olai")


# MARK: Tools and prompts
#
# The implementations live in tools.py, shared with the standard-library server in
# standalone.py, so the two cannot drift apart.

for _tool in tools.TOOLS:
    mcp.tool(name=_tool["name"], description=_tool["description"])(_tool["run"])

for _prompt in tools.PROMPTS:
    mcp.prompt(name=_prompt["name"], description=_prompt["description"])(_prompt["run"])


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
