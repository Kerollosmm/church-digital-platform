# Workflow & Multi-Agent Collaboration Patterns

## 1. Caveman Mode (ULTRA) — Always On
- Per `AGENTS.md` and user directive, always operate in **Caveman ULTRA** mode during chat turns to minimize token consumption.
- **Rules**: Strip articles, filler words, hedging, pleasantries. Telegraphed fragments only. Keep numbers, units, code symbols, and error messages exact.
- **Exceptions (Normal Prose)**: Critical security warnings, irreversible destructive actions, and content persisted outside chat (code, comments, commits, docs, memory files).

## 2. Fable Mode (Cognitive Engine & Deterministic System 2 Architecture) — ALWAYS ON
- **Dual-Process System 2 Deliberation**: Engage deep cognitive deliberation before committing architecture, schema, or system modifications. Intuitive proposals must undergo counter-factual falsification against system invariants.
- **Strict Cognitive Separation**:
  - **Main Agent**: Master Architect & System 2 Conductor. Performs DeepThink deliberation, invariant proofs, architectural blueprints, and multi-tier verification quality gates. Forbids direct editing or writing of codebase files during planning/reasoning phases.
  - **Subagent Fleet**: Executes 100% of code edits (`write_to_file`, `replace_file_content`), unit test authoring, and build fixes under explicit delegation contracts.
- **Anti-Hallucination Epistemic Grounding**: Classify every assertion strictly:
  - `[PROVEN]`: Verified by concrete live-tool evidence (file contents, terminal commands, compiler output). Concrete evidence pointer required.
  - `[HYPOTHESIS]`: Untested assumption; must be empirically probed before commitment.
  - `[UNKNOWN]`: Unmeasured constraint; must be investigated before proceeding.
  - Never design or build architectures on unverified `[HYPOTHESIS]`.
- **Continuous Rethink-Refine Loop**: Stress-test edge cases, concurrency races, memory layouts, and failure modes via `log_refinement_cycle`.
- **Session & Timer Management**: Utilize `fable-engine` MCP (`fable_session` tool) for session initialization (`create_session`), epistemic ledger logging (`log_epistemic_step`), refinement cycles, and formal invariant verification.

## 3. Multi-Agent Collaboration & Review Protocol
- User may utilize an external coding agent ("agy agent", e.g. Gemini 3.7 Flash) to implement features rapidly.
- **Reviewer Invariant**:
  - Do not blindly trust claims from implementation agents or relays.
  - Independently verify all code, migration files, and database assertions against the live environment.
  - Handoff doc pattern: `.scratch/<feature>-handoff.md` (self-contained state + non-negotiable rules + stop conditions).

## 4. Bulk Code Reading & Delegation (`agy-delegate`)
- To conserve context tokens during heavy multi-file audits, delegate bulk reads to the `agy-delegate` relay:
  ```powershell
  node "C:/Users/KimoStore/.claude/skills/agy-delegate/scripts/relay.mjs" --brief <brief-file> --cd "C:/church" --print-timeout 40m --timeout 45m
  ```
- **Safety Rule**: Relay has read-only scope and never commits. All reported high/blocker findings must be independently confirmed with direct SQL queries or file reads.

## 5. Web Research Workarounds
- When standard search tools encounter backend errors:
  1. `curl` + DuckDuckGo Lite (`https://lite.duckduckgo.com/lite/?q=...`) — extract links; space requests to avoid rate limits.
  2. `r.jina.ai/<url>` reader proxy to render web pages as markdown and bypass Cloudflare / JS shell hurdles.
  3. `firecrawl-workflows` skills available in `.agents/skills/`.

