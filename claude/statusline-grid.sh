#!/bin/bash
# Claude Code status line — a grid whose │ dividers line up from row to row
# (Catppuccin Mocha, heat-only). Wide ($COLUMNS ≥ 60), four columns:
#
#   t-g-skills ⑂  │ fix/sandtable-route-tactics !1 ?2
#   O 5.5 · m ▃   │ 10:08 · +12°  │ $0.60  │ 2.1.301
#   5H 18% ⟳2h33m │ WK 26% ⟳1h51m │ ○ 8%   │  99% ⟳38m |  cold 77k
#   gw 8080●      │ be 8000●      │ fe 5173○              (worktree ports)
#
# Narrow (a split pane), two grid rows only — Claude Code shows few status
# lines in a short pane: [model ctx cache] [5H WK cost] [gw be fe]; clock,
# temperature and version are left out. Under 40 columns timers shorten to
# the hour (⟳1h) and the model drops its dot; columns that still do not fit
# are dropped from the right. The place row's one divider sits on the grid's
# first. Palette is calm by default; saturated hues appear ONLY as a
# signal — a meter heating up (peach→red), a dirty tree, a worktree.
# bash 3.2-safe: integer printf only (%f floats break on macOS /bin/bash).
input=$(cat)

# Widths are counted in characters, which needs a UTF-8 locale.
for loc in C.UTF-8 en_US.UTF-8; do
  if LC_ALL=$loc true 2>/dev/null; then export LC_ALL=$loc; break; fi
done

cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
ver=$(echo "$input" | jq -r '.version // empty')
now=$(date +%s)
# Terminal width; anything under 60 is a split pane. $COLUMNS is frozen at
# the width Claude Code started with, so ask the terminal itself: walk up to
# the first ancestor that owns a tty (Claude Code) and read its live size.
# STATUSLINE_COLUMNS overrides both (tests).
cols=""
if [ -z "${STATUSLINE_COLUMNS:-}" ]; then
  p=$PPID
  for _ in 1 2 3 4 5; do
    read -r pp tty <<PS
$(ps -o ppid= -o tty= -p "$p" 2>/dev/null)
PS
    case "$tty" in
      ''|'?'|'??') ;;
      *) cols=$(stty size < "/dev/${tty#/dev/}" 2>/dev/null | cut -d' ' -f2); break ;;
    esac
    case "$pp" in ''|0|1) break ;; esac
    p=$pp
  done
fi
cols=${STATUSLINE_COLUMNS:-${cols:-${COLUMNS:-100}}}
case "$cols" in ''|*[!0-9]*|0) cols=100 ;; esac

# ── Palette — Catppuccin Mocha, treatment C (vivid accents) ─────────────
# Every field carries its own readable hue; grays are reserved for secondary
# detail only. Heat overrides a meter's hue → peach (≥70%) → red (≥90%).
RESET=$'\033[0m';   BOLD=$'\033[1m'
MAUVE=$'\033[38;5;183m'    # model      (#cba6f7)
SKY=$'\033[38;5;117m'      # clock      (#89dceb)
PEACH=$'\033[38;5;216m'    # temp · warm signal ≥70% · dirty tree (#fab387)
YELLOW=$'\033[38;5;223m'   # usage      (#f9e2af)
TEAL=$'\033[38;5;116m'     # context    (#94e2d5)
BLUE=$'\033[38;5;111m'     # dir        (#89b4fa)
GREEN=$'\033[38;5;114m'    # branch · cost (#a6e3a1)
PINK=$'\033[38;5;218m'     # worktree   (#f5c2e7)
LAVENDER=$'\033[38;5;147m' # cache warm (#b4befe)
RED=$'\033[38;5;211m'      # hot signal ≥90% (#f38ba8)
DIM=$'\033[38;5;103m'      # secondary readable — labels, version, branch type
CLK=$'\033[38;5;102m'      # reset clocks
FAINT=$'\033[38;5;60m'     # dividers — quiet, but visible on a dark theme
DOT="${FAINT} · ${RESET}"  # joins two values inside one cell
BAR="${FAINT} │ ${RESET}"  # divides cells

