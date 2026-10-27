# claude-statusline

A status line for [Claude Code](https://code.claude.com/docs/en/statusline): model, git, context,
prompt cache and usage limits, always in view.

```
Opus·M │ myapp main +2~3 ↑2 (+120/-4) │ ctx 85,000/200K 42% · cache 49m
5h 10% (16:34) │ 7d 55% (10/21 15:34) │ 7d→ 96% │ $1.23
```

## Installation

Requirements: `bash`, `jq` and `git`. Works on macOS and Linux.

The quickest way is to ask Claude Code: *"Install the status line from
https://github.com/NicoCorini/claude-statusline following its README"*. By hand:

1. Clone the repo and link the two scripts into `~/.claude/`. With symlinks, `git pull` is all it
   takes to update; copy them instead if you prefer.

   ```bash
   git clone https://github.com/NicoCorini/claude-statusline
   ln -s "$PWD/claude-statusline/statusline.sh" ~/.claude/statusline.sh
   ln -s "$PWD/claude-statusline/subagent-statusline.sh" ~/.claude/subagent-statusline.sh
   ```

2. Add to `~/.claude/settings.json`, next to your existing settings:

   ```json
   "statusLine": {
     "type": "command",
     "command": "~/.claude/statusline.sh",
     "refreshInterval": 5
   },
   "subagentStatusLine": {
     "type": "command",
     "command": "~/.claude/subagent-statusline.sh"
   }
   ```

   `refreshInterval` keeps the cache countdown ticking while the session is idle.

Open sessions pick up the new status line on their own.

The scripts make no network requests: they read only the JSON Claude Code passes them and the git
state of the current directory. To avoid running git on every refresh, they keep a tiny cache in
`~/.cache/claude-statusline/`.

### Uninstall

Remove `statusLine` and `subagentStatusLine` from `~/.claude/settings.json`, then:

```bash
rm ~/.claude/statusline.sh ~/.claude/subagent-statusline.sh
rm -rf ~/.cache/claude-statusline
```

If you use `CLAUDE_CONFIG_DIR` or `XDG_CACHE_HOME`, adjust the paths accordingly.

## What it shows

**First line**

| Segment | Meaning |
|---|---|
| `Opus·M` | Model and effort (`L`, `M`, `H`, `XH`, `MAX`; `think` when only thinking is on) |
| `myapp` | Current directory, with `⎇` inside a worktree |
| `main +2~3 ↑2 (+120/-4)` | Branch, staged files (`+`), modified tracked files (`~`), unpushed commits (`↑`), lines added/removed against `HEAD` |
| `ctx 85,000/200K 42%` | Tokens in context (yellow from 70%, red from 90%) |
| `cache 49m` | Time until the prompt cache expires: dim, yellow in the last 15 minutes, red in the last 5, `✗` once expired |

**Second line**

| Segment | Meaning |
|---|---|
| `5h 10% (16:34)` | 5-hour limit and reset time |
| `7d 55% (10/21 15:34)` | Weekly limit and reset date |
| `7d→ 96%` | Projection: where the weekly limit lands at reset if you keep the current pace. Red above 100%. Hidden in the first 6 hours of the week |
| `$1.23` | Estimated session cost |

The 5h/7d limits appear only on a Pro or Max subscription, after the session's first response.

Numbers and dates follow your locale (`LC_ALL`, `LC_NUMERIC`, `LC_TIME`, then `LANG`); on macOS
the region in System Settings comes before `LANG`. With an Italian region, for example, the context
reads `85.000` and the weekly reset `21.10 15:34`.

**Subagent panel**

One row per subagent: name, model and effort, context used, and the worktree and branch it works in.
Finished subagents are dimmed.
