#!/usr/bin/env bash
# Codex Insights - Analyze Codex CLI session history and generate HTML report
# Usage: bash ~/.skills/codex-insights/analyze.sh
# Output: ~/.codex/usage-data/report.html (mirrors Claude Code's path)
# Compatible with macOS bash 3.x (no associative arrays)
set -euo pipefail
if locale -a 2>/dev/null | grep -q 'C.UTF-8'; then
  export LC_ALL=C.UTF-8
elif locale -a 2>/dev/null | grep -q 'en_US.UTF-8'; then
  export LC_ALL=en_US.UTF-8
fi

# HTML escape helper to prevent XSS
html_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  echo "$s"
}

CODEX_DIR="${HOME}/.codex"
HISTORY="${CODEX_DIR}/history.jsonl"
SESSIONS_DIR="${CODEX_DIR}/sessions"
OUTPUT_DIR="${CODEX_DIR}/usage-data"
OUTPUT_HTML="${OUTPUT_DIR}/report.html"
INSIGHTS_JSON="${OUTPUT_DIR}/insights.json"
mkdir -p "$OUTPUT_DIR"
TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install it: brew install jq" >&2
  exit 1
fi

if [[ ! -f "$HISTORY" ]]; then
  echo "Error: ${HISTORY} not found" >&2
  echo "Codex CLI のセッションデータが見つかりません。Codex を使ってからもう一度実行してください。" >&2
  exit 1
fi

# ═══════════════════════════════════════
# Data Collection
# ═══════════════════════════════════════

total_messages=$(wc -l < "$HISTORY" | tr -d ' ')
unique_sessions=$(jq -r '.session_id' "$HISTORY" | sort -u | wc -l | tr -d ' ')

first_ts=$(jq -r '.ts | floor' "$HISTORY" | head -1)
last_ts=$(jq -r '.ts | floor' "$HISTORY" | tail -1)
first_date=$(date -r "$first_ts" '+%Y-%m-%d' 2>/dev/null || date -d "@$first_ts" '+%Y-%m-%d' 2>/dev/null || echo "unknown")
last_date=$(date -r "$last_ts" '+%Y-%m-%d' 2>/dev/null || date -d "@$last_ts" '+%Y-%m-%d' 2>/dev/null || echo "unknown")

days_active=$(( (last_ts - first_ts) / 86400 + 1 ))
[[ $days_active -lt 1 ]] && days_active=1
msgs_per_day=$(awk "BEGIN {printf \"%.1f\", $total_messages / $days_active}")
avg_msgs=$(jq -r '.session_id' "$HISTORY" | sort | uniq -c | awk '{sum+=$1; n++} END {printf "%.1f", sum/n}')

# Session file analysis
projects_tmp="${TMPDIR_WORK}/projects.txt"
tools_tmp="${TMPDIR_WORK}/tools.txt"
: > "$projects_tmp"
: > "$tools_tmp"

find "$SESSIONS_DIR" -name '*.jsonl' -print0 2>/dev/null | while IFS= read -r -d '' sf; do
  jq -r 'select(.type == "session_meta") | .payload.cwd // empty' "$sf" 2>/dev/null | head -1 | while read -r cwd; do
    [[ -n "$cwd" ]] && basename "$cwd" >> "$projects_tmp"
  done
  jq -r 'select(.type == "response_item") | .payload | select(.type == "function_call") | .name // empty' "$sf" 2>/dev/null >> "$tools_tmp"
done

project_sorted=$(sort "$projects_tmp" | uniq -c | sort -rn | head -10)
tool_sorted=$(sort "$tools_tmp" | uniq -c | sort -rn | head -8)
total_tool_calls=$(wc -l < "$tools_tmp" | tr -d ' ')

max_project_count=$(echo "$project_sorted" | head -1 | awk '{print $1}')
max_tool_count=$(echo "$tool_sorted" | head -1 | awk '{print $1}')
: "${max_project_count:=1}"
: "${max_tool_count:=1}"

keywords=$(jq -r '.text' "$HISTORY" | \
  grep -oiE '(Chrome拡張|CLI|GAS|Slack|API|PR|commit|push|test|deploy|CI|CD|Homebrew|chezmoi|dotfiles|Playwright|review|bug|fix|リリース|公開|記事|ブログ|画像|MCP|Serena)' 2>/dev/null | \
  tr '[:upper:]' '[:lower:]' | sort | uniq -c | sort -rn | head -10) || true