# Heat color for a percentage: the field's own hue ($2) until it crosses a
# threshold, then peach (≥70%) → red (≥90%).
heat() {
  p="$1"; base="$2"
  if   [ -z "$p" ];                  then printf '%s' "$base"
  elif [ "$p" -ge 90 ] 2>/dev/null;  then printf '%s' "$RED"
  elif [ "$p" -ge 70 ] 2>/dev/null;  then printf '%s' "$PEACH"
  else                                    printf '%s' "$base"; fi
}

# Cut $1 to $2 characters in the middle, so a branch keeps its distinctive end.
mid() {
  s="$1"; n="$2"
  if [ "${#s}" -le "$n" ]; then printf '%s' "$s"; return; fi
  k=$(( n - 1 )); a=$(( (k + 1) / 2 )); b=$(( k - a ))
  printf '%s…%s' "${s:0:$a}" "${s:$(( ${#s} - b ))}"
}

# ── Weather (cached, never blocks render) ──────────────────────────────
# Read whatever's cached now; if stale (>30m) kick off a background refresh
# for the *next* render. wttr.in format: "Location|+7°C|Drizzle".
WCACHE="$HOME/.claude/cache/statusline-weather"
WLOCK="$HOME/.claude/cache/statusline-weather.lock"
weather=""
[ -f "$WCACHE" ] && weather=$(cat "$WCACHE" 2>/dev/null)
stale=1
if [ -f "$WCACHE" ]; then
  mt=$(stat -c %Y "$WCACHE" 2>/dev/null || stat -f %m "$WCACHE" 2>/dev/null || echo 0)
  [ $((now - mt)) -lt 1800 ] && stale=0
fi
if [ "$stale" = 1 ]; then
  spawn=1
  if [ -f "$WLOCK" ]; then
    lmt=$(stat -c %Y "$WLOCK" 2>/dev/null || stat -f %m "$WLOCK" 2>/dev/null || echo 0)
    [ $((now - lmt)) -lt 60 ] && spawn=0   # refresh already in flight
  fi
  if [ "$spawn" = 1 ]; then
    touch "$WLOCK" 2>/dev/null
    ( w=$(curl -s --max-time 4 'wttr.in/?format=%l|%t|%C' 2>/dev/null)
      case "$w" in *"|"*) printf '%s' "$w" > "$WCACHE" ;; esac ) >/dev/null 2>&1 &
  fi
fi

# Weather → temp only (location name dropped so shared screenshots don't
# deanonymize; cache format is "Location|+7°C|Condition"). "+12°C" → "+12°".
wtemp=""
if [ -n "$weather" ]; then rest=${weather#*|}; wtemp=${rest%%|*}; wtemp=${wtemp%C}; fi

# ── Git ────────────────────────────────────────────────────────────────
branch=""
if b=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null); then
  branch="$b"
elif c=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null); then
  branch="@$c"
fi
changed=0; untracked=0; in_wt=0
if [ -n "$branch" ]; then
  # Worktree detection: in a *linked* worktree --git-dir (…/.git/worktrees/x)
  # differs from --git-common-dir (…/.git); in the main worktree they match.
  gdir=$(git -C "$cwd" rev-parse --git-dir 2>/dev/null)
  gcommon=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null)
  [ -n "$gdir" ] && [ "$gdir" != "$gcommon" ] && in_wt=1
  porcelain=$(git -C "$cwd" status --porcelain 2>/dev/null)
  if [ -n "$porcelain" ]; then
    untracked=$(printf '%s\n' "$porcelain" | grep -c '^??')
    changed=$(( $(printf '%s\n' "$porcelain" | wc -l) - untracked ))
  fi
fi

