---
name: codex-insights
description: Generate and report Codex usage insights.
---

# Codex Insights

Usage:
- Terminal: `codex-insights`
- Interactive: `codex` -> type "Codex Insights を実行して"

Analyze Codex CLI session history and generate a usage report.

## What It Does

1. **Run the analysis script** to collect raw metrics:
   ```bash
   codex-insights
   ```
   This generates `~/.codex/usage-data/report.html` with stats and charts.

2. **Deep analysis** -- go beyond the raw stats:
   - Read `~/.codex/history.jsonl` to understand conversation patterns
   - Sample 3-5 session JSONL files from `~/.codex/sessions/` to understand tool usage and workflow patterns
   - Identify friction points (repeated corrections, error loops, scope misunderstandings)
   - Note which agents/skills were used and how effectively

3. **Generate insights report** covering:
   - **At a Glance**: What's working well, what's hindering, quick wins
   - **Project Areas**: Group sessions by project/topic
   - **Interaction Style**: How you use Codex vs Claude Code
   - **Friction Analysis**: Where things go wrong and why
   - **Suggestions**: Concrete improvements with copyable prompts

4. **Save AI analysis** to `~/.codex/usage-data/insights.json` so the HTML report includes:
   - Wins, friction points, suggestions with copyable prompts
   - instructions.md additions
   - Codex vs Claude Code comparison

## Data Sources

- `~/.codex/history.jsonl` -- user messages with session_id and timestamp
- `~/.codex/sessions/{year}/{month}/{day}/*.jsonl` -- full session transcripts with:
  - `session_meta`: project dir, git branch, CLI version
  - `event_msg`: user messages with images
  - `response_item`: assistant responses, function_calls (exec_command, custom_tool_call), reasoning
  - `turn_context`: approval policy, collaboration mode

## insights.json Schema

Save to `~/.codex/usage-data/insights.json`:
```json
{
  "at_a_glance": {
    "working": "string",
    "hindering": "string",
    "quick_wins": "string"
  },
  "wins": [{"title": "string", "desc": "string"}],
  "friction": [{"title": "string", "desc": "string", "example": "string"}],
  "instructions_additions": [{"text": "string", "why": "string"}],
  "suggestions": [{"title": "string", "desc": "string", "prompt": "string"}],
  "comparison": {
    "codex": ["string"],
    "claude": ["string"]
  }
}
```

## Rules

- Do NOT fabricate any statistics -- only report what the data shows
- Compare with Claude Code usage patterns if `~/.claude/` data is available
- Keep suggestions actionable and specific to the user's actual workflow
