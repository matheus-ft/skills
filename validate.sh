#!/usr/bin/env bash
# Structural checks that have to hold before a skill is packaged or pushed.
# Shared by .githooks/pre-push and by CI, and safe to run by hand at any time.
#
# Everything here is a failure that is silent at the point it bites: a name
# mismatch is rejected by the claude.ai uploader without saying why, and a skill
# with no description loads fine and then never triggers.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$root/skills"
manifest="$root/.claude-plugin/plugin.json"

status=0
fail() {
  echo "FAIL: $*" >&2
  status=1
}

# Value of one key from the first --- fenced block of a SKILL.md.
frontmatter() {
  awk -v key="$2" '
    /^---$/ { n++; if (n > 1) exit; next }
    n == 1 {
      if (index($0, key ":") == 1) {
        sub("^" key ":[ \t]*", "")
        print
        exit
      }
    }
  ' "$1"
}

echo "== skills"
found=0
for d in "$src"/*/; do
  [ -d "$d" ] || continue
  found=$((found + 1))
  name=$(basename "$d")
  skill="$d/SKILL.md"

  if [ ! -f "$skill" ]; then
    fail "$name: no SKILL.md"
    continue
  fi

  if [ "$(head -1 "$skill")" != "---" ]; then
    fail "$name: SKILL.md does not open with a --- frontmatter block"
    continue
  fi

  # The folder name and the declared name must agree or the upload is rejected.
  declared=$(frontmatter "$skill" name)
  if [ -z "$declared" ]; then
    fail "$name: frontmatter has no name:"
  elif [ "$declared" != "$name" ]; then
    fail "$name: frontmatter declares name '$declared'"
  fi

  # A skill with no description never triggers. Block scalars are legitimate.
  description=$(frontmatter "$skill" description)
  case "$description" in
    "") fail "$name: frontmatter has no description:" ;;
    "|" | ">" | "|-" | ">-" | "|+" | ">+") ;;
    *) ;;
  esac

  [ $status -eq 0 ] && echo "   ok: $name"
done

if [ "$found" -eq 0 ]; then
  fail "no skills found under $src"
fi

echo "== plugin manifest"
if [ ! -f "$manifest" ]; then
  fail "missing $manifest"
else
  if python3 - "$manifest" <<'PY'; then
import json, sys

path = sys.argv[1]
try:
    with open(path) as fh:
        data = json.load(fh)
except json.JSONDecodeError as exc:
    sys.exit(f"not valid JSON: {exc}")

if not isinstance(data, dict):
    sys.exit("top level is not an object")

for key in ("name", "description", "version"):
    if not data.get(key):
        sys.exit(f"missing or empty {key!r}")
PY
    echo "   ok: $(basename "$manifest")"
  else
    fail "$(basename "$manifest") is not a usable plugin manifest"
  fi
fi

# The CLI is the authority on the manifest, but it is not installed in CI.
# Run it when it happens to be around; never fail the check for its absence.
if command -v claude >/dev/null 2>&1; then
  if claude plugin validate "$root" >/dev/null 2>&1; then
    echo "   ok: claude plugin validate"
  else
    fail "claude plugin validate rejected the manifest"
  fi
fi

if [ $status -eq 0 ]; then
  echo
  echo "all checks passed"
fi
exit $status
