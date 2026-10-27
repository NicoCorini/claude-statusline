#!/bin/bash
# Claude Code subagent panel rows. Dependencies: jq, git. Runs on macOS (BSD) and Linux (GNU).
# Row: label · model·effort · ctx % · [⎇ worktree] branch

input=$(cat)

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
mkdir -p "$CACHE_DIR"

RESET=$'\033[0m'; RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; CYAN=$'\033[36m'

# GNU and BSD spell file mtime differently.
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# "<worktree name>|<branch>" for a directory, cached 5s per directory: the panel
# refreshes every few seconds and several subagents often share a directory.
git_location() {
  local dir=$1 cache wt="" branch="" git_dir common_dir
  cache="$CACHE_DIR/subagent-git-$(printf '%s' "$dir" | cksum | cut -d' ' -f1)"
  if [ -f "$cache" ] && [ $(( $(date +%s) - $(mtime "$cache") )) -le 5 ]; then
    cat "$cache"; return
  fi
  if git_dir=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null); then
    common_dir=$(cd "$dir" && cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
    # A linked worktree has its own git dir, distinct from the shared common dir.
    [ "$git_dir" != "$common_dir" ] && wt=$(basename "$(git -C "$dir" rev-parse --show-toplevel)")
    branch=$(git -C "$dir" branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
  fi
  echo "$wt|$branch" | tee "$cache"
}

while IFS=$'\x1f' read -r id label status model effort tokens ctx_size cwd; do
  case "$effort" in
    low) eff="L" ;; medium) eff="M" ;; high) eff="H" ;; xhigh) eff="XH" ;; max) eff="MAX" ;;
    *) eff="$effort" ;;
  esac
  model_seg="${model#claude-}"
  [ -n "$eff" ] && model_seg="${model_seg:+${model_seg}·}${eff}"
  [ -n "$model_seg" ] && model_seg="${CYAN}${model_seg}${RESET}"

  ctx_seg=""
  if [ "${ctx_size:-0}" -gt 0 ] 2>/dev/null; then
    pct=$(( ${tokens:-0} * 100 / ctx_size ))
    c="$GRN"; [ "$pct" -ge 70 ] && c="$YEL"; [ "$pct" -ge 90 ] && c="$RED"
    ctx_seg="ctx ${c}${pct}%${RESET}"
  fi

  loc_seg=""
  if [ -n "$cwd" ]; then
    IFS='|' read -r wt branch <<<"$(git_location "$cwd")"
    [ -n "$wt" ] && loc_seg="${YEL}⎇ ${wt}${RESET}"
    [ -n "$branch" ] && loc_seg="${loc_seg:+$loc_seg }${DIM}${branch}${RESET}"
  fi

  label_seg="$label"
  [ "$status" = "running" ] || label_seg="${DIM}${label}${RESET}"

  row="$label_seg"
  for seg in "$model_seg" "$ctx_seg" "$loc_seg"; do
    [ -n "$seg" ] && row="${row}${DIM} · ${RESET}${seg}"
  done
  printf '%s\x1f%s\n' "$id" "$row"
done < <(jq -r '
  # Truncate by characters, not bytes, and keep only plain numbers for the arithmetic.
  def short: if length > 48 then .[0:47] + "…" else . end;
  def num: (numbers | floor) // 0;
  .tasks[]? | [.id, (.label // .description // .name // "" | tostring | short), (.status // ""),
    (.model // ""), (.effort // ""), (.tokenCount | num), (.contextWindowSize | num), (.cwd // "")]
  | map(tostring | gsub("[\u0000-\u001f\u007f]"; " ")) | join("\u001f")' <<<"$input") |
  jq -cR 'split("\u001f") | {id: .[0], content: .[1]}'