# ── Worktree ports (only when cwd's git root has a self-describing .env.local) ──
wt_gw=""; wt_be=""; wt_fe=""; wt_sw=""; wt_live=""
if [ -n "$branch" ]; then
  wt_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  wt_envf="$wt_root/.env.local"
  if [ -f "$wt_envf" ]; then
    wt_gw=$(grep '^GATEWAY_PORT='  "$wt_envf" 2>/dev/null | head -1 | cut -d= -f2)
    wt_be=$(grep '^BACKEND_PORT='  "$wt_envf" 2>/dev/null | head -1 | cut -d= -f2)
    wt_fe=$(grep '^FRONTEND_PORT=' "$wt_envf" 2>/dev/null | head -1 | cut -d= -f2)
    # Sim-worker port: only for projects that actually ship a sim worker (a
    # sim-runner/ dir). Prefer an explicit SIM_WORKER_PORT; else derive it the
    # same way run.sh does (8100 + PORT_OFFSET). Projects with no sim-runner
    # never show an `sw` cell.
    if [ -d "$wt_root/sim-runner" ]; then
      wt_sw=$(grep '^SIM_WORKER_PORT=' "$wt_envf" 2>/dev/null | head -1 | cut -d= -f2)
      if [ -z "$wt_sw" ]; then
        wt_off=$(grep '^PORT_OFFSET=' "$wt_envf" 2>/dev/null | head -1 | cut -d= -f2)
        [ -n "$wt_off" ] && wt_sw=$(( 8100 + wt_off ))
      fi
    fi
    if [ -n "$wt_gw" ] && [ -n "$wt_be" ] && [ -n "$wt_fe" ]; then
      wt_live=$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null)   # ONE call for all ports
    fi
  fi
fi

# Time left until epoch $1, so no timer needs mental maths against the Mac
# clock: 43m · 2h05m under 24h, else a day and clock time (Tue 14:00), where a
# countdown would stop being useful. Minutes round down; past is 0m. Stays
# current while idle thanks to settings' refreshInterval (60s).
# Under 40 columns the minutes and clock time are dropped: 1h, Tue.
until_at() {
  left=$(( $1 - now )); [ "$left" -lt 0 ] && left=0
  if [ "$cols" -lt 40 ]; then
    if   [ "$left" -ge 86400 ]; then date -r "$1" '+%a' 2>/dev/null || date -d "@$1" '+%a' 2>/dev/null
    elif [ "$left" -ge 3600 ];  then printf '%dh' $(( left / 3600 ))
    else                             printf '%dm' $(( left / 60 )); fi
  elif [ "$left" -ge 86400 ]; then date -r "$1" '+%a %H:%M' 2>/dev/null || date -d "@$1" '+%a %H:%M' 2>/dev/null
  elif [ "$left" -ge 3600 ];  then printf '%dh%02dm' $(( left / 3600 )) $(( left % 3600 / 60 ))
  else                             printf '%dm' $(( left / 60 )); fi
}

# ── Quota windows ──────────────────────────────────────────────────────
five_pct=$(echo "$input" | jq -r '(.rate_limits.five_hour.used_percentage // empty) | round')
week_pct=$(echo "$input" | jq -r '(.rate_limits.seven_day.used_percentage // empty) | round')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
five_at=""; week_at=""
[ -n "$five_reset" ] && five_at=$(until_at "$five_reset")
[ -n "$week_reset" ] && week_at=$(until_at "$week_reset")

# ── Context ────────────────────────────────────────────────────────────
used=$(echo "$input" | jq -r '(.context_window.used_percentage // empty) | round')

# ── Effort ─────────────────────────────────────────────────────────────
# One letter and a bar that rises with the level; colour follows the heat
# scale, bold red at max. An unknown level renders plain with no bar, so a new
# level never borrows another level's look.
effort=$(echo "$input" | jq -r '.effort.level // empty')
eff_color=""; eff_short=""
case "$effort" in
  low)    eff_color="$DIM";          eff_short="l ▁" ;;
  medium) eff_color="$TEAL";         eff_short="m ▃" ;;
  high)   eff_color="$YELLOW";       eff_short="h ▅" ;;
  xhigh)  eff_color="$PEACH";        eff_short="x ▇" ;;
  max)    eff_color="${BOLD}${RED}"; eff_short="! █" ;;
  *)      eff_short="$effort" ;;
esac

