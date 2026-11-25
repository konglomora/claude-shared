#!/bin/bash
# Claude Code subagent status line — one agent-panel row per subagent, in the
# same Catppuccin palette and heat rules as statusline-command.sh, laid out as
# a table whose │ dividers line up from row to row.
#
# stdin:  {columns, tasks:[{id, name?, agentType, status, label, startTime(ms),
#          model?, effort?, tokenCount, contextWindowSize?}, …]}
# stdout: one {"id","content"} JSON line per task.
#
#   wide:    <name>       │ O 5.5 │ h ▅ │ ◑ 34% │  40% ⟳3m │ <label>
#   narrow:  <name>     │ O │ ▅ │ 34% │ 40% │ <label>        (columns < 60)
#
# A tight panel drops the cache column, then model, so the label keeps room; effort stays.
#
# Running rows get no icon: Claude Code draws its own status mark before the
# row. ✓ completed · ✗ failed/killed. Finished rows go gray. The cache column,
# marked with the Nerd Font database glyph (U+F1C0) like the main line, is how
# much of the agent's prompt-cache lifetime has passed, with the time left;
# "cold" once it has run out. The label is cut with … so the row never wraps the panel.
now_ms=$(( $(date +%s) * 1000 ))
input=$(cat)

# Cache countdown. Claude Code sends no cache data for subagents, but each one
# keeps a transcript at ~/.claude/projects/<slug>/<session>/subagents/
# agent-<task id>.jsonl. Its last assistant turn is when the cache was last
# written, and the bucket that turn wrote (ephemeral_5m / ephemeral_1h) is the
# TTL. Collected here as "id<TAB>timestamp<TAB>ttl<TAB>effort" lines for jq
# below.
caches=""
for id in $(printf '%s' "$input" | jq -r '.tasks[].id'); do
  case "$id" in ''|*[!A-Za-z0-9_-]*) continue ;; esac   # ids go into a glob
  log=""
  for f in "$HOME"/.claude/projects/*/*/subagents/agent-"$id".jsonl; do
    [ -f "$f" ] && { log="$f"; break; }
  done
  [ -n "$log" ] || continue
  tail=$(tail -c 262144 "$log" 2>/dev/null)
  ts=$(printf '%s\n' "$tail" | grep '"type":"assistant"' | tail -n 1 \
       | sed -n 's/.*"timestamp":"\([^"]*\)".*/\1/p')
  # Claude Code leaves effort out of the task when the agent inherits the
  # session's level, but every transcript entry records the level it ran at.
  eff=$(printf '%s\n' "$tail" | grep -oE '"effort":"[a-z]+"' | tail -n 1 | cut -d'"' -f4)
  [ -n "$ts" ] || [ -n "$eff" ] || continue
  case "$(printf '%s\n' "$tail" | grep -oE 'ephemeral_(1h|5m)_input_tokens":[1-9]' | tail -n 1)" in
    *1h*) ttl=3600 ;;
    *)    ttl=300 ;;    # the subagent default
  esac
  caches="$caches$id	$ts	$ttl	$eff
"
done

