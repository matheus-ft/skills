#!/usr/bin/env bash
# Compare the skills copied from other repos (listed in upstream.tsv) with their
# upstream folders.
#   ./upstream.sh                  report; exit 1 if any is behind, 2 on an API error
#   ./upstream.sh pull [name ...]  replace those skills (default: all) with upstream's
#                                  latest, plus the repo licence when the folder has
#                                  none, and re-pin; review the result with git diff
# Needs an authenticated gh (GH_TOKEN in CI).
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
list="$root/upstream.tsv"

# gh would otherwise read the while-loops' stdin and swallow the remaining entries.
latest() { gh api "repos/$1/commits?path=$2&per_page=1" -q '.[0].sha' </dev/null; }

# "<path relative to the folder>\t<blob sha>" for every file under $2 in $1 at $3.
files_at() {
  gh api "repos/$1/git/trees/$3?recursive=1" </dev/null -q "
    .tree[] | select(.type == \"blob\") | select(.path | startswith(\"$2/\"))
    | [(.path | ltrimstr(\"$2/\")), .sha] | @tsv"
}

entries() { grep -v -e '^#' -e '^[[:space:]]*$' "$list"; }

check() {
  local status=0 dir repo src pin head f sha
  while IFS=$'\t' read -r dir repo src pin; do
    if ! head=$(latest "$repo" "$src") || [ -z "$head" ]; then
      echo "ERROR:   $dir: cannot read $src from $repo"
      status=2
      continue
    fi
    if [ "$pin" = "$head" ]; then
      echo "ok:      $dir @ ${head:0:7}"
    else
      echo "BEHIND:  $dir pinned ${pin:0:7}, upstream ${head:0:7}"
      [ $status -eq 0 ] && status=1
      [ "$pin" = - ] || gh api "repos/$repo/compare/$pin...$head" </dev/null -q "
        .files[] | select(.filename | startswith(\"$src/\"))
        | \"         \" + .status + \" \" + (.filename | ltrimstr(\"$src/\"))"
    fi
    # Edits made here since the pin: expected when deliberate, and lost on the next pull.
    [ "$pin" = - ] && continue
    while IFS=$'\t' read -r f sha; do
      if [ ! -f "$root/$dir/$f" ]; then
        echo "         local: missing $f"
      elif [ "$(git -C "$root" hash-object "$dir/$f")" != "$sha" ]; then
        echo "         local: edited $f"
      fi
    done < <(files_at "$repo" "$src" "$pin")
  done < <(entries)
  return $status
}

pull() {
  local dir repo src pin head tmp f sha
  while IFS=$'\t' read -r dir repo src pin; do
    if [ $# -gt 0 ] && ! printf '%s\n' "$@" | grep -qxF "$(basename "$dir")"; then
      continue
    fi
    head=$(latest "$repo" "$src") || return 2
    tmp=$(mktemp -d)
    files_at "$repo" "$src" "$head" >"$tmp/list" || return 2
    while IFS=$'\t' read -r f sha; do
      mkdir -p "$tmp/files/$(dirname "$f")"
      gh api "repos/$repo/contents/$src/$f?ref=$head" </dev/null \
        -H 'Accept: application/vnd.github.raw' >"$tmp/files/$f" || return 2
    done <"$tmp/list"
    # A folder without its own licence ships the repo's, so the notice travels with the copy.
    if ! cut -f1 "$tmp/list" | grep -qiE '^(licen[cs]e|copying)(\.[a-z]+)?$'; then
      f=$(gh api "repos/$repo/license" -q .path </dev/null) || return 2
      gh api "repos/$repo/contents/$f?ref=$head" </dev/null \
        -H 'Accept: application/vnd.github.raw' >"$tmp/files/$(basename "$f")" || return 2
    fi
    # Drop files upstream has removed since the pin; files that were never upstream's
    # (such as an added LICENSE) are left alone.
    if [ "$pin" != - ]; then
      while IFS=$'\t' read -r f sha; do
        cut -f1 "$tmp/list" | grep -qxF "$f" || rm -f "$root/$dir/$f"
      done < <(files_at "$repo" "$src" "$pin")
    fi
    mkdir -p "$root/$dir"
    cp -R "$tmp/files/." "$root/$dir/"
    rm -rf "$tmp"
    awk -v d="$dir" -v h="$head" 'BEGIN { FS = OFS = "\t" } $1 == d { $4 = h } { print }' \
      "$list" >"$list.tmp" && mv "$list.tmp" "$list"
    echo "pulled:  $dir @ ${head:0:7}"
  done < <(entries)
}

case "${1:-}" in
  pull) shift; pull "$@" ;;
  "") check ;;
  *) echo "usage: $0 [pull [name ...]]" >&2; exit 64 ;;
esac
