
## 2026-03-17 11:49 - US-002 - Single-instance protection using LOCK file
Completed [US-002]: Single-instance protection using LOCK file. All gates passed.

## 2026-03-17 11:56 - US-003 - Ensure git repository exists or initialize one
Completed [US-003]: Ensure git repository exists or initialize one. All gates passed.

## 2026-03-17 11:59 - US-004 - Validate Claude CLI installation before loop start
Completed [US-004]: Validate Claude CLI installation before loop start. All gates passed.

## 2026-03-17 12:06 - US-005 - Read Ralph-style prd.json and select highest-priority unfinished ticket
Completed [US-005]: Read Ralph-style prd.json and select highest-priority unfinished ticket. All gates passed.

## 2026-03-17 12:09 - US-006 - Create deterministic gitflow feature branch from selected ticket
Completed [US-006]: Create deterministic gitflow feature branch from selected ticket. All gates passed.

## 2026-03-17 12:11 - US-007 - Load agent registry from markdown files in Agents folder
Completed [US-007]: Load agent registry from markdown files in Agents folder. All gates passed.

## 2026-03-17 12:58 - US-008 - Define agent prompt contract and structured outputs
Completed [US-008]: Define agent prompt contract and structured outputs. All gates passed.

## 2026-03-17 13:10 - US-009 - Implement planning and review loop between agents A and B
Completed [US-009]: Implement planning and review loop between agents A and B. All gates passed.

## 2026-03-17 13:17 - US-010 - Implement architecture review and ADR maintenance
Completed [US-010]: Implement architecture review and ADR maintenance. All gates passed.

## 2026-03-17 16:36 - US-011 - Implement test-first handoff from agent D to agent E
Completed [US-011]: Implement test-first handoff from agent D to agent E. All gates passed.

## 2026-03-17 17:08 - US-012 - Implement configurable per-ticket iteration retry limit
Completed [US-012]: Implement configurable per-ticket iteration retry limit. All gates passed.

## 2026-03-17 21:11 - US-013 - Implement developer and test rework loop until green or limit reached
Completed [US-013]: Implement developer and test rework loop until green or limit reached. All gates passed.

## 2026-03-17 21:18 - US-014 - Implement safe merge policy before merging to main
Completed [US-014]: Implement safe merge policy before merging to main. All gates passed.

## 2026-03-17 21:32 - US-015 - Run deployment gate and enforce quality requirements
Completed [US-015]: Run deployment gate and enforce quality requirements. All gates passed.

## 2026-03-18 09:14 - US-016 - Commit, merge to main, and update PRD and progress after successful iteration
Completed [US-016]: Commit, merge to main, and update PRD and progress after successful iteration. All gates passed.

## 2026-03-18 12:09 - US-017 - Persist structured iteration artifacts for traceability
Completed [US-017]: Persist structured iteration artifacts for traceability. All gates passed.

## 2026-03-18 13:07 - US-018 - Apply artifact summarization policy for fresh-agent iterations
Completed [US-018]: Apply artifact summarization policy for fresh-agent iterations. All gates passed.

## 2026-03-18 13:37 - US-019 - Keep terminal loop running continuously
Completed [US-019]: Keep terminal loop running continuously. All gates passed.

## 2026-03-24 23:10 - US-020 - Handle Claude rate-limit responses by waiting and resuming
Completed [US-020]: Handle Claude rate-limit responses by waiting and resuming. All gates passed.

## 2026-03-24 23:39 - US-021 - Generate first-run tech.md questionnaire and recommendations
Completed [US-021]: Generate first-run tech.md questionnaire and recommendations. All gates passed.

## 2026-03-25 01:36 - US-022 - Provide concise CLI logging and operator controls
Completed [US-022]: Provide concise CLI logging and operator controls. All gates passed.

## 2026-03-25 07:58 - US-023 - Add karl clean command for repository recovery
Completed [US-023]: Add karl clean command for repository recovery. All gates passed.

## 2026-03-25 08:53 - US-024 - Provide open-source onboarding: example workspace, README, and visual project overview
Completed [US-024]: Provide open-source onboarding: example workspace, README, and visual project overview. All gates passed.
## 2026-03-26 - US-027 - Reduce logging and add parameter to enable verbose mode
Completed [US-027]: Added --verbose flag. Default output shows concise status lines; --verbose shows full subagent output.

## 2026-03-26 - US-030 - Implement a multi instance version of karl
Completed [US-030]: Multi-instance mode via --instances N. Bash supervisor spawns parallel workers in git worktrees with atomic ticket claiming, merge arbitration, and signal propagation.

## 2026-03-27 - Migration to Claude Code subagents
Migrated agent invocation from custom bash orchestration (agents.sh, claude_invoke, rate_limit.sh) to Claude Code native subagents (.claude/agents/). Bash still orchestrates the pipeline; each stage invokes its subagent via subagent_invoke_json. Added dependency analysis on every startup, signal propagation for clean shutdown, and --verbose flag.