# ── Prompt cache ───────────────────────────────────────────────────────
# Warm: hit ratio + time left until it goes cold (until_at). The time turns
# peach in the last 5 min of a 1h cache. Cold: tokens the next message must
# write to the cache again.
c_obs=$(echo "$input" | jq -r '.prompt_cache.caching_observed // false')
c_warm=$(echo "$input" | jq -r '.prompt_cache.warm // false')
c_ttl=$(echo "$input" | jq -r '.prompt_cache.ttl // empty')
c_exp=$(echo "$input" | jq -r '.prompt_cache.expires_at // empty')
c_hit=$(echo "$input" | jq -r '(.prompt_cache.hit_ratio // empty) * 100 | round')
c_rebuild=$(echo "$input" | jq -r '.prompt_cache.recache_tokens_if_cold // empty')
c_at=""; c_tcolor="$CLK"
if [ -n "$c_exp" ]; then
  c_at=$(until_at "$c_exp")
  c_left=$(( c_exp - now ))
  [ "$c_ttl" = "1h" ] && [ "$c_left" -gt 0 ] && [ "$c_left" -le 300 ] && c_tcolor="$PEACH"
fi

# Compact token count: 812 · 45k · 1.2M (integer maths, bash 3.2-safe).
ktok() {
  n="$1"
  if   [ "$n" -ge 1000000 ]; then d=$(( (n + 50000) / 100000 )); printf '%d.%dM' $((d / 10)) $((d % 10))
  elif [ "$n" -ge 1000 ];    then printf '%dk' $(( (n + 500) / 1000 ))
  else                            printf '%d' "$n"; fi
}

# ── Session cost ───────────────────────────────────────────────────────
# Estimate at API list prices (not a plan bill); resets on /clear. jq rounds
# to cents so the dollars.cents split stays integer maths (bash 3.2).
cents=$(echo "$input" | jq -r '(.cost.total_cost_usd // empty) * 100 | round')

# ════════════════════════════════════════════════════════════════════════
#  Cells
# ════════════════════════════════════════════════════════════════════════
# Each cell is a pair: <name>_t, the visible text (for measuring), and
# <name>_c, the same text with colour (for printing). An unset cell is empty.
cell() { # name text coloured
  eval "${1}_t=\$2; ${1}_c=\$3"
}

# Model: "Opus 5.5" → "O 5.5", "Opus 5 (1M context)" → "O 5 1M".
m_short="$model"
case "$model" in
  *" "*)
    m_rest=${model#* }; m_rest=${m_rest//(/}; m_rest=${m_rest//)/}; m_rest=${m_rest// context/}
    m_short="${model:0:1} $m_rest" ;;
esac
if [ -n "$effort" ] && [ "$cols" -lt 40 ]; then
  cell model "$m_short $eff_short" "${BOLD}${MAUVE}${m_short}${RESET} ${eff_color}${eff_short}${RESET}"
elif [ -n "$effort" ]; then
  cell model "$m_short · $eff_short" "${BOLD}${MAUVE}${m_short}${RESET}${DOT}${eff_color}${eff_short}${RESET}"
else
  cell model "$m_short" "${BOLD}${MAUVE}${m_short}${RESET}"
fi

clock=$(date '+%H:%M')
if [ -n "$wtemp" ]; then
  cell time "$clock · $wtemp" "${SKY}${clock}${RESET}${DOT}${PEACH}${wtemp}${RESET}"
else
  cell time "$clock" "${SKY}${clock}${RESET}"
fi

if [ -n "$cents" ]; then
  cost=$(printf '$%d.%02d' $((cents / 100)) $((cents % 100)))
  cell cost "$cost" "${GREEN}${cost}${RESET}"
fi
[ -n "$ver" ] && cell ver "$ver" "${DIM}${ver}${RESET}"

quota() { # name label pct at
  [ -n "$3" ] || return 0
  t="$2 $3%"; c="${DIM}$2 $(heat "$3" "$YELLOW")$3%${RESET}"
  [ -n "$4" ] && { t="$t ⟳$4"; c="$c ${CLK}⟳$4${RESET}"; }
  cell "$1" "$t" "$c"
}
quota q5 5H "$five_pct" "$five_at"
quota qw WK "$week_pct" "$week_at"

# Context: a one-character pie, filled by quarters (○ ◔ ◑ ◕ ●), and the percentage.
pie() {
  q=$(( ($1 + 12) / 25 )); [ "$q" -gt 4 ] && q=4; [ "$q" -lt 0 ] && q=0
  case "$q" in 0) printf '○' ;; 1) printf '◔' ;; 2) printf '◑' ;; 3) printf '◕' ;; *) printf '●' ;; esac
}
if [ -n "$used" ]; then
  pc=$(heat "$used" "$TEAL"); p=$(pie "$used")
  cell ctx "$p $used%" "${pc}${p} $used%${RESET}"
