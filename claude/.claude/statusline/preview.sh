#!/usr/bin/env bash
# Render statusline.sh against every fixture, so a change can be eyeballed
# without starting a Claude Code session.
#
#   ./statusline/preview.sh              all fixtures
#   ./statusline/preview.sh edge         one fixture
#
# Exits non-zero if any fixture makes the script fail or print nothing, which
# is the failure mode that shows up in Claude Code as a blank status line.

set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script="$here/statusline.sh"

# Claude Code exports COLUMNS before each run; the script justifies against it.
# Pin a width here so the preview is reproducible rather than depending on
# whatever terminal happens to be rendering it. Override to check narrow cases:
#   COLUMNS=60 ./statusline/preview.sh
export COLUMNS=${COLUMNS:-120}
printf '\033[2m(rendering at COLUMNS=%s)\033[0m\n\n' "$COLUMNS"

fixtures=("$@")

if (( ${#fixtures[@]} == 0 )); then
  for f in "$here"/fixtures/*.json; do
    fixtures+=("$(basename "$f" .json)")
  done
fi

fail=0
for name in "${fixtures[@]}"; do
  file="$here/fixtures/${name}.json"
  if [[ ! -f $file ]]; then
    printf '%s: no such fixture\n' "$name" >&2
    fail=1
    continue
  fi

  printf '\033[1m── %s ──\033[0m\n' "$name"
  # Rebase the rate-limit reset times onto now. They are epoch seconds, so a
  # fixture with a fixed value drifts into the past and the countdown silently
  # disappears from the preview.
  out=$(jq --argjson now "$(date +%s)" '
      if .rate_limits.five_hour   then .rate_limits.five_hour.resets_at   = $now + 7200    else . end
    | if .rate_limits.seven_day   then .rate_limits.seven_day.resets_at   = $now + 259200  else . end
    | if .rate_limits.spend_limit then .rate_limits.spend_limit.resets_at = $now + 1209600 else . end
  ' "$file" 2>/dev/null | "$script")
  status=$?
  printf '%s\n\n' "$out"

  if (( status != 0 )); then
    printf '%s: exited %d\n' "$name" "$status" >&2
    fail=1
  elif [[ -z ${out//[$' \n']/} ]]; then
    printf '%s: printed nothing (status line would be blank)\n' "$name" >&2
    fail=1
  fi
done

# The empty and malformed cases must still print something rather than blanking.
for probe in '' 'not json' '{}'; do
  out=$(printf '%s' "$probe" | "$script")
  if [[ -z ${out//[$' \n']/} ]]; then
    printf 'degenerate input %q produced a blank status line\n' "$probe" >&2
    fail=1
  fi
done

exit $fail
