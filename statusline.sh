#!/bin/bash
# Claude Code status line. Dependencies: jq, git. Runs on macOS (BSD) and Linux (GNU).

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
mkdir -p "$CACHE_DIR"

# Locales for displaying numbers and dates, in POSIX precedence. On macOS the region set in
# System Settings comes before LANG, which terminals often set to en_US regardless.
fallback_locale() {
  local apple region
  if [ "$(uname)" = Darwin ] && apple=$(defaults read -g AppleLocale 2>/dev/null); then
    apple=${apple%%@*}; region=${apple#*_}
    # "en_IT" has no POSIX locale of its own: any locale of the same region has its formats.
    locale -a | grep -m1 -x "${apple}.UTF-8" && return
    locale -a | grep -m1 "_${region}.UTF-8$" && return
  fi
  echo "${LANG:-C}"
}
# "<thousands separator>|<day and month format>", cached for an hour per environment.
locale_formats() {
  local cache num_loc time_loc sep day
  cache="$CACHE_DIR/locale-$(printf '%s|' "${LC_ALL:-}" "${LC_NUMERIC:-}" "${LC_TIME:-}" "${LANG:-}" | cksum | cut -d' ' -f1)"
  if [ -f "$cache" ] && [ $(( $(date +%s) - $(mtime "$cache") )) -lt 3600 ]; then
    cat "$cache"; return
  fi
  num_loc=${LC_ALL:-${LC_NUMERIC:-}}; time_loc=${LC_ALL:-${LC_TIME:-}}
  if [ -z "$num_loc" ] || [ -z "$time_loc" ]; then
    local fb; fb=$(fallback_locale)
    num_loc=${num_loc:-$fb}; time_loc=${time_loc:-$fb}
  fi
  sep=$(LC_ALL=$num_loc locale thousands_sep 2>/dev/null)
  # The locale's short date without the year: %d/%m/%Y -> %d/%m, %Y-%m-%d -> %m-%d.
  day=$(LC_ALL=$time_loc locale d_fmt 2>/dev/null); day=${day//%Y/}; day=${day//%y/}
  day=${day#[!%]}; day=${day%[!a-zA-Z]}
  echo "${sep:-,}|${day:-%m/%d}" | tee "$cache"
}

# GNU and BSD spell file mtime and epoch formatting differently.
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
fmt_epoch() { date -d "@$1" "$2" 2>/dev/null || date -r "$1" "$2" 2>/dev/null; }

IFS='|' read -r THOUSANDS_SEP DAY_FMT <<<"$(locale_formats)"

# From here on, C: printf and awk read decimals with the locale's separator, so "10.2" is
# invalid under it_IT. LC_ALL, because it overrides LC_NUMERIC.
export LC_ALL=C

# One jq call for every field: the status line refreshes every few seconds.
IFS=$'\x1f' read -r MODEL EFFORT_RAW THINKING DIR GIT_WORKTREE IN_TOK CTX_SIZE CTX_PCT \
  FIVE_H FIVE_H_RESET SEVEN_D SEVEN_D_RESET COST CACHE_EXP CACHE_SEEN < <(jq -r '[
    .model.display_name // "?", .effort.level // "", .thinking.enabled // false,
    .workspace.current_dir // .cwd // "?", .workspace.git_worktree // "",
    .context_window.total_input_tokens // 0, .context_window.context_window_size // 200000,
    .context_window.used_percentage // 0,
    .rate_limits.five_hour.used_percentage // "", .rate_limits.five_hour.resets_at // "",
    .rate_limits.seven_day.used_percentage // "", .rate_limits.seven_day.resets_at // "",
    .cost.total_cost_usd // 0,
    .prompt_cache.expires_at // "", .prompt_cache.caching_observed // false
  ] | map(tostring | gsub("[\u0000-\u001f\u007f]"; " ")) | join("\u001f")')
# Defaults again, for input jq could not parse.
: "${IN_TOK:=0}" "${CTX_SIZE:=200000}" "${CTX_PCT:=0}" "${COST:=0}"
CTX_PCT=${CTX_PCT%%.*}

RESET=$'\033[0m'; RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; CYAN=$'\033[36m'
SEP="${DIM} │ ${RESET}"

case "$EFFORT_RAW" in
  low) EFF="L" ;;
  medium) EFF="M" ;;
  high) EFF="H" ;;
  xhigh) EFF="XH" ;;
  max) EFF="MAX" ;;
  *) EFF="" ;;