top_sessions=$(jq -r '{id: .session_id, text: .text}' "$HISTORY" | \
  jq -rs 'group_by(.id) | map({id: .[0].id, count: length, first_msg: .[0].text}) | sort_by(-.count) | .[0:5]')

# Check for AI-generated insights
has_insights=false
if [[ -f "$INSIGHTS_JSON" ]]; then
  has_insights=true
fi

generated_at=$(date '+%Y-%m-%d %H:%M')

# ═══════════════════════════════════════
# HTML Generation
# ═══════════════════════════════════════

cat > "$OUTPUT_HTML" <<'CSS'
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Codex Insights</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f8fafc; color: #334155; line-height: 1.65; padding: 48px 24px; }
    .container { max-width: 800px; margin: 0 auto; }
    h1 { font-size: 32px; font-weight: 700; color: #0f172a; margin-bottom: 8px; }
    h2 { font-size: 20px; font-weight: 600; color: #0f172a; margin-top: 48px; margin-bottom: 16px; }
    .subtitle { color: #64748b; font-size: 15px; margin-bottom: 32px; }
    .nav-toc { display: flex; flex-wrap: wrap; gap: 8px; margin: 24px 0 32px 0; padding: 16px; background: white; border-radius: 8px; border: 1px solid #e2e8f0; }
    .nav-toc a { font-size: 12px; color: #64748b; text-decoration: none; padding: 6px 12px; border-radius: 6px; background: #f1f5f9; transition: all 0.15s; }
    .nav-toc a:hover { background: #e2e8f0; color: #334155; }
    .stats-row { display: flex; gap: 24px; margin-bottom: 40px; padding: 20px 0; border-top: 1px solid #e2e8f0; border-bottom: 1px solid #e2e8f0; flex-wrap: wrap; justify-content: center; }
    .stat { text-align: center; min-width: 80px; }
    .stat-value { font-size: 24px; font-weight: 700; color: #0f172a; }
    .stat-label { font-size: 11px; color: #64748b; text-transform: uppercase; }
    .at-a-glance { background: linear-gradient(135deg, #dbeafe 0%, #bfdbfe 100%); border: 1px solid #3b82f6; border-radius: 12px; padding: 20px 24px; margin-bottom: 32px; }
    .glance-title { font-size: 16px; font-weight: 700; color: #1e3a5f; margin-bottom: 16px; }
    .glance-sections { display: flex; flex-direction: column; gap: 12px; }
    .glance-section { font-size: 14px; color: #1e3a5f; line-height: 1.6; }
    .glance-section strong { color: #1e40af; }
    .see-more { color: #2563eb; text-decoration: none; font-size: 13px; white-space: nowrap; }
    .see-more:hover { text-decoration: underline; }
    .charts-row { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; margin: 24px 0; }
    .chart-card { background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px; }
    .chart-title { font-size: 12px; font-weight: 600; color: #64748b; text-transform: uppercase; margin-bottom: 12px; }
    .bar-row { display: flex; align-items: center; margin-bottom: 6px; }
    .bar-label { width: 130px; font-size: 11px; color: #475569; flex-shrink: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .bar-track { flex: 1; height: 6px; background: #f1f5f9; border-radius: 3px; margin: 0 8px; }
    .bar-fill { height: 100%; border-radius: 3px; }
    .bar-value { width: 40px; font-size: 11px; font-weight: 500; color: #64748b; text-align: right; }
    .session-card { background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 12px 16px; margin-bottom: 8px; }
    .area-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px; }
    .area-name { font-weight: 600; font-size: 13px; color: #0f172a; font-family: monospace; }
    .area-count { font-size: 12px; color: #64748b; background: #f1f5f9; padding: 2px 8px; border-radius: 4px; }
    .session-msg { font-size: 13px; color: #475569; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 600px; }
    .keyword-grid { display: flex; flex-wrap: wrap; gap: 8px; margin: 16px 0; }
    .keyword-chip { background: white; border: 1px solid #e2e8f0; border-radius: 6px; padding: 6px 12px; font-size: 13px; }
    .keyword-count { font-weight: 600; color: #2563eb; margin-right: 4px; }
    .big-win { background: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 8px; padding: 16px; margin-bottom: 12px; }
    .big-win-title { font-weight: 600; font-size: 15px; color: #166534; margin-bottom: 8px; }
    .big-win-desc { font-size: 14px; color: #15803d; line-height: 1.5; }
    .friction-card { background: #fef2f2; border: 1px solid #fca5a5; border-radius: 8px; padding: 16px; margin-bottom: 12px; }
    .friction-title { font-weight: 600; font-size: 15px; color: #991b1b; margin-bottom: 6px; }
    .friction-desc { font-size: 13px; color: #7f1d1d; line-height: 1.5; }
    .friction-example { font-size: 12px; color: #334155; margin-top: 8px; padding: 8px 12px; background: rgba(255,255,255,0.6); border-radius: 4px; font-family: monospace; }
    .suggestion-card { background: #eff6ff; border: 1px solid #bfdbfe; border-radius: 8px; padding: 16px; margin-bottom: 12px; }
    .suggestion-title { font-weight: 600; font-size: 15px; color: #1e40af; margin-bottom: 6px; }
    .suggestion-desc { font-size: 14px; color: #1e3a5f; line-height: 1.5; }
    .copy-btn { background: #e2e8f0; border: none; border-radius: 4px; padding: 4px 10px; font-size: 11px; cursor: pointer; color: #475569; float: right; transition: all 0.2s; }
    .copy-btn:hover { background: #cbd5e1; }
    .copy-btn.copied { background: #16a34a; color: white; }
    .copyable-prompt { background: #f8fafc; padding: 12px; border-radius: 6px; margin-top: 10px; border: 1px solid #e2e8f0; position: relative; }
    .copyable-prompt code { font-family: monospace; font-size: 12px; color: #334155; display: block; white-space: pre-wrap; line-height: 1.6; }
    .prompt-label { font-size: 11px; font-weight: 600; text-transform: uppercase; color: #64748b; margin-bottom: 6px; }
    .instructions-section { background: #eff6ff; border: 1px solid #bfdbfe; border-radius: 8px; padding: 16px; margin-bottom: 20px; }
    .instructions-section h3 { font-size: 14px; font-weight: 600; color: #1e40af; margin: 0 0 8px 0; }
    .instructions-item { display: flex; flex-wrap: wrap; align-items: flex-start; gap: 8px; padding: 10px 0; border-bottom: 1px solid #dbeafe; }
    .instructions-item:last-child { border-bottom: none; }
    .instructions-code { background: white; padding: 8px 12px; border-radius: 4px; font-size: 12px; color: #1e40af; border: 1px solid #bfdbfe; font-family: monospace; display: block; white-space: pre-wrap; word-break: break-word; flex: 1; }
    .instructions-why { font-size: 12px; color: #64748b; width: 100%; padding-left: 4px; margin-top: 4px; }
    .compare-row { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin: 16px 0; }
    .compare-card { background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px; }
    .compare-card h3 { font-size: 14px; font-weight: 600; margin-bottom: 8px; }
    .compare-card ul { font-size: 13px; color: #475569; padding-left: 16px; line-height: 1.7; }
    .note { background: #f0f9ff; border: 1px solid #bae6fd; border-radius: 8px; padding: 16px; margin: 24px 0; font-size: 14px; color: #0c4a6e; line-height: 1.6; }
    @media (max-width: 640px) { .charts-row { grid-template-columns: 1fr; } .compare-row { grid-template-columns: 1fr; } }
  </style>
</head>
<body>
<div class="container">
CSS

# --- Header + At a Glance ---
cat >> "$OUTPUT_HTML" <<HEADER
  <h1>Codex Insights</h1>
  <p class="subtitle">${total_messages} messages across ${unique_sessions} sessions | ${first_date} to ${last_date}</p>
HEADER

# At a Glance (read from insights.json if exists, otherwise use data-driven defaults)
if [[ "$has_insights" == true ]] && jq -e '.at_a_glance' "$INSIGHTS_JSON" >/dev/null 2>&1; then
  working=$(html_escape "$(jq -r '.at_a_glance.working' "$INSIGHTS_JSON")")
  hindering=$(html_escape "$(jq -r '.at_a_glance.hindering' "$INSIGHTS_JSON")")
  quick_wins=$(html_escape "$(jq -r '.at_a_glance.quick_wins' "$INSIGHTS_JSON")")
else
  working="shell_command ${total_tool_calls}回の実行が示す通り、git操作・CI/CD・複数リポジトリ管理の自動化が安定稼働中。"
  hindering="セッションデータから詳細な摩擦分析を行うには、codex-insights --force を実行してください。"
  quick_wins="まず codex-insights --force で AI 分析を実行して、具体的な改善提案を取得しましょう。"
fi

cat >> "$OUTPUT_HTML" <<GLANCE
  <div class="at-a-glance">
    <div class="glance-title">At a Glance</div>
    <div class="glance-sections">
      <div class="glance-section"><strong>What's working:</strong> ${working} <a href="#section-wins" class="see-more">Impressive Things →</a></div>
      <div class="glance-section"><strong>What's hindering:</strong> ${hindering} <a href="#section-friction" class="see-more">Friction Points →</a></div>
      <div class="glance-section"><strong>Quick wins:</strong> ${quick_wins} <a href="#section-suggestions" class="see-more">Suggestions →</a></div>
    </div>
  </div>
GLANCE

# --- Nav ---
cat >> "$OUTPUT_HTML" <<'NAV'
  <nav class="nav-toc">
    <a href="#section-stats">Stats</a>
    <a href="#section-projects">Projects</a>
    <a href="#section-tools">Tools</a>
    <a href="#section-keywords">Keywords</a>
    <a href="#section-wins">Impressive Things</a>
    <a href="#section-friction">Friction Points</a>
    <a href="#section-suggestions">Suggestions</a>
    <a href="#section-compare">Codex vs Claude Code</a>
  </nav>
NAV

# --- Stats ---
cat >> "$OUTPUT_HTML" <<STATS
  <div class="stats-row" id="section-stats">
    <div class="stat"><div class="stat-value">${total_messages}</div><div class="stat-label">Messages</div></div>
    <div class="stat"><div class="stat-value">${unique_sessions}</div><div class="stat-label">Sessions</div></div>
    <div class="stat"><div class="stat-value">${total_tool_calls}</div><div class="stat-label">Tool Calls</div></div>
    <div class="stat"><div class="stat-value">${days_active}</div><div class="stat-label">Days</div></div>
    <div class="stat"><div class="stat-value">${msgs_per_day}</div><div class="stat-label">Msgs/Day</div></div>
    <div class="stat"><div class="stat-value">${avg_msgs}</div><div class="stat-label">Msgs/Session</div></div>
  </div>
  <div class="charts-row">
    <div class="chart-card">
      <div class="chart-title" id="section-projects">Projects</div>
STATS

echo "$project_sorted" | while read -r count name; do
  [[ -z "$count" ]] && continue
  pct=$(awk "BEGIN {printf \"%.1f\", $count * 100 / $max_project_count}")
  escaped_name=$(html_escape "$name")
  printf '      <div class="bar-row"><div class="bar-label">%s</div><div class="bar-track"><div class="bar-fill" style="width:%s%%;background:#2563eb"></div></div><div class="bar-value">%s</div></div>\n' "$escaped_name" "$pct" "$count" >> "$OUTPUT_HTML"
done

cat >> "$OUTPUT_HTML" <<'MID'
    </div>
    <div class="chart-card">
      <div class="chart-title" id="section-tools">Tool Usage</div>
MID

echo "$tool_sorted" | while read -r count name; do
  [[ -z "$count" ]] && continue
  pct=$(awk "BEGIN {printf \"%.1f\", $count * 100 / $max_tool_count}")
  escaped_name=$(html_escape "$name")
  printf '      <div class="bar-row"><div class="bar-label">%s</div><div class="bar-track"><div class="bar-fill" style="width:%s%%;background:#0891b2"></div></div><div class="bar-value">%s</div></div>\n' "$escaped_name" "$pct" "$count" >> "$OUTPUT_HTML"
done

printf '    </div>\n  </div>\n' >> "$OUTPUT_HTML"

# --- Keywords ---
printf '\n  <h2 id="section-keywords">Top Keywords</h2>\n  <div class="keyword-grid">\n' >> "$OUTPUT_HTML"
echo "$keywords" | while read -r count word; do
  [[ -z "$count" ]] && continue
  escaped_word=$(html_escape "$word")
  printf '    <div class="keyword-chip"><span class="keyword-count">%s</span>%s</div>\n' "$count" "$escaped_word" >> "$OUTPUT_HTML"
done
printf '  </div>\n' >> "$OUTPUT_HTML"

# ═══════════════════════════════════════
# AI Analysis Sections (from insights.json)
# ═══════════════════════════════════════

if [[ "$has_insights" == true ]]; then
  # --- Wins ---
  printf '\n  <h2 id="section-wins">Impressive Things</h2>\n' >> "$OUTPUT_HTML"
  while read -r win; do
    title=$(html_escape "$(echo "$win" | jq -r '.title')")
    desc=$(html_escape "$(echo "$win" | jq -r '.desc')")
    printf '  <div class="big-win"><div class="big-win-title">%s</div><div class="big-win-desc">%s</div></div>\n' "$title" "$desc" >> "$OUTPUT_HTML"
  done < <(jq -c '.wins[]' "$INSIGHTS_JSON" 2>/dev/null)

  # --- Friction ---
  printf '\n  <h2 id="section-friction">Friction Points</h2>\n' >> "$OUTPUT_HTML"
  while read -r fr; do
    title=$(html_escape "$(echo "$fr" | jq -r '.title')")
    desc=$(html_escape "$(echo "$fr" | jq -r '.desc')")
    example=$(html_escape "$(echo "$fr" | jq -r '.example // empty')")
    printf '  <div class="friction-card"><div class="friction-title">%s</div><div class="friction-desc">%s</div>' "$title" "$desc" >> "$OUTPUT_HTML"
    [[ -n "$example" ]] && printf '<div class="friction-example">%s</div>' "$example" >> "$OUTPUT_HTML"
    printf '</div>\n' >> "$OUTPUT_HTML"
  done < <(jq -c '.friction[]' "$INSIGHTS_JSON" 2>/dev/null)

  # --- Suggestions with instructions.md additions ---
  printf '\n  <h2 id="section-suggestions">Suggestions</h2>\n' >> "$OUTPUT_HTML"

  # instructions.md additions
  inst_count=$(jq '.instructions_additions | length' "$INSIGHTS_JSON" 2>/dev/null || echo 0)
  if [[ "$inst_count" -gt 0 ]]; then
    printf '  <div class="instructions-section"><h3>instructions.md に追加（コピーして貼り付け）</h3>\n' >> "$OUTPUT_HTML"
    local_idx=0
    while read -r item; do
      text=$(html_escape "$(echo "$item" | jq -r '.text')")
      why=$(html_escape "$(echo "$item" | jq -r '.why // empty')")
      printf '    <div class="instructions-item"><div class="instructions-code" id="inst-%s">%s</div><button class="copy-btn" onclick="copyText('"'"'inst-%s'"'"', this)">Copy</button>' "$local_idx" "$text" "$local_idx" >> "$OUTPUT_HTML"
      [[ -n "$why" ]] && printf '<div class="instructions-why">%s</div>' "$why" >> "$OUTPUT_HTML"
      printf '</div>\n' >> "$OUTPUT_HTML"
      local_idx=$((local_idx + 1))
    done < <(jq -c '.instructions_additions[]' "$INSIGHTS_JSON" 2>/dev/null)
    printf '  </div>\n' >> "$OUTPUT_HTML"
  fi

  # Suggestion cards with copyable prompts
  local_idx=0
  while read -r sug; do
    title=$(html_escape "$(echo "$sug" | jq -r '.title')")
    desc=$(html_escape "$(echo "$sug" | jq -r '.desc')")
    prompt=$(html_escape "$(echo "$sug" | jq -r '.prompt // empty')")
    printf '  <div class="suggestion-card"><div class="suggestion-title">%s</div><div class="suggestion-desc">%s</div>' "$title" "$desc" >> "$OUTPUT_HTML"
    if [[ -n "$prompt" ]]; then
      printf '<div class="copyable-prompt"><div class="prompt-label">Codex に貼り付けるプロンプト</div><code id="prompt-%s">%s</code><button class="copy-btn" onclick="copyText('"'"'prompt-%s'"'"', this)">Copy</button></div>' "$local_idx" "$prompt" "$local_idx" >> "$OUTPUT_HTML"
    fi
    printf '</div>\n' >> "$OUTPUT_HTML"
    local_idx=$((local_idx + 1))
  done < <(jq -c '.suggestions[]' "$INSIGHTS_JSON" 2>/dev/null)

  # --- Comparison ---
  if jq -e '.comparison' "$INSIGHTS_JSON" >/dev/null 2>&1; then
    printf '\n  <h2 id="section-compare">Codex vs Claude Code</h2>\n' >> "$OUTPUT_HTML"
    printf '  <div class="compare-row">\n    <div class="compare-card"><h3 style="color:#2563eb;">Codex</h3><ul>\n' >> "$OUTPUT_HTML"
    while read -r item; do
      escaped_item=$(html_escape "$item")
      printf '      <li>%s</li>\n' "$escaped_item" >> "$OUTPUT_HTML"
    done < <(jq -r '.comparison.codex[]' "$INSIGHTS_JSON" 2>/dev/null)
    printf '    </ul></div>\n    <div class="compare-card"><h3 style="color:#d946ef;">Claude Code</h3><ul>\n' >> "$OUTPUT_HTML"
    while read -r item; do
      escaped_item=$(html_escape "$item")
      printf '      <li>%s</li>\n' "$escaped_item" >> "$OUTPUT_HTML"
    done < <(jq -r '.comparison.claude[]' "$INSIGHTS_JSON" 2>/dev/null)
    printf '    </ul></div>\n  </div>\n' >> "$OUTPUT_HTML"
  fi

else
  # No insights.json - show placeholder sections
  cat >> "$OUTPUT_HTML" <<'PLACEHOLDER'

  <h2 id="section-wins">Impressive Things</h2>
  <div class="note">AI分析を実行すると、セッションデータから成功パターンを抽出します。<br><code>codex-insights --force</code> を実行してください。</div>

  <h2 id="section-friction">Friction Points</h2>
  <div class="note">AI分析を実行すると、摩擦点と改善提案を生成します。<br><code>codex-insights --force</code> を実行してください。</div>

  <h2 id="section-suggestions">Suggestions</h2>
  <div class="note">AI分析を実行すると、コピー可能な改善プロンプトを生成します。<br><code>codex-insights --force</code> を実行してください。</div>

  <h2 id="section-compare">Codex vs Claude Code</h2>
  <div class="note">AI分析を実行すると、両ツールの使い分け比較を生成します。<br><code>codex-insights --force</code> を実行してください。</div>
PLACEHOLDER
fi

# --- Top Sessions ---
printf '\n  <h2 id="section-sessions">Top Sessions</h2>\n' >> "$OUTPUT_HTML"
echo "$top_sessions" | jq -c '.[]' | while read -r session; do
  sid=$(echo "$session" | jq -r '.id')
  scount=$(echo "$session" | jq -r '.count')
  first_msg=$(html_escape "$(echo "$session" | jq -r '.first_msg' | head -c 120)")
  short_id="${sid:0:12}"
  printf '  <div class="session-card"><div class="area-header"><span class="area-name">%s...</span><span class="area-count">%s messages</span></div><div class="session-msg">%s</div></div>\n' "$short_id" "$scount" "$first_msg" >> "$OUTPUT_HTML"
done

# --- Footer ---
cat >> "$OUTPUT_HTML" <<FOOTER
  <p style="margin-top:48px;font-size:12px;color:#94a3b8;text-align:center;">Generated: ${generated_at}</p>
</div>
<script>
function copyText(id, btn) {
  var el = document.getElementById(id);
  var text = el.textContent || el.innerText;
  navigator.clipboard.writeText(text).then(function() {
    btn.textContent = 'Copied!';
    btn.classList.add('copied');
    setTimeout(function() { btn.textContent = 'Copy'; btn.classList.remove('copied'); }, 2000);
  });
}
</script>
</body>
</html>
FOOTER

echo "$OUTPUT_HTML"
