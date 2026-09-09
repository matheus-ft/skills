#!/usr/bin/env bash
# Compare this repo against the two places skills actually get consumed:
#   1. ~/.claude/skills          -> Claude Code (a symlink to ./skills means always in sync)
#   2. the account-skills cache  -> claude.ai chat / Desktop / Cowork / Design
# The account cache is read-only and written by Claude Desktop's sync. It is the
# only local evidence of what is live on the account; there is no API for it.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$root/skills"
code_dir="$HOME/.claude/skills"
cache_root="$HOME/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin"

status=0

echo "== Claude Code ($code_dir)"
if [ -L "$code_dir" ]; then
  echo "   symlink -> $(readlink "$code_dir") (in sync by construction)"
elif [ -d "$code_dir" ]; then
  for d in "$src"/*/; do
    name=$(basename "$d")
    if [ ! -d "$code_dir/$name" ]; then
      echo "   MISSING: $name"; status=1
    elif ! diff -rq "$d" "$code_dir/$name" >/dev/null 2>&1; then
      echo "   DRIFT:   $name"; status=1
    fi
  done
  for d in "$code_dir"/*/; do
    name=$(basename "$d")
    [ -d "$src/$name" ] || { echo "   EXTRA:   $name (not in repo)"; status=1; }
  done
  [ $status -eq 0 ] && echo "   all skills identical"
else
  echo "   not present"
fi

echo
echo "== Account skills (chat / Desktop / Cowork / Design)"
cache=$(find "$cache_root" -maxdepth 3 -type d -name skills 2>/dev/null | head -1)
if [ -z "$cache" ]; then
  echo "   no local cache found - open Claude Desktop once to populate it"
  exit $status
fi
echo "   cache: $cache"
for d in "$src"/*/; do
  name=$(basename "$d")
  if [ ! -d "$cache/$name" ]; then
    echo "   NOT UPLOADED: $name"
  elif diff -rq "$d" "$cache/$name" >/dev/null 2>&1; then
    echo "   in sync:      $name"
  else
    echo "   DRIFT:        $name  (repo differs from what is live)"; status=1
  fi
done
echo
echo "   account-only (installed from Anthropic, or uploaded but not in this repo):"
for d in "$cache"/*/; do
  name=$(basename "$d")
  [ -d "$src/$name" ] || echo "     - $name"
done

exit $status