esac
[ -z "$EFF" ] && [ "$THINKING" = "true" ] && EFF="think"

MODEL_SEG="${MODEL:-?}"
[ -n "$EFF" ] && MODEL_SEG="${MODEL_SEG}·${EFF}"

DIR=${DIR:-?}
DIRNAME="${DIR##*/}"
[ -z "$DIRNAME" ] && DIRNAME="/"
[ -n "$GIT_WORKTREE" ] && DIRNAME="⎇ ${DIRNAME}"

# Git info (branch, staged/modified file counts, line diff), cached 5s per directory
# to avoid shelling out to git on every statusline refresh.
GIT_SEG=""
CACHE_FILE="$CACHE_DIR/git-$(printf '%s' "$DIR" | cksum | cut -d' ' -f1)"
CACHE_MAX_AGE=5
cache_is_stale() {
  [ ! -f "$CACHE_FILE" ] || \
  [ $(( $(date +%s) - $(mtime "$CACHE_FILE") )) -ge $CACHE_MAX_AGE ]
}
if cache_is_stale; then
  # Only commands that never write .git/index, so a refresh can't collide with a
  # commit running in the same repo ("index.lock exists").
  if st=$(git -C "$DIR" --no-optional-locks status --porcelain=v2 --branch --untracked-files=no 2>/dev/null); then
    read -r branch staged modified < <(awk '
      $2 == "branch.oid" {oid = substr($3, 1, 7)}
      $2 == "branch.head" {head = $3}
      /^[12u] / {if (substr($2, 1, 1) != ".") s++; if (substr($2, 2, 1) != ".") m++}
      END {print (head == "(detached)" ? oid : head), s + 0, m + 0}' <<<"$st")
    read -r added removed < <(git -C "$DIR" diff-index --numstat HEAD 2>/dev/null | \
      awk '{if ($1 ~ /^[0-9]+$/) a+=$1; if ($2 ~ /^[0-9]+$/) d+=$2} END{print a+0, d+0}')
    # Commits on no remote branch, so new branches without an upstream count too.
    # Skipped in repos without remotes, where every commit would count.
    ahead=0
    [ -n "$(git -C "$DIR" remote 2>/dev/null)" ] && \
      ahead=$(git -C "$DIR" rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)
    echo "$branch|$staged|$modified|$added|$removed|$ahead" > "$CACHE_FILE"
  else
    echo "|||||" > "$CACHE_FILE"
  fi
fi
IFS='|' read -r branch staged modified added removed ahead < "$CACHE_FILE"

if [ -n "$branch" ]; then
  status=""
  [ "$staged" -gt 0 ] 2>/dev/null && status="${GRN}+${staged}${RESET}"
  [ "$modified" -gt 0 ] 2>/dev/null && status="${status}${YEL}~${modified}${RESET}"
  [ "${ahead:-0}" -gt 0 ] 2>/dev/null && status="${status:+$status }${YEL}↑${ahead}${RESET}"
  diffstat=""
  if [ "${added:-0}" -gt 0 ] || [ "${removed:-0}" -gt 0 ]; then
    diffstat=" ${DIM}(${RESET}${GRN}+${added:-0}${RESET}${DIM}/${RESET}${RED}-${removed:-0}${RESET}${DIM})${RESET}"
  fi
  GIT_SEG=" ${DIM}${branch}${RESET}${status:+ $status}${diffstat}"
fi

LOC_SEG="${DIRNAME}${GIT_SEG}"

# Absolute token count (no abbreviation), with the locale's thousands separator
thousands() {
  awk -v n="$1" -v s="$THOUSANDS_SEP" 'BEGIN {
    while (length(n) > 3) { r = s substr(n, length(n) - 2) r; n = substr(n, 1, length(n) - 3) }
    print n r }'
}
IN_TOK_FMT=$(thousands "$IN_TOK")

# Abbreviated context window size: 200000 -> 200K, 1000000 -> 1M
abbreviate() {
  local n=$1
  if [ "$n" -ge 1000000 ]; then
    local v; v=$(awk -v n="$n" 'BEGIN{printf "%.1f", n/1000000}'); v=${v%.0}
    printf '%sM' "$v"
  elif [ "$n" -ge 1000 ]; then
    local v; v=$(awk -v n="$n" 'BEGIN{printf "%.1f", n/1000}'); v=${v%.0}
    printf '%sK' "$v"
  else
    printf '%s' "$n"
  fi
}
CTX_SIZE_FMT=$(abbreviate "$CTX_SIZE")

