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

## Getting the code there

The repository is private, and it does not need to become public for any of this. Three
ways in, easiest first.

**Copy one file.** The standalone server builds into a single 24 KB `.pyz` — a zip
application, which is a standard-library feature, not a package you install. No git, no
GitHub account on that machine, nothing to install:

```bash
# from a machine that has the repo
mcp-server/build-bundle.sh ~/Desktop/olai-mcp.pyz
```

Move that one file across however you normally would — email, AirDrop, a USB stick, your
own file sync — and put it somewhere sensible, say `~/bin/olai-mcp.pyz`. That is the
whole install. Nothing is unpacked and nothing is registered with the system.

**Or clone the private repo.** Private is fine as long as the machine can authenticate --
but this means signing in to GitHub on a work laptop, which is worth a thought if the
account you have there is your employer's:

```bash
gh auth login && gh repo clone entercas/olai ~/olai     # with the GitHub CLI
git clone git@github.com:entercas/olai.git ~/olai        # with an SSH key
git clone https://github.com/entercas/olai.git ~/olai    # with a personal access token
```

**Making the repository public is not necessary**, and costs something: it publishes the
Apple Team ID in `project.yml`, the bundle and iCloud container identifiers, and the
whole history — which stays cached and indexed even if it is made private again later.

## Setup, with no package installs

Register the server with Claude Code, pointing `PYTHONPATH` at wherever the code landed
and `OLAI_ROOT` at wherever the mirror lives:

```bash
claude mcp add olai --scope user \
  --env OLAI_ROOT="$HOME/Olai" \
  -- python3 "$HOME/bin/olai-mcp.pyz"
```

If you cloned the repository instead of copying the single file, point at the package
rather than the bundle -- `PYTHONPATH` has to name the folder *containing* `olai_mcp`:

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

That is the whole install. The server is written against the Python standard library, so
it runs on the `python3` macOS already has — verified on the stock 3.9, from an
unrelated working directory, as a bundle and as a package. Nothing is pip-installed and
no virtual environment is created.

`gh` is not needed for any of this, and neither is `git`.

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
