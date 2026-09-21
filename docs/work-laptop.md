# Running the Olai agent on another Mac

For a machine where you have Claude Code but cannot install packages, and where you may
not want to build the app at all.

## What actually has to be there

The MCP server reads one thing: a folder of Markdown files that Olai exported. It does
not need the app, a database, or an account. So there are two separate questions:

1. **Getting the notes onto that machine.** The mirror is written by the Mac app, so
   that machine needs either the app running on it, or a copy of the mirror folder.
2. **Reading them.** That is the server, and it needs nothing but Python.

Most people only need the second. Point the server at a synced copy of `~/Olai` and you
get weekly summaries and priorities without installing anything.

## Setup, with no package installs

```bash
git clone https://github.com/entercas/olai.git ~/olai
```

Then register the server with Claude Code, pointing `OLAI_ROOT` at wherever the mirror
lives on that machine:

```bash
claude mcp add olai --scope user \
  --env OLAI_ROOT="$HOME/Olai" \
  --env PYTHONPATH="$HOME/olai/mcp-server" \
  -- python3 -m olai_mcp.standalone
```

`--scope user` is the part that is easy to miss: without it the default scope is
`local`, meaning the server exists only in the directory you ran the command in. Notes
are worth asking about from wherever you happen to be working, so register it for the
user.

That is the whole install. `olai_mcp.standalone` is an MCP server written against the
Python standard library, so it runs on the `python3` macOS already has — verified on the
stock 3.9. Nothing is pip-installed and no virtual environment is created.

Check it:

```bash
claude mcp list
```

It should report `olai: python3 -m olai_mcp.standalone - ✓ Connected`.

Then just ask, in an ordinary Claude Code session:

```
> summarise my last two weeks
> what should I prioritise next week?
> what did I write about the mirror?
```

There is nothing to invoke by hand. Claude Code sees the tools and calls them when a
question needs them; the three prompts are also available as slash commands, listed
under `/mcp`.

If `python3` is missing, macOS offers to install the Command Line Tools, which is the
only prerequisite. The richer SDK server (`olai_mcp.server`) is still there for machines
where `pip install -e .` is allowed; both expose the same tools from the same code.

## What it can do

| Ask for | What it calls |
| --- | --- |
| "Summarise the last two weeks" | `get_weekly_pages(2)` |
| "What should I prioritise next week?" | the last three weekly pages, with citations |
| "Find what I wrote about X" | `search_notes` |
| "Draft a review for this quarter" | `get_goals_with_evidence` plus the weeks |

There are also three ready-made prompts: `weekly_summary`, `next_week_priorities`,
`performance_review_draft`.

## It does not talk to anything

Worth being able to show, not just assert:

- **The reader imports only the standard library** — `os`, `re`, `dataclasses`,
  `datetime`, `pathlib`. No HTTP client, no socket, no telemetry. Check with
  `grep -rE "socket|urllib|requests|http" mcp-server/olai_mcp/*.py`.
- **The transport is stdin and stdout.** An MCP stdio server is a process the client
  writes JSON lines to and reads JSON lines from. There is no port and no listener.
- **It is read-only.** The only tool that would write, `append_to_page`, returns an error
  saying the mirror is export-only.

To see this for yourself while it runs:

```bash
lsof -a -p "$(pgrep -f olai_mcp.standalone)" -i -nP
```

`-a` matters: it means *and this process*. Without it, `lsof` prints every connection on
the machine, which looks alarming and has nothing to do with the server. With it, the
output is empty.

Your notes still leave the machine in one sense worth naming plainly: whatever you ask
the agent goes to the model, along with whichever pages it reads to answer. The server
is local; the conversation is not.

## If you want the notes there too

The server needs the Markdown; how it arrives is your call.

- **Sync the folder** (Dropbox, iCloud Drive, a private git repo). Simplest, and the
  notes then live in that service as well as on both Macs.
- **Copy it occasionally** with `rsync`, if a point-in-time snapshot is enough.
- **Run the app on that machine** if you want to write notes there. That needs Xcode and
  signing in with the Apple ID holding the iCloud data — on a work laptop, check that
  against your employer's policy before you do it.

Nothing in the first two options requires the app, Xcode, or an Apple ID.