ctx_color="$GRN"
[ "$CTX_PCT" -ge 70 ] 2>/dev/null && ctx_color="$YEL"
[ "$CTX_PCT" -ge 90 ] 2>/dev/null && ctx_color="$RED"

CTX_SEG="ctx ${ctx_color}${IN_TOK_FMT}/${CTX_SIZE_FMT} ${CTX_PCT}%${RESET}"

# Prompt cache countdown: dim while far, yellow in the last 15 minutes, red in
# the last 5. Past expiry the next message re-reads the whole context at full price.
if [ -n "$CACHE_EXP" ]; then
  left=$(( $(printf '%.0f' "$CACHE_EXP") - $(date +%s) ))
fi
if [ "${left:-0}" -gt 0 ]; then
  if [ "$left" -ge 60 ]; then left_fmt="$(( left / 60 ))m"; else left_fmt="${left}s"; fi
  c="$DIM"; [ "$left" -le 900 ] && c="$YEL"; [ "$left" -le 300 ] && c="$RED"
  CTX_SEG="${CTX_SEG} ${DIM}·${RESET} ${c}cache ${left_fmt}${RESET}"
elif [ "$CACHE_SEEN" = "true" ]; then
  CTX_SEG="${CTX_SEG} ${DIM}· cache ✗${RESET}"
fi

RATE_SEG=""
if [ -n "$FIVE_H" ] || [ -n "$SEVEN_D" ]; then
  if [ -n "$FIVE_H" ]; then
    p=$(printf '%.0f' "$FIVE_H")
    c="$GRN"; [ "$p" -ge 70 ] 2>/dev/null && c="$YEL"; [ "$p" -ge 90 ] 2>/dev/null && c="$RED"
    reset_str=""
    [ -n "$FIVE_H_RESET" ] && reset_str=" ${DIM}($(fmt_epoch "$(printf '%.0f' "$FIVE_H_RESET")" '+%H:%M'))${RESET}"
    RATE_SEG="5h ${c}${p}%${RESET}${reset_str}"
  fi
  if [ -n "$SEVEN_D" ]; then
    p=$(printf '%.0f' "$SEVEN_D")
    c="$GRN"; [ "$p" -ge 70 ] 2>/dev/null && c="$YEL"; [ "$p" -ge 90 ] 2>/dev/null && c="$RED"
    reset_str=""
    [ -n "$SEVEN_D_RESET" ] && reset_str=" ${DIM}($(fmt_epoch "$(printf '%.0f' "$SEVEN_D_RESET")" "+$DAY_FMT %H:%M"))${RESET}"
    RATE_SEG="${RATE_SEG:+$RATE_SEG${SEP}}7d ${c}${p}%${RESET}${reset_str}"
  fi
fi

COST_FMT=$(printf '$%.2f' "$COST")
COST_SEG="${DIM}${COST_FMT}${RESET}"

# Linear projection of the 7-day usage at reset time, at the current pace.
# Hidden in the first 6h of the window, where the estimate is too noisy.
PROJ_SEG=""
if [ -n "$SEVEN_D" ] && [ -n "$SEVEN_D_RESET" ]; then
  proj=$(awk -v u="$SEVEN_D" -v r="$SEVEN_D_RESET" -v now="$(date +%s)" \
    'BEGIN{e=604800-(r-now); if (e>=21600) printf "%.0f", u*604800/e}')
  if [ -n "$proj" ]; then
    c="$GRN"; [ "$proj" -ge 90 ] && c="$YEL"; [ "$proj" -gt 100 ] && c="$RED"
    PROJ_SEG="7d→ ${c}${proj}%${RESET}"
  fi
fi

LINE1="${CYAN}${MODEL_SEG}${RESET}${SEP}${LOC_SEG}${SEP}${CTX_SEG}"

LINE2="$COST_SEG"
[ -n "$PROJ_SEG" ] && LINE2="${PROJ_SEG}${SEP}${LINE2}"
[ -n "$RATE_SEG" ] && LINE2="${RATE_SEG}${SEP}${LINE2}"

# printf, not echo -e: a directory or branch name must not be read as escape sequences.
printf '%s\n' "$LINE1" "$LINE2"
