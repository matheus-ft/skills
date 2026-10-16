#!/usr/bin/env bash
# Claude Code status line. Source of truth: ~/Projects/skills/claude/.claude/statusline/
# Wired up via "statusLine" in ~/.claude/settings.json.
#
# Reads the session JSON on stdin (schema: statusline/README.md) and prints two
# justified lines:
#
#   repo ⎇ branch                              Opus·high  Ctx ███░░ 28% 144k left
#   @agent                        5h 46% ⟳55m · 7d 17% ⟳4d2h │ $8.93 · 24h31m · +698/-25
#
# Left is where the session is and what is running; right is what it is costing.
#
# Design rule: default states stay silent. A segment appears only when it is
# notable (fast mode on, thinking off, tree dirty), so the line stays scannable.
#
# Vim mode and permission mode are deliberately absent: Claude Code renders both
# in its own footer, directly below this line.

input=$(cat)

# One jq pass. Fields are joined with US (0x1f) rather than a tab: tab counts as
# IFS whitespace, so bash would collapse runs of it and silently shift every
# value left whenever an optional field was absent.
IFS=$'\x1f' read -r \
  model effort ctx_pct ctx_size ctx_in ctx_out \
  fast thinking style \
  cur_dir proj_dir repo_name git_wt wt_name \
  pr_num pr_state \
  cost \
  h5_pct h5_reset d7_pct d7_reset spend_pct \
  cache_warm \
  agent_name \
  <<< "$(printf '%s' "$input" | jq -r '
    def s: if . == null then "" else tostring end;
    [ .model.display_name, .effort.level,
      .context_window.used_percentage, .context_window.context_window_size,
      .context_window.total_input_tokens, .context_window.total_output_tokens,
      .fast_mode, .thinking.enabled, .output_style.name,
      .workspace.current_dir, .workspace.project_dir, .workspace.repo.name,
      .workspace.git_worktree, .worktree.name,
      .pr.number, .pr.review_state,
      .cost.total_cost_usd,
      .rate_limits.five_hour.used_percentage, .rate_limits.five_hour.resets_at,
      .rate_limits.seven_day.used_percentage, .rate_limits.seven_day.resets_at,
      .rate_limits.spend_limit.used_percentage,
      .prompt_cache.warm,
      .agent.name
    ] | map(s) | join("\u001f")' 2>/dev/null)"

# ---------- colours ----------
R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'
RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'
BLU=$'\033[34m'; MAG=$'\033[35m'; CYA=$'\033[36m'

dot="${D} · ${R}"
bar_sep="${D} │ ${R}"

# ---------- helpers ----------

