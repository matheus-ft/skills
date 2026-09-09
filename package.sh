#!/usr/bin/env bash
# Zip each skill for upload at claude.ai -> Settings -> Capabilities -> Skills.
# Usage: ./package.sh [skill-name ...]   (no args = all)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$root/skills"
out="$root/dist"

mkdir -p "$out"

names=("$@")
if [ ${#names[@]} -eq 0 ]; then
  names=()
  for d in "$src"/*/; do names+=("$(basename "$d")"); done
fi

for name in "${names[@]}"; do
  if [ ! -f "$src/$name/SKILL.md" ]; then
    echo "skip: $name (no SKILL.md)" >&2
    continue
  fi
  # Folder name must match the frontmatter `name:` or the upload is rejected.
  declared=$(awk '/^---$/{n++; next} n==1 && /^name:/{sub(/^name:[ \t]*/,""); print; exit}' "$src/$name/SKILL.md")
  if [ "$declared" != "$name" ]; then
    echo "FAIL: $name/SKILL.md declares name '$declared'" >&2
    exit 1
  fi
  rm -f "$out/$name.zip"
  (cd "$src" && zip -qr "$out/$name.zip" "$name" -x '*.DS_Store')
  echo "packaged: dist/$name.zip"
done
