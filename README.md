# skills

Source of truth for my Claude setup: the skills, plus the Claude Code config that
loads them (settings, rules, status line).

## How skills reach Claude

|                       | Reaches                                                 | How it gets there                                                                                                  |
| --------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| **`skills/` here**    | Claude Code                                             | `~/.claude/skills`, stowed from [`claude/`](#claude-code-config)                                                   |
| **Account skills**    | claude.ai chat, Desktop, Cowork, Design, _and_ Claude Code | zip uploaded at claude.ai → Settings → Capabilities → Skills; Claude Code downloads them into `~/.claude/skills/synced/` |

The sync is one-way, account → Claude Code, and the upload is manual: there is no API
for it. A skill uploaded from here therefore shows up in Claude Code twice, the local
copy under its short name and the synced one as `anthropic-skills:<name>`. So only
skills meant for chat go up. Most skills here are Claude Code-only and stay off the
account. `package.sh` makes the upload cheap; `drift.sh` polices it.

## The skills, and who wrote them

Some of the skills here may have been taken from elsewhere, and such are credited as below

| Skill             | Taken from                                                                                       | Licence    |
| ----------------- | ------------------------------------------------------------------------------------------------ | ---------- |
| `frontend-design` | [anthropics/skills](https://github.com/anthropics/skills/tree/main/skills/frontend-design)       | Apache 2.0 |
| `grill-me`        | [mattpocock/skills](https://github.com/mattpocock/skills/tree/main/skills/productivity/grill-me) | MIT        |
| `grilling`        | [mattpocock/skills](https://github.com/mattpocock/skills/tree/main/skills/productivity/grilling) | MIT        |
| `handoff`         | [mattpocock/skills](https://github.com/mattpocock/skills/tree/main/skills/productivity/handoff)  | MIT        |
| `unslop`          | [backnotprop/pstack](https://github.com/backnotprop/pstack/tree/main/skills/unslop) (disabled)   | MIT        |

Each carries its upstream licence file in its folder, so the notice ships inside the zip
too. They are taken verbatim and kept current, as described in
[Tracking upstream](#tracking-upstream).

## Layout

```
.claude-plugin/plugin.json   makes the repo a single Claude Code plugin
skills/<name>/SKILL.md       the skills themselves
claude/.claude/              stow package for ~/.claude: settings.json, rules/, statusline/
claude/.claude/skills        link back to ./skills, so stow wires the skills too
package.sh                   zip skills into dist/ for claude.ai upload
validate.sh                  the checks that must hold before a skill ships
drift.sh                     repo vs. Claude Code vs. what is live on the account
upstream.sh, upstream.tsv    copied skills vs. their upstream repos, and the pins
.githooks/pre-push           runs validate.sh and package.sh before letting a push through
.github/workflows/skills.yml the same checks in CI, as a backstop
.github/workflows/upstream.yml  upstream.sh weekly, proposing updates as a PR
disabled/<name>/SKILL.md     parked skills: kept, but never loaded or packaged
dist/                        build output, gitignored
```

`skills/` is a fixed directory name — Claude Code's plugin loader looks for exactly
that. Each folder name must match the `name:` in its `SKILL.md`; `package.sh` enforces
it, because a mismatch is the usual silent upload rejection.

To switch a skill off without losing it, move its folder to `disabled/`; move it back to
switch it on. That only covers Claude Code. A copy uploaded to the account stays live until
it is toggled off at claude.ai.

`skills/synced/` is not ours. Claude Code downloads the account skills into
`~/.claude/skills/synced/`, and the link routes that copy into this repo. It is
gitignored, and all three scripts skip it.

## Adding or editing a skill

1. `skills/<name>/SKILL.md`, with `name:` matching the folder and a `description:` that
   says when to trigger.
2. **Claude Code picks it up on the next session** — the stowed link takes care of it.
3. Only if it is meant for chat too: `./package.sh <name>`, then upload `dist/<name>.zip`.
4. `./drift.sh` to confirm what is live matches what is here.

`claude plugin validate .` checks the manifest after touching `plugin.json`.

If the skill came from someone else, add it to the credits table above, add a line to
`upstream.tsv` with `-` as the commit, and run `./upstream.sh pull <name>`.

Only copy what its licence allows to be redistributed, since this repo is public.
Anthropic's document skills (`docx`, `pdf`, `pptx`, `xlsx`) are all rights reserved;
others such as `learn` and `frontend-design` are Apache 2.0. If a copied skill also goes
up to claude.ai, upload this copy and remove the one installed from Anthropic.

## Tracking upstream

```sh
./upstream.sh                  # report; exit 1 if any copied skill is behind
./upstream.sh pull grilling    # take upstream's latest for one (or all, with no name)
```

`upstream.tsv` pins the upstream commit each copied skill matches. The report lists, per
skill, the files upstream changed since that pin, and any local edits, which the next
pull overwrites; `git diff` shows what a pull brought in. A pull mirrors the whole
upstream folder, extras such as mattpocock's `agents/openai.yaml` (for OpenAI's agents)
included. A folder with no licence of its own also gets the repo's, so every copy
carries its notice.

`.github/workflows/upstream.yml` runs the report every Monday. While anything is behind
it keeps one PR open from the `upstream-updates` branch, rebuilt each week, and closes
it once all are current. The repo needs **Allow GitHub Actions to create and approve
pull requests** turned on under Settings → Actions → General.

## Claude Code config

```sh
stow --dir ~/Projects/skills --target ~ claude
```

Stow folds into the existing `~/.claude` instead of replacing it, linking each entry
individually. If `~/.claude/skills` already exists as a real directory or a link not owned
by stow, move it aside first; stow refuses to replace it.

`rules/` replaces a `~/.claude/CLAUDE.md`: instructions every session loads, one file per
topic. They are not skills because a skill loads only when its description matches,
and these must shape every turn. [`models.md`](claude/.claude/rules/models.md) decides
which model takes which work; effort stays unset so each model keeps its own default.

The status line needs `jq` and `git`; notes and a fixture preview in
[`claude/.claude/statusline/README.md`](claude/.claude/statusline/README.md).

Claude Code rewrites `settings.json` whenever you change a setting through `/config`. If
a write replaces it instead of following the link, the repo quietly stops tracking
reality. To check, and repair if needed:

```sh
test -L ~/.claude/settings.json || stow -R --dir ~/Projects/skills --target ~ claude
```

`Enter` in `/effort` or `/model` saves there too; `s` changes it for the session only.

## Consumers

### Claude Code, this machine — stow

See [Claude Code config](#claude-code-config). `~/.claude/skills.bak` is kept
deliberately, as the only copy of whatever was installed before this repo existed.

Verify after any change to the link:

```sh
claude -p "Output only the names of skills available to you via the Skill tool, one per line." --model haiku
```

Skills with `disable-model-invocation: true` will **not** appear in that list — they are
slash-command only (e.g. `grill-me` being absent is correct, not a broken link).

### Claude Code, other machines — plugin

The repo is a valid plugin, so `--plugin-dir` works against a clone immediately:

```sh
claude --plugin-dir ~/Projects/skills
```

For `claude plugin marketplace add <user>/skills`, the repo additionally needs
`.claude-plugin/marketplace.json` listing itself:

```json
{
  "name": "skills",
  "owner": { "name": "matheus-ft" },
  "plugins": [{ "name": "skills", "source": "./" }]
}
```

### chat / Cowork / Design — manual upload

```sh
./package.sh grilling           # one skill
./package.sh grilling handoff   # several
./package.sh                    # every skill, rarely wanted: most are Claude Code-only
```

Then drag `dist/<name>.zip` into claude.ai → Settings → Capabilities → Skills. There is
no API for this; it is a browser step every time.

## Checking drift

```sh
./drift.sh
```

Reports the repo against both consumers. The account side reads Claude Desktop's
read-only sync cache under `~/Library/Application Support/Claude/` — the only local
evidence of what is actually live on the account, since nothing exposes that over an
API. It is empty until Desktop has run at least once. `drift.sh` never writes there;
editing that cache directly is pointless because sync overwrites it. Claude Code-only
skills show as `NOT UPLOADED`, which is expected for them.

## Automation

The upload itself cannot be automated, so everything around it is.

`validate.sh` is the gate. It rejects a folder whose name disagrees with the `name:` in
its `SKILL.md`, a skill with no `description:`, and a plugin manifest that is not usable.
All three fail silently in real use — a name mismatch is refused by the uploader without
saying why, and a skill with no description loads and then never triggers.

Enable the hook once per clone:

```sh
git config core.hooksPath .githooks
```

`pre-push` then runs `validate.sh` and rebuilds `dist/` on every push, so the zips on
disk always match the commit. `--no-verify` skips it when you need to.

CI (`skills.yml`) runs the same `validate.sh` on every push and pull request. It is a
backstop for the times the hook does not run: a fresh clone before `core.hooksPath` is
set, or a push with `--no-verify`. Building the zips stays local, since the upload they
feed is a browser step on this machine anyway.

## Portability

Account skills run without a working directory, a shell, or a repo. Anything that
assumes one of those is Claude Code-only, and earns a note here when it lands.

`disable-model-invocation` and `argument-hint` are Claude Code-only frontmatter keys.
Harmless elsewhere — ignored, not rejected.

`claude/` is Claude Code-only as a whole. Chat's nearest equivalent to `rules/` is the
profile preferences at claude.ai, pasted by hand.

## What this repo does not cover

It is the source of truth for _my_ setup, not an inventory of everything Claude has.
Deliberately outside it:

- **Skills installed from Anthropic** — `learn`, `morning`, `skill-creator`, `docx`,
  `pdf`, `pptx`, `xlsx`, `schedule`, `setup-cowork`, `explain-usage`,
  `consolidate-memory`, `import-memory`. Account-side, managed at claude.ai, and synced
  into Claude Code. `drift.sh` lists them under "account-only" so they stay visible
  without being vendored.
- **`~/Claude/Scheduled/*`** — scheduled-run wrappers. They stay put: each one is an
  instruction specific to its schedule, not a skill.
- **Claude Code's own built-in skills** (`code-review`, `dataviz`, `artifact-*`, …) —
  shipped with the CLI.