printf '%s' "$input" | jq -c --argjson now "$now_ms" --arg caches "$caches" '
  def esc(c): "\u001b[" + c + "m";
  def MAUVE:  "38;5;183"; def TEAL: "38;5;116"; def YELLOW: "38;5;223";
  def PEACH:  "38;5;216"; def RED:  "38;5;211"; def LAV:    "38;5;147";
  def DIM:    "38;5;103"; def FAINT: "38;5;60"; def CLK: "38;5;102";

  def heat(p; base): if p >= 90 then RED elif p >= 70 then PEACH else base end;
  def lpad(n): tostring | (" " * ([n - length, 0] | max)) + .;
  def cut(n): if length > n then .[0:n - 1] + "…" else . end;
  def pie(p): ((((p + 12) / 25) | floor) | if . > 4 then 4 else . end) as $q | "○◔◑◕●"[$q:$q + 1];
  # general-purpose → g-purpose, diff-critic → d-critic: every word but the
  # last shrinks to its initial, as the main line does for folder names.
  def shortname: split("-") | if length > 1 then (.[:-1] | map(.[0:1])) + [.[-1]] | join("-") else join("-") end;
  def ktok: if . >= 1000000 then "\((. / 100000 | round) / 10)M"
            elif . >= 1000 then "\(. / 1000 | round)k" else tostring end;
  # claude-opus-5-5[1m] → "O 5.5"; claude-haiku-5-5-20260301 → "H 5.5"
  def short_model: (capture("^claude-(?<f>[a-z]+)-(?<v>[0-9]+(-[0-9]{1,2})?)(-[0-9]{8})?(\\[.*\\])?$")?
                    | "\(.f[0:1] | ascii_upcase) \(.v | gsub("-"; "."))") // .;
  def effort_seg:
    { low: ["l", "▁", DIM], medium: ["m", "▃", TEAL], high: ["h", "▅", YELLOW],
      xhigh: ["x", "▇", PEACH], max: ["!", "█", "1;" + RED] }[tostring];

  ($caches | split("\n") | map(select(length > 0) | split("\t")
     | {key: .[0], value: {ts: .[1], ttl: (.[2] | tonumber), effort: (.[3] // "")}}) | from_entries) as $cache
  | (.columns // 200) as $cols
  | ($cols < 60) as $narrow
  | (if $cols < 40 then 8 elif $narrow then 10 else 12 end) as $namew

  # Cells per task as [text, colour], in column order; the label is last.
  | [ .tasks[]
      | . as $t
      | ($t.status == "running") as $live
      | (if $live then null else DIM end) as $mute
      | (if $t.status == "completed" then "✓ " elif $live then "" else "✗ " end) as $icon
      | (if $t.status == "running" or $t.status == "completed" then null else RED end) as $bad
      | ($t.model // "" | short_model | if $narrow then .[0:1] else . end) as $model
      | ($t.effort // $cache[$t.id].effort // "" | if . == "" then null else . end) as $effort
      | ($effort // "" | effort_seg) as $e
      | (if $t.contextWindowSize then (($t.tokenCount * 100 / $t.contextWindowSize) | round) else null end) as $p
      | ($cache[$t.id]) as $c
      | (if $c == null then null else
           (try ($c.ts | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch null) as $at
           | if $at == null then null else
               ($at + $c.ttl - ($now / 1000 | floor)) as $left
               | {left: $left, used: ((($c.ttl - $left) * 100 / $c.ttl) | round | if . > 100 then 100 elif . < 0 then 0 else . end)}
             end
         end) as $ttl
      | { id: $t.id,
          cells: [
            [($icon + ($t.name // $t.agentType | shortname)) | cut($namew), $bad // (if $live then "1;" + MAUVE else DIM end)],
            [$model, $mute // MAUVE],
            (if $e == null then [$effort // "", $mute // DIM]
             elif $narrow then [$e[1], $mute // $e[2]]
             else [$e[0] + " " + $e[1], $mute // $e[2]] end),
            (if $p != null then [[(if $narrow then "" else pie($p) + " " end), "\($p)%"], $mute // heat($p; TEAL)]
             else [[(if $narrow then "" else "  " end), ($t.tokenCount | ktok)], $mute // TEAL] end),
            (if $ttl == null then ["", null]
             elif $ttl.left <= 0 then [[(if $narrow then "" else "\uf1c0 " end), {rest: "cold"}], DIM]
             else [[(if $narrow then "" else "\uf1c0 " end), "\($ttl.used)%",
                    (if $narrow then "" else " ⟳\($ttl.left / 60 | floor)m" end)],
                   if $ttl.left < 60 then PEACH else $mute // LAV end] end),
            [(if $live or $t.status == "completed" then $t.label else $t.status end) // "", $bad // DIM]
          ] } ]

  # Number cells come as [icon, value, tail] parts. Each part is right-aligned
  # to the widest one in its column, so digits line up with the least padding
  # the rows need: " 9%" next to "15%", never a fixed 4-wide "  9%". A {rest}
  # part (the "cold" word) starts right after the icon, left-aligned, and is
  # left out of the widths so it never pushes the numbers of other rows.
  | . as $raw
  | ([range(0; 5)] | map(. as $i
      | [$raw[].cells[$i][0] | arrays] as $parts
      | [range(0; [$parts[] | length] | max // 0) | . as $k | [$parts[] | .[$k] | strings | length] | max // 0])) as $pw
  | map(.cells |= [to_entries[] | .key as $i | .value
      | if (.[0] | type) == "array"
        then [(.[0] as $p | ($p | map(type == "object") | index(true)) as $o
              | [range(0; $o // ($pw[$i] | length)) as $k | $p[$k] // "" | lpad($pw[$i][$k])]
              + (if $o then [$p[$o].rest] else [] end) | join("")), .[1]]
        else . end])
  | . as $rows

  # Column widths: the name column is fixed; every other column is as wide as
  # its widest cell over all rows, so the dividers line up.
  | ([range(0; 5)] | map(. as $i | [$rows[].cells[$i][0] | length] | max // 0)) as $w0
  | ($w0 | .[0] = ([.[0], $namew] | min)) as $w
  # A tight panel drops columns until the label keeps ~10 characters: the
  # cache column first, then model. Effort always stays.
  | (reduce (4, 1) as $d ([range(0; 5)] | map(select($w[.] > 0));
      if ((map($w[.] + 3) | add) + 10) > $cols then map(select(. != $d)) else . end)) as $shown
  | (($shown | map($w[.] + 3) | add) // 0) as $used
  | ([($cols - $used - 1), 8] | max) as $room

  | $rows[]
  | . as $r
  | ([$shown[] | . as $i | $r.cells[$i] | .[0] as $txt
        | (if .[1] then esc(.[1]) + $txt + esc("0") else $txt end)
          + (" " * ($w[$i] - ($txt | length)))]
     + [$r.cells[5] | (.[0] | cut($room)) as $txt | esc(.[1]) + $txt + esc("0")])
  | join(esc(FAINT) + " │ " + esc("0"))
  | {id: $r.id, content: .}
'
