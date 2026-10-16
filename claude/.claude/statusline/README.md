# Status line

The bar Claude Code draws above its footer. `statusline.sh` is the whole thing:
Claude Code pipes it a JSON blob describing the session on stdin, and renders
whatever it prints to stdout.

## What it shows

Two lines, each justified across the terminal. Left is context — where the
session is, what is running. Right is consumption — what it is costing.

```
skills ⑂ worktree-statusline●          Opus 5·high  Ctx ██░░░░░░░░ 209k/1M
@claude                         5h 65% ⟳2h00m · 7d 19% ⟳3d0h │ $16.22
```

**Line one, left.** Repo name — from the `origin` remote, falling back to the
launch directory, and to the full path when this is not a repo at all — followed
by the path within the repo when the cwd is deeper than its root, so the bare
name always means "at the top". Then the branch: `⎇` in a normal checkout, `⑂`
in a worktree, with a `●` when the tree is dirty. Then the open PR, coloured by
review state.

**Line one, right.** Model, reasoning effort, and the context window. The bar is
the glanceable version; `209k/1M` beside it carries the precision and says which
window you are in, since it is 200k or 1M depending on the model. No percentage:
three renderings of one number was one too many.

**Line two, left.** What is running: `@agent` when the session was launched
under one, and a warning when the prompt cache has gone cold. When there is
nothing to report it falls back to `? for shortcuts` — see below.

**Line two, right.** Rate limits — for each window, the share consumed and a `⟳`
countdown to its reset — then, past the `│`, this session's estimated cost.

Segments stay silent at their default. `⚡` only appears in fast mode,
`(no think)` only when extended thinking is off, the output style only when it
is not `default`. The line is meant to be read at a glance, so anything
unsurprising is left out.

Colour tracks alarm, not category: green under 70%, yellow to 90%, red above.
That applies to the context bar and to every rate-limit percentage, so a glance
at the colour is enough.

### Reading the right-hand side

`5h 46% ⟳55m` — 46% of the rolling five-hour window consumed, resetting in 55
minutes. `7d 17% ⟳4d2h` — 17% of the weekly window, resetting in 4 days 2
hours. These come straight from the plan's rate limits and are the numbers that
decide whether you get throttled.

`$16.22` is **this session only**, resets when `/clear` starts a new one, and is
an estimate computed client-side at list price rather than a bill.

Elapsed session time and lines added/removed used to sit beside it and were
dropped on purpose. The clock is wall time including every idle stretch, so a
session left open overnight reads `25h` and means nothing; the line counts are a
`git diff` away. Cost is the one session number worth permanent space.

There is no dollar figure for the weekly window — `rate_limits` carries only
percentages and reset times. It could be reconstructed by summing token counts
out of `~/.claude/projects/**/*.jsonl` against a price table, but that takes
seconds rather than milliseconds, so it would need a cached file refreshed out
of band. On a subscription the result is notional anyway: it answers "what would
this week have cost on the API", not what gets billed. The `7d` percentage is
the number that actually predicts throttling.

## What configuring this costs

A custom status line suppresses most of Claude Code's footer *keyboard hints* —
`esc to interrupt`, the `? for shortcuts` fallback, and the `hold space to speak`
voice hint. The footer **badges** are untouched and still render below: the
permission mode, the PR badge, MCP and auto-update notices.

There is no setting that keeps them. The suppression follows from configuring a
status line at all, so the only way to have them back is to print them yourself.

`? for shortcuts` is printed here, on the same terms Claude Code used: reading
its own footer logic, that hint only ever appeared when the row was otherwise
empty — a filler, not a fixture, which is why the docs call it a fallback. Line
two's left side does the same, so the hint costs nothing whenever there is
something real to say there.

`esc to interrupt` is not reproducible at any price: nothing in the payload says
whether a turn is currently in flight. `hold space to speak` could be printed but
is not — unlike the shortcuts hint it points at one feature rather than at the
list of everything, so it earns its space less.

## What is deliberately missing

