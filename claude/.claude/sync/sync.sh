#!/usr/bin/env bash
# SessionStart hook: brings the config repos listed in ./repos up to date, and
# caches their open PRs for the status line, which shows everything pending.
#
# Silent by design. Only a session started inside one of those repos gets a
# summary in its context; anywhere else the work runs in the background and
# prints nothing, so unrelated sessions never hear about it.
#
#   sync.sh          as the hook: session JSON on stdin
#   sync.sh --now    run in the foreground and print the summary
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-sync"
mkdir -p "$cache"

# Never prompt and never hang: this runs unattended, possibly offline.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5"

repos() {
  local r
  while IFS= read -r r; do
    [[ -z $r || $r == \#* ]] && continue
    r=${r/#\~/$HOME}
    [[ -d $r/.git ]] && (cd "$r" && pwd -P)
  done <"$here/repos"
}

# Fast-forward only when nothing local could conflict: clean tree, nothing
# unpushed. Anything else is left for a person to sort out.
pull() {
  local r=$1 counts behind ahead
  git -C "$r" fetch --quiet --prune 2>/dev/null || return
  counts=$(git -C "$r" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null) || return
  read -r behind ahead <<<"$counts"
  ((behind > 0 && ahead == 0)) || return
  [[ -z $(git -C "$r" status --porcelain) ]] || return
  git -C "$r" merge --ff-only --quiet '@{u}' 2>/dev/null &&
    echo "$r pulled $behind commit(s)" >>"$cache/pulled"
}

# "<repo>\t#1 #4" per repo. On a gh failure (offline, logged out) the previous
# line is kept, so the status line goes stale rather than falsely clean.
prs() {
  local r line old=$cache/prs new
  new=$(mktemp "$cache/prs.XXXX")
  while IFS= read -r r; do
    if line=$(cd "$r" && gh pr list --state open --json number -q 'map("#\(.number)") | join(" ")' 2>/dev/null); then
      printf '%s\t%s\n' "$r" "$line" >>"$new"
    else
      grep -F "$r"$'\t' "$old" 2>/dev/null >>"$new"
    fi
  done < <(repos)
  mv "$new" "$old"
}

sync_all() {
  local r
  # One run at a time; a second session starting meanwhile just skips. A lock
  # older than ten minutes belongs to a run that was killed.
  find "$cache/lock" -maxdepth 0 -mmin +10 -exec rmdir {} \; 2>/dev/null
  mkdir "$cache/lock" 2>/dev/null || return
  trap 'rmdir "$cache/lock"' EXIT
  while IFS= read -r r; do pull "$r"; done < <(repos)
  prs
}

summary() {
  local r name dirty counts behind ahead prs out=()
  while IFS= read -r r; do
    name=${r##*/}; name=${name#.}
    dirty=$(git -C "$r" status --porcelain | wc -l | tr -d ' ')
    counts=$(git -C "$r" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null) || counts='0 0'
    read -r behind ahead <<<"$counts"
    prs=$(grep -F "$r"$'\t' "$cache/prs" 2>/dev/null | cut -f2)
    local bits=()
    ((dirty > 0)) && bits+=("$dirty uncommitted file(s)")
    ((ahead > 0)) && bits+=("$ahead unpushed commit(s)")
    ((behind > 0)) && bits+=("$behind commit(s) behind, not pulled because of local changes")
    [[ -n $prs ]] && bits+=("open PRs $prs")
    ((${#bits[@]})) && out+=("- $name ($r): $(printf '%s; ' "${bits[@]}" | sed 's/; $//')")
  done < <(repos)
  [[ -e ~/.claude/settings.json && ! -L ~/.claude/settings.json ]] &&
    out+=("- ~/.claude/settings.json is no longer a link into the skills repo; re-stow it")
  if [[ -s $cache/pulled ]]; then
    while IFS= read -r r; do out+=("- pulled: $r"); done <"$cache/pulled"
    rm -f "$cache/pulled"
  fi
  ((${#out[@]})) || return 0
  echo "Config repos (from ~/.claude/sync/sync.sh). Mention this only if the user's"
  echo "task touches these repos or they ask:"
  printf '%s\n' "${out[@]}"
}

case ${1:-} in
  --now) sync_all; summary; exit 0 ;;
  --bg)  sync_all; exit 0 ;;
esac

cwd=$(jq -r '.cwd // empty' 2>/dev/null)
top=$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null) && top=$(cd "$top" && pwd -P)
if [[ -n $top ]] && repos | grep -qxF "$top"; then
  sync_all
  summary
else
  # Detached and with every stream closed, so Claude Code does not wait on it.
  nohup "$0" --bg </dev/null >/dev/null 2>&1 &
fi
exit 0