fi

# Prompt cache, marked with the Nerd Font database glyph (U+F1C0).
printf -v I_CACHE '\xef\x87\x80'

# Claude Code reports the cache only after this process has made a request, so
# a resumed session shows nothing until its first message. Its transcript
# still says when the cache was last written and in which bucket (5m/1h):
# read the time left from that instead. No hit ratio is known this way.
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
if [ "$c_obs" != true ] && [ -n "$transcript" ] && [ -s "$transcript" ]; then
  tail_tx=$(tail -c 262144 "$transcript" 2>/dev/null)
  at=$(printf '%s\n' "$tail_tx" | grep '"type":"assistant"' | tail -n 1 \
       | jq -r '.timestamp // "" | sub("\\.[0-9]+Z$"; "Z") | (try fromdateiso8601 catch "")' 2>/dev/null)
  # The bucket of the last turn that wrote to the cache; a turn that only read
  # it writes zero to both, so look back past those.
  case "$(printf '%s\n' "$tail_tx" | grep -oE 'ephemeral_(1h|5m)_input_tokens":[1-9]' | tail -n 1)" in
    *1h*) ttl_s=3600 ;;
    *)    ttl_s=300 ;;
  esac
  if [ -n "$at" ]; then
    c_obs=true; c_hit=""; c_rebuild=""
    c_exp=$(( at + ttl_s )); c_left=$(( c_exp - now ))
    [ "$ttl_s" = 3600 ] && c_ttl=1h || c_ttl=5m
    if [ "$c_left" -gt 0 ]; then
      c_warm=true; c_at=$(until_at "$c_exp")
      [ "$c_ttl" = 1h ] && [ "$c_left" -le 300 ] && c_tcolor="$PEACH"
    else
      c_warm=false
    fi
  fi
fi

if [ "$c_obs" = true ]; then
  if [ "$c_warm" = true ]; then
    t="$I_CACHE"; c="${LAVENDER}${I_CACHE}${RESET}"
    [ -n "$c_hit" ] && { t="$t $c_hit%"; c="$c ${LAVENDER}$c_hit%${RESET}"; }
    [ -n "$c_at" ]  && { t="$t ⟳$c_at"; c="$c ${c_tcolor}⟳$c_at${RESET}"; }
    cell cache "$t" "$c"
  elif [ -n "$c_rebuild" ]; then
    k=$(ktok "$c_rebuild"); cell cache "$I_CACHE cold $k" "${PEACH}${I_CACHE} cold ${DIM}$k${RESET}"
  else
    cell cache "$I_CACHE cold" "${PEACH}${I_CACHE} cold${RESET}"
  fi
fi

# Worktree ports: live ones green with ● and clickable (OSC 8), down ones dim ○.
port() { # name label port
  [ -n "$3" ] || return 0
  case "$wt_live" in
    *":$3 (LISTEN)"*)
      cell "$1" "$2 $3●" "${GREEN}$2 "$'\033]8;;'"http://localhost:$3"$'\033\\'"$3"$'\033]8;;\033\\'"●${RESET}" ;;
    *) cell "$1" "$2 $3○" "${DIM}$2 $3○${RESET}" ;;
  esac
}
if [ -n "$wt_gw" ] && [ -n "$wt_be" ] && [ -n "$wt_fe" ]; then
  port gw gw "$wt_gw"; port be be "$wt_be"; port fe fe "$wt_fe"; port sw sw "$wt_sw"
fi