**Vim mode and permission mode.** Both are omitted because Claude Code already
renders them in its own footer, on the row directly below this one — showing
them here would just duplicate what is a glance away.

That is lucky for permission mode, because it could not be shown here anyway.
Claude Code does not put it in the payload, does not persist it to any file, and
does not pass it in the environment. It *does* re-run the status line when the
mode changes — the change is a refresh trigger — it just never says what the new
mode is.

**`exceeds_200k_tokens`.** A fixed 200k threshold regardless of the actual
window size. On a 1M-context model it goes true at 20% used and stays lit, which
is worse than showing nothing — confirmed on a captured payload reading
`exceeds_200k_tokens: true` beside `used_percentage: 21`. The context bar already
says what this was meant to.

**Running subagents and active skills.** Not in this payload. `agent.name` is
the agent the whole session runs under, not a list of what is executing right
now. Claude Code shows running subagents in the agent panel below the prompt
instead, and the separate [`subagentStatusLine`](https://code.claude.com/docs/en/statusline#subagent-status-lines)
setting customises those rows — it receives its own input, a `tasks` array with
each subagent's `name`, `status`, `model`, `effort` and token count.

## Justification and terminal width

`tput cols` cannot work from in here: Claude Code captures stdout rather than
handing over the tty. It exports `COLUMNS` before each run, which is what the
script justifies against.

`COLUMNS` is more than the width actually available, though, because Claude Code
draws this content inside its own spacing — measured at 213 in a terminal where
a 211-column line already ran off the right edge. Nothing reports the usable
width, so the script keeps a margin instead of calculating one: `margin`,
defaulting to 6 and overridable with `STATUSLINE_MARGIN`. Raise it if the
right-hand side still overflows.

A margin alone only holds until the left side grows, so line two's right-hand
side sheds from its tail until it fits, leaving the rate limits as the last
thing to go.

### Resizing

**A terminal resize does not re-run the status line.** It is not one of Claude
Code's triggers — those are a new assistant message, `/compact`, a permission or
vim mode change, a `command` edit, `refreshInterval`, and a rate-limit or prompt
cache expiry. `COLUMNS` is correct at the moment of each run, so a line is never
mis-justified when it is drawn; it goes wrong only because the terminal changed
underneath a line that was already printed, and nothing in the script can
observe that.

So the only real lever is how soon the next run comes, which is why
`refreshInterval` is 10 rather than 60. A resize is visibly wrong for up to ten
seconds and then corrects itself. At 56 ms a run that is well under a percent of
one core.

Worth knowing which way it fails: when the terminal grows the line is simply
short of the right edge, which is harmless. When it shrinks the line is too long
and wraps, and the part that overflows is the right-hand end — the rate limits
and cost. That is an argument against putting anything on the right that you
cannot bear to lose for a few seconds.

Widths are measured with the ANSI escapes stripped, in pure bash rather than by
shelling out, since this runs on every refresh. That counts characters, which is
only the same as columns under a UTF-8 locale — so if the padding ever comes out
negative, the script falls back to a single space and degrades to a left-aligned
line instead of mangling it. The same fallback covers a terminal too narrow to
justify into.

## The input

The full schema is in the [status line docs](https://code.claude.com/docs/en/statusline).
Fields this script reads:

| Field | Notes |
| --- | --- |
| `model.display_name` | |
| `effort.level` | `low`–`max`. Absent when the model has no effort parameter |
| `context_window.used_percentage` | Null early in a session and again right after `/compact` |
| `context_window.context_window_size` | 200k, or 1M on extended-context models |
| `context_window.total_input_tokens`, `.total_output_tokens` | Used for the "N left" figure |
| `fast_mode`, `thinking.enabled`, `output_style.name` | Only rendered when not at their default |
| `workspace.repo.name` | Repo name from the `origin` remote. Absent without one |
| `workspace.current_dir`, `workspace.project_dir`, `workspace.git_worktree` | |
| `worktree.name` | Present only in a worktree session |
| `pr.number`, `pr.review_state` | |
| `cost.total_cost_usd` | Session total, reset by `/clear`. A list-price estimate, not a bill |
| `rate_limits.five_hour`, `.seven_day`, `.spend_limit` | `used_percentage` plus `resets_at` in epoch seconds. Pro/Max only, and only after the session's first API response |
| `prompt_cache.warm` | |
| `agent.name` | The agent the session runs under, not what is executing now |

Almost every field is optional, so the script reads them in one `jq` pass and
treats absent and null identically.

The fields are joined with US (`0x1f`), not a tab. Tab counts as IFS whitespace
in bash, so `read` collapses runs of it — one absent optional field would shift
every later value one slot left, silently, and the status line would render
plausible-looking nonsense. Any separator used here has to be non-whitespace.

## Working on it

```sh
./preview.sh          # render every fixture
./preview.sh edge     # just one
```

`preview.sh` pins `COLUMNS` to 120 so the justification is reproducible rather
than dependent on the terminal rendering it; `COLUMNS=60 ./preview.sh`
checks how it degrades when there is no room to justify.

It renders `fixtures/*.json` through the script so a change can be checked
without starting a session, and fails if any fixture produces a non-zero exit or
empty output — that is exactly what a blank status line in Claude Code means. It also feeds in empty, malformed, and `{}` input, since
those must degrade to something rather than blanking the bar.

Reset timestamps in the fixtures are rebased onto the current time as they are
rendered. They are absolute epoch seconds, so a checked-in value would drift
into the past and the countdown would quietly vanish from the preview.

The fixtures cover the cases worth keeping honest:

- `live` — a real payload captured from a running session, identifiers scrubbed.
  The others are hand-written and only prove what I assumed; this one proves what
  Claude Code actually sends
- `full` — worktree session, high context, a rate limit into the red
- `minimal` — fresh session outside a repo: no git, no limits, null context
- `edge` — 1M context window, fast mode, thinking off, cold cache, PR with
  changes requested

Capturing a fresh `live` fixture means pointing `statusLine.command` at a wrapper
that tees stdin to a file before piping it on, using Claude Code for a moment,
then scrubbing `session_id`, `prompt_id` and `transcript_path`. Worth redoing
whenever a Claude Code release adds fields — the captured payload already carried
`agent_type` and `scratchpad_dir`, neither of which is in the published schema.

Runs in about 45 ms. Claude Code debounces status line updates at 300 ms and
cancels a run still in flight when the next update arrives, so the budget is
real but not tight. Keep it free of network calls.

## Wiring

This is the `claude` stow package, so both the script and the settings file that
activates it are symlinked out of the repo:

```sh
stow --dir ~/Projects/skills --target ~ claude
```

which gives `~/.claude/statusline` → here and `~/.claude/settings.json` →
`../Projects/skills/claude/.claude/settings.json`. Stow folds into the existing
`~/.claude` rather than replacing it, linking each entry individually.

`settings.json` then points at its own symlinked neighbour:

```json
"statusLine": {
  "type": "command",
  "command": "~/.claude/statusline/statusline.sh",
  "refreshInterval": 10
}
```

The repo holds the live copy, so an edit here takes effect on the next status
line refresh with no install step.

> **Watch the settings symlink.** Claude Code writes to `settings.json` itself
> when you change a setting through `/config`. If a write ever replaces the file
> instead of writing through the link, the link is gone and the repo silently
> stops tracking reality. `test -L ~/.claude/settings.json` says whether it still
> holds; re-`stow` if it does not.

`refreshInterval` is in seconds. Without it the status line only redraws on
events — a new assistant message, a `/compact`, a permission or vim mode change.
Two things here need a timer: the `⟳` countdowns to each rate-limit reset, and
recovery from a terminal resize, which is not itself a trigger. See
[Resizing](#resizing) for why that lands on 10 seconds.

`padding` is left unset. It defaults to 0 and *adds* indentation, so there is
nothing to gain by setting it to 0 explicitly.

Claude Code runs this under the same workspace-trust rule as hooks. In an
untrusted folder the bar stays blank and `claude --debug` logs
`Status line command skipped: workspace trust not accepted`.
