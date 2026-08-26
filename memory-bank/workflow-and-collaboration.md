# Workflow & Multi-Agent Collaboration Patterns

## 1. Caveman Mode (ULTRA) — Always On
- Per `AGENTS.md` and user directive, always operate in **Caveman ULTRA** mode during chat turns to minimize token consumption.
- **Rules**: Strip articles, filler words, hedging, pleasantries. Telegraphed fragments only. Keep numbers, units, code symbols, and error messages exact.
- **Exceptions (Normal Prose)**: Critical security warnings, irreversible destructive actions, and content persisted outside chat (code, comments, commits, docs, memory files).

## 2. Multi-Agent Collaboration & Review Protocol
- User may utilize an external coding agent ("agy agent", e.g. Gemini 3.7 Flash) to implement features rapidly.
- **Reviewer Invariant**:
  - Do not blindly trust claims from implementation agents or relays.
  - Independently verify all code, migration files, and database assertions against the live environment.
  - Handoff doc pattern: `.scratch/<feature>-handoff.md` (self-contained state + non-negotiable rules + stop conditions).

## 3. Bulk Code Reading & Delegation (`agy-delegate`)
- To conserve context tokens during heavy multi-file audits, delegate bulk reads to the `agy-delegate` relay:
  ```powershell
  node "C:/Users/KimoStore/.claude/skills/agy-delegate/scripts/relay.mjs" --brief <brief-file> --cd "C:/church" --print-timeout 40m --timeout 45m
  ```
- **Safety Rule**: Relay has read-only scope and never commits. All reported high/blocker findings must be independently confirmed with direct SQL queries or file reads.

## 4. Web Research Workarounds
- When standard search tools encounter backend errors:
  1. `curl` + DuckDuckGo Lite (`https://lite.duckduckgo.com/lite/?q=...`) — extract links; space requests to avoid rate limits.
  2. `r.jina.ai/<url>` reader proxy to render web pages as markdown and bypass Cloudflare / JS shell hurdles.
  3. `firecrawl-workflows` skills available in `.agents/skills/`.
