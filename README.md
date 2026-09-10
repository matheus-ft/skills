# skills

Source of truth for my Claude skills.

## Why this exists

Skills reach Claude through **two systems that do not talk to each other**:

|                    | Reaches                                 | How it loads                                                 |
| ------------------ | --------------------------------------- | ------------------------------------------------------------ |
| **Filesystem**     | Claude Code only                        | `~/.claude/skills/`, project `.claude/skills/`, plugins      |
| **Account skills** | claude.ai chat, Desktop, Cowork, Design | uploaded zip at claude.ai → Settings → Capabilities → Skills |

There is no `claude skill` CLI verb and no sync between them. Account skills do not
appear in Claude Code; local skills do not appear in chat. The bridge is a manual zip
upload, which is what `package.sh` exists to make cheap and `drift.sh` exists to police.

## The skills, and who wrote them

Some of the skills here may have been taken from elsewhere, and such are credited as below

| Skill      | Taken from                                                                                       | Licence |
| ---------- | ------------------------------------------------------------------------------------------------ | ------- |
| `grill-me` | [mattpocock/skills](https://github.com/mattpocock/skills/tree/main/skills/productivity/grill-me) | MIT     |
| `grilling` | [mattpocock/skills](https://github.com/mattpocock/skills/tree/main/skills/productivity/grilling) | MIT     |
| `handoff`  | [mattpocock/skills](https://github.com/mattpocock/skills/tree/main/skills/productivity/handoff)  | MIT     |
| `unslop`   | [backnotprop/pstack](https://github.com/backnotprop/pstack/tree/main/skills/unslop)              | MIT     |

They are generally taken verbatim, but nothing tracks upstream automatically, so I may edit them from time to time to
suit my specific needs.

## Layout

```
.claude-plugin/plugin.json   makes the repo a single Claude Code plugin
skills/<name>/SKILL.md       the skills themselves
package.sh                   zip skills into dist/ for claude.ai upload
drift.sh                     repo vs. Claude Code vs. what is live on the account
dist/                        build output, gitignored
```

`skills/` is a fixed directory name — Claude Code's plugin loader looks for exactly
that. Each folder name must match the `name:` in its `SKILL.md`; `package.sh` enforces
it, because a mismatch is the usual silent upload rejection.

## Adding or editing a skill

1. `skills/<name>/SKILL.md`, with `name:` matching the folder and a `description:` that
   says when to trigger.
2. **Claude Code picks it up on the next session** — the symlink takes care of it (no additional install step).
3. For chat / Cowork / Design: `./package.sh <name>` then upload `dist/<name>.zip`.
4. `./drift.sh` to confirm what is live matches what is here.

`claude plugin validate .` checks the manifest after touching `plugin.json`.

If the skill came from someone else, add it to the credits table above.

## Consumers

### Claude Code via symlink

Symlink `~/.claude/skills` to `./skills`, so edits in the repo are live in the next session with no copy step.

```sh
mv ~/.claude/skills ~/.claude/skills.bak      # keep the old dir until proven
ln -s ~/projects/skills/skills ~/.claude/skills
```

The pre-symlink directory is retained at `~/.claude/skills.bak` deliberately, as the
only copy of whatever was installed before this repo existed. To undo:
`rm ~/.claude/skills && mv ~/.claude/skills.bak ~/.claude/skills`.

Verify after any change to the link:

```sh
claude -p "Output only the names of skills available to you via the Skill tool, one per line." --model haiku
```

Skills with `disable-model-invocation: true` will **not** appear in that list — they are
slash-command only (e.g. `grill-me` being absent is correct, not a broken link).

### Claude Code, other machines — plugin

The repo is a valid plugin, so `--plugin-dir` works against a clone immediately:

```sh
claude --plugin-dir ~/projects/skills
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
./package.sh                    # all skills
./package.sh grilling unslop    # named ones
```

Then drag `dist/*.zip` into claude.ai → Settings → Capabilities → Skills. There is no
API for this; it is a browser step every time.

## Checking drift

```sh
./drift.sh
```

Reports the repo against both consumers. The account side reads Claude Desktop's
read-only sync cache under `~/Library/Application Support/Claude/` — the only local
evidence of what is actually live on the account, since nothing exposes that over an
API. It is empty until Desktop has run at least once. `drift.sh` never writes there;
editing that cache directly is pointless because sync overwrites it.

## Portability

Account skills run without a working directory, a shell, or a repo. Anything that
assumes one of those is Claude Code-only, and earns a note here when it lands.

`disable-model-invocation` and `argument-hint` are Claude Code-only frontmatter keys.
Harmless elsewhere — ignored, not rejected.

## What this repo does not cover

It is the source of truth for _my_ skills, not an inventory of everything Claude has.
Deliberately outside it:

- **Skills installed from Anthropic** — `learn`, `morning`, `skill-creator`, `docx`,
  `pdf`, `pptx`, `xlsx`, `schedule`, `setup-cowork`, `explain-usage`,
  `consolidate-memory`, `import-memory`. Account-side, managed at claude.ai. `drift.sh`
  lists them under "account-only" so they stay visible without being vendored.
- **`~/Claude/Scheduled/*`** — scheduled-run wrappers. They stay put: each one is an
  instruction specific to its schedule, not a skill.
- **Claude Code's own built-in skills** (`code-review`, `dataviz`, `artifact-*`, …) —
  shipped with the CLI.