# Place: folder basename (home → ~). Three or more words shrink to initials and
# the last word (theater-gen-skills → t-g-skills); a linked worktree adds ⑂.
if [ "$cwd" = "$HOME" ]; then dir="~"; else dir="${cwd##*/}"; fi
case "$dir" in
  *-*-*)
    short=""; rest="$dir"
    while case "$rest" in *-*) true ;; *) false ;; esac; do
      short="$short${rest:0:1}-"; rest=${rest#*-}
    done
    dir="$short$rest" ;;
esac
[ "${#dir}" -gt 16 ] && dir="${dir:0:15}…"
if [ "$in_wt" = 1 ]; then
  cell place "$dir ⑂" "${BOLD}${BLUE}${dir}${RESET} ${BOLD}${PINK}⑂${RESET}"
else
  cell place "$dir" "${BOLD}${BLUE}${dir}${RESET}"
fi

# ════════════════════════════════════════════════════════════════════════
#  Render
# ════════════════════════════════════════════════════════════════════════
if [ "$cols" -ge 60 ]; then
  rows="model time cost ver
q5 qw ctx cache
gw be fe sw"
else
  rows="model ctx cache
q5 qw cost
gw be fe"
fi

# Column widths: the widest cell in each column over every row; the place
# cell counts toward the first column so its divider lines up too.
w0=${#place_t}; w1=0; w2=0; w3=0
while read -r row; do
  i=0
  for name in $row; do
    eval "t=\${${name}_t}"
    eval "[ \${#t} -gt \$w$i ] && w$i=\${#t}"
    i=$(( i + 1 ))
  done
done <<EOF
$rows
EOF

# Keep only the columns that fit the pane (a little margin for the panel's
# own edge): drop from the right until they do.
ncol=4
while [ "$ncol" -gt 1 ]; do
  total=$(( 3 * (ncol - 1) )); i=0
  while [ "$i" -lt "$ncol" ]; do eval "total=\$(( total + w$i ))"; i=$(( i + 1 )); done
  [ "$total" -le $(( cols - 2 )) ] && break
  ncol=$(( ncol - 1 ))
done

# Line 1: place │ branch. The branch may use the rest of the pane; a long one
# is cut in the middle. Its type (fix/, feat/) is dimmed.
printf '%s' "$place_c"
if [ -n "$branch" ]; then
  tail=""; tail_c=""
  [ "$changed" -gt 0 ]   && { tail="$tail !$changed";   tail_c="$tail_c ${PEACH}!$changed${RESET}"; }
  [ "$untracked" -gt 0 ] && { tail="$tail ?$untracked"; tail_c="$tail_c ${PEACH}?$untracked${RESET}"; }
  pre=""; name="$branch"
  case "$branch" in */*) pre="${branch%%/*}/"; name="${branch#*/}" ;; esac
  room=$(( cols - w0 - 3 - ${#pre} - ${#tail} - 1 )); [ "$room" -lt 6 ] && room=6
  printf '%*s%s%s%s%s%s%s%s' $(( w0 - ${#place_t} )) '' "$BAR" "$DIM" "$pre" "$GREEN" "$(mid "$name" "$room")" "$RESET" "$tail_c"
fi
printf '\n'

# Grid rows: skip a row with nothing in it; drop empty cells at the end of a
# row, but keep an empty cell in the middle so the next one stays in its column.
while read -r row; do
  last=-1; i=0
  for name in $row; do
    [ "$i" -lt "$ncol" ] || break
    eval "t=\${${name}_t}"; [ -n "$t" ] && last=$i
    i=$(( i + 1 ))
  done
  [ "$last" -ge 0 ] || continue
  i=0
  for name in $row; do
    [ "$i" -le "$last" ] || break
    [ "$i" -gt 0 ] && printf '%s' "$BAR"
    eval "t=\${${name}_t}; c=\${${name}_c}"
    # Claude Code trims leading spaces, which would pull an empty first cell
    # (a fresh session has no 5H yet) and everything after it to the left. A
    # braille blank survives the trim and keeps the column.
    if [ "$i" = 0 ] && [ -z "$t" ]; then t="⠀"; c="⠀"; fi
    printf '%s' "$c"
    if [ "$i" -lt "$last" ]; then eval "w=\$w$i"; printf '%*s' $(( w - ${#t} )) ''; fi
    i=$(( i + 1 ))
  done
  printf '\n'
done <<EOF
$rows
EOF

# Trailing spacer (U+2800 braille blank survives Claude Code's whitespace trim).
printf "%s⠀" "$RESET"
