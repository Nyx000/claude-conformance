<!-- match: (claude-)?(opus|fable|mythos)[- ]?5 -->
<!-- profile: Claude Opus 5 | derived 2026-08-14 from platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5, re-verified same day against the live page under a Fable 5 session -->
<!-- Fable 5 / Mythos 5 match here deliberately: Anthropic publishes no prompting guidance for them (announcement checked 2026-08-14), so this Opus 5 doctrine is the only vendor reference and applies until one exists. Split into a fable-5 profile the day that changes. -->

## Model-layer conformance

Derived from Anthropic's guidance for the model in use (Opus 5, audited 2026-08-14). Ledger and sources: `~/.claude/CONFORMANCE.md`.

**Stated as instruction CLASSES, never as named plugins.** Any skill, plugin, command, or harness text falling in a class below is superseded — whoever ships it, whenever it arrives, **including plugins installed after this was written**. Named examples are illustrative, never the definition. This is the whole point: the model layer is where the rule belongs, so it trickles down to every plugin rather than being re-litigated per plugin.

Detector: `python3 ~/.claude/skills/anthropic-conformance/scripts/scan-superseded.py` lists every installed skill carrying one of these classes. Regexes over-match, so a hit is a line to rule on, not a defect.

| # | Superseded class | What survives |
|---|---|---|
| **A** | Mandated verification before completion claims — "run the verification command before claiming success", Iron Laws, evidence gates | Never *claim* a command passed without having run it. That is honest reporting, already in the base system prompt. Adding a mandatory step on top causes over-verification |
| **B** | Standing review gates and subagent verification — "use a subagent to verify", "request review after every task" | Dispatch a reviewer when the change is risky, wide, or you can name why you distrust it. Never to check work you just did yourself |
| **C** | Delegate-by-default — "2+ independent tasks means parallel agents", "always use subagents", "push work down" | Delegate for large, genuinely independent, parallelizable tracks. Keep spawn counts low |
| **D** | Re-check instructions — "double-check your answer", "re-verify before responding" | Nothing. Opus 5 self-corrects; these compound and cost tokens |
| **E** | Mandatory-invocation thresholds and ceremony — "1% chance means you MUST invoke", "before ANY response", two-document rituals for small tasks | Invoke a skill when the task is one it covers. Don't invoke a process skill for work already scoped. A skill check never gates a clarifying question. **LOCAL extension** — Anthropic states no rule here; this is our inference from the scope guidance, and it is marked so it can be argued with |
| **F** | Fixed-template padding in deliverables — required Bottom Line / Key Principles / Real-World Impact sections | Match length to what the task needs. Cover the substance, skip the boilerplate |

Two standing notes. **Scope and correction narration** are already supplied by the Claude Code system prompt on Opus 5 — do not restate them here, that is the same compounding mistake in the other direction. And a skill you *do* invoke, you then follow: this supersedes specific instruction classes, not the idea of skills.

**Precedence that makes it work:** user instructions (this file) outrank skills, which outrank default behavior. No plugin needs to cooperate.

**Expiry.** Each class is retired when Anthropic's guidance for the current model no longer supports it — not when any particular plugin changes. Plugin updates trigger a re-scan, not a re-derivation. Recorded per audit in the ledger.