# Printable width, ignoring the ANSI escapes. Done in pure bash rather than by
# shelling out to sed, because this runs on every status line refresh.
vis_len() {
  local s=$1 out=''
  while [[ $s == *$'\033['* ]]; do
    out+=${s%%$'\033['*}
    s=${s#*$'\033['}
    s=${s#*m}
  done
  out+=$s
  printf '%s' "${#out}"
}

# Columns to leave free at the right edge. Claude Code renders this content
# inside its own spacing, so COLUMNS is more than the width actually available
# and justifying to the very end pushes the tail off screen. There is no field
# that reports the usable width, so this is a margin rather than a calculation:
# raise it if the right-hand side still runs off.
margin=${STATUSLINE_MARGIN:-6}

# Print left and right justified across the terminal. Claude Code cannot be
# asked for the width from in here (it captures stdout rather than handing over
# the tty) but it exports COLUMNS before each run.
render() {
  local left=$1 right=$2 cols=${COLUMNS:-100} pad
  pad=$(( cols - margin - $(vis_len "$left") - $(vis_len "$right") ))
  # Too narrow to justify, or a non-UTF-8 locale made the widths meaningless:
  # fall back to a single space so the line degrades instead of wrapping badly.
  (( pad < 1 )) && pad=1
  if [[ -z $right ]]; then
    printf '%s\n' "$left"
  else
    printf '%s%*s%s\n' "$left" "$pad" '' "$right"
  fi
}

# Width still free for a right-hand side, given the left-hand side beside it.
room_for() {
  local cols=${COLUMNS:-100}
  printf '%s' $(( cols - margin - $(vis_len "$1") - 1 ))
}

# Percentages arrive as floats (57.99999999999999 is a real observed value), so
# round rather than truncating towards zero.
round() {
  local n=${1:-}
  [[ -z $n ]] && { printf '0'; return; }
  printf '%.0f' "$n" 2>/dev/null || printf '%s' "${n%%.*}"
}

# Join the segments that are present, so an absent one leaves no dangling
# separator at either end.
join_with() {
  local glue=$1 out='' seg
  shift
  for seg in "$@"; do
    [[ -z $seg ]] && continue
    if [[ -z $out ]]; then out=$seg; else out+="${glue}${seg}"; fi
  done
  printf '%s' "$out"
}

# Human-readable countdown to an epoch-seconds timestamp.
until_reset() {
  local target=${1%%.*} now delta d h m
  [[ -z $target ]] && return
  now=$(date +%s); delta=$(( target - now ))
  (( delta <= 0 )) && return
  d=$(( delta / 86400 )); h=$(( (delta % 86400) / 3600 )); m=$(( (delta % 3600) / 60 ))
  if   (( d > 0 )); then printf '%dd%dh' "$d" "$h"
  elif (( h > 0 )); then printf '%dh%02dm' "$h" "$m"
  else                   printf '%dm' "$m"; fi
}

# Colour by how alarming a 0-100 percentage is.
pct_colour() {
  local p
  p=$(round "$1")
  (( p >= 90 )) && { printf '%s' "$RED"; return; }
  (( p >= 70 )) && { printf '%s' "$YEL"; return; }
  printf '%s' "$GRN"
}

# Usage bar. The absolute figures beside it carry the precision, so the bar is
# left as a plain fill rather than having the percentage written through it.
bar() {
  local p=$1 width=${2:-10} filled i out=''
  (( p < 0 )) && p=0
  (( p > 100 )) && p=100
  filled=$(( (p * width + 50) / 100 ))
  for (( i = 0; i < width; i++ )); do
    if (( i < filled )); then out+='█'; else out+='░'; fi
  done
  printf '%s' "$out"
}

# 15500 -> 15k, 1000000 -> 1M, 1200000 -> 1.2M
short_tokens() {
  local n=${1%%.*}
  [[ -z $n ]] && { printf '0'; return; }
  if   (( n >= 1000000 && n % 1000000 == 0 )); then printf '%dM' $(( n / 1000000 ))
  elif (( n >= 1000000 )); then printf '%d.%dM' $(( n / 1000000 )) $(( (n % 1000000) / 100000 ))
  elif (( n >= 1000 ));    then printf '%dk' $(( n / 1000 ))
  else                          printf '%d' "$n"; fi
}

# ============ line 1 left: where am I ============
dir=${cur_dir:-$PWD}

# Branch, and whether the tree is dirty. --no-optional-locks keeps this a
# read-only look at the repo.
branch=''
dirty=''
if branch=$(git --no-optional-locks -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null) \
   || branch=$(git --no-optional-locks -C "$dir" rev-parse --short HEAD 2>/dev/null); then
  git --no-optional-locks -C "$dir" diff --quiet --ignore-submodules HEAD 2>/dev/null || dirty="${YEL}●${R}"
fi

l1_left=()
if [[ -n $branch ]]; then
  # In a repo, the repo name beats the path: it stays short however deep the cwd
  # is. repo_name comes from the origin remote and is absent without one, so fall
  # back to the launch dir.
  if   [[ -n $repo_name ]]; then name=$repo_name
  elif [[ -n $proj_dir  ]]; then name=${proj_dir##*/}
  else                           name=${dir##*/}
  fi
  # Append where we are inside the repo, so the name alone means the root.
  # --show-prefix gives exactly that, "" at the root and "sub/dir/" below it.
  prefix=$(git --no-optional-locks -C "$dir" rev-parse --show-prefix 2>/dev/null)
  [[ -n $prefix ]] && name+="${D}/${prefix%/}${R}${BLU}${B}"
  l1_left+=("${BLU}${B}${name}${R}")
  # ⑂ instead of ⎇ marks a worktree branch, so it is obvious at a glance that
  # this is not the main checkout.
  if [[ -n $wt_name || -n $git_wt ]]; then
    l1_left+=("${MAG}⑂ ${branch}${R}${dirty}")
  else
    l1_left+=("${GRN}⎇ ${branch}${R}${dirty}")
  fi
else
  # Outside a repo there is no name to show, so fall back to the path.
  home_rel=${dir/#$HOME/'~'}
  l1_left+=("${BLU}${B}${home_rel}${R}")
fi

# Open PR for this branch, coloured by review state.
if [[ -n $pr_num ]]; then
  case $pr_state in
    approved)          pc=$GRN ;;
    changes_requested) pc=$RED ;;
    draft)             pc=$D   ;;
    *)                 pc=$YEL ;;
  esac
  l1_left+=("${pc}⇡#${pr_num}${R}")
fi

# ============ line 1 right: model and context ============
m="${CYA}${model:-?}${R}"
[[ -n $effort ]] && m+="${D}·${R}${YEL}${effort}${R}"
[[ $fast == true ]] && m+=" ${MAG}⚡${R}"
[[ $thinking == false ]] && m+=" ${D}(no think)${R}"
[[ -n $style && $style != default ]] && m+=" ${D}${style}${R}"

if [[ -n $ctx_pct ]]; then
  p=$(round "$ctx_pct")
  c=$(pct_colour "$p")
  # Used against the window size, rather than what is left: the absolute figures
  # are what the bar cannot tell you, and the window is 200k or 1M depending on
  # the model, which is worth seeing.
  used=$(( ${ctx_in:-0} + ${ctx_out:-0} ))
  ctx="${D}Ctx${R} ${c}$(bar "$p")${R}${D} $(short_tokens "$used")/$(short_tokens "${ctx_size:-200000}")${R}"
else
  ctx="${D}Ctx $(bar 0) --/$(short_tokens "${ctx_size:-200000}")${R}"
fi

# ============ line 2 left: what is running ============
l2_left=()
[[ -n $agent_name ]] && l2_left+=("${CYA}@${agent_name}${R}")
# A cold prompt cache means the next turn re-reads the whole context.
[[ $cache_warm == false ]] && l2_left+=("${YEL}cache cold${R}")

# Configuring any status line makes Claude Code drop its footer keyboard hints,
# and there is no setting to keep them. Put the discoverability one back — but
# on Claude Code's own terms: it only ever showed "? for shortcuts" when the
# footer row was otherwise empty, as filler rather than as a fixture. Same rule
# here, so it costs nothing whenever there is something real to say.
#
# "esc to interrupt" is not reproducible at any price: the payload carries no
# field saying whether a turn is currently in flight.
(( ${#l2_left[@]} == 0 )) && l2_left+=("${D}? for shortcuts${R}")

# ============ line 2 right: what it is costing ============

# Rate limits: share of the window used, and how long until it resets.
limits=()
if [[ -n $h5_pct ]]; then
  c=$(pct_colour "$h5_pct"); t=$(until_reset "$h5_reset")
  limits+=("${D}5h${R} ${c}$(round "$h5_pct")%${R}${t:+${D} ⟳${t}${R}}")
fi
if [[ -n $d7_pct ]]; then
  c=$(pct_colour "$d7_pct"); t=$(until_reset "$d7_reset")
  limits+=("${D}7d${R} ${c}$(round "$d7_pct")%${R}${t:+${D} ⟳${t}${R}}")
fi
if [[ -n $spend_pct ]]; then
  c=$(pct_colour "$spend_pct")
  limits+=("${D}spend${R} ${c}$(round "$spend_pct")%${R}")
fi

# This session's estimated cost. Elapsed time and lines changed used to sit here
# too and were dropped: the clock is wall time including every idle stretch, and
# the line counts are a `git diff` away.
session=()
if [[ -n $cost ]]; then
  money=$(printf '%.2f' "$cost" 2>/dev/null) || money='0.00'
  session+=("${GRN}\$${money}${R}")
fi

l1l=$(join_with ' ' "${l1_left[@]}")
l2l=$(join_with "$dot" "${l2_left[@]}")

# Line two's right-hand side, richest form that fits: the session group sheds
# from its tail first, leaving the rate limits as the last thing to go.
avail=$(room_for "$l2l")
limits_str=$(join_with "$dot" "${limits[@]}")
r2=''
for (( keep = ${#session[@]}; keep >= 0; keep-- )); do
  cand=$(join_with "$bar_sep" "$limits_str" "$(join_with "$dot" "${session[@]:0:$keep}")")
  if (( $(vis_len "$cand") <= avail )); then r2=$cand; break; fi
done
# Even the limits alone do not fit: show what there is and let render fall back.
[[ -z $r2 ]] && r2=$limits_str

render "$l1l" "$(join_with '  ' "$m" "$ctx")"
render "$l2l" "$r2"
