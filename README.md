# claude-conformance

A model-conformance layer for Claude Code. It keeps every locally installed instruction source (plugin skills, your own skills, agents, output styles, and CLAUDE.md itself) aligned with Anthropic's current published guidance for the model you are actually running.

## The problem

Claude Code has no mechanism that tells a plugin which model it is running against. There is no compatibility field in `plugin.json`, no model interpolation variable, and no hook that can filter or correct a skill's instructions before the model reads them. Every plugin ships one instruction set for every model, forever.

That mattered less when models changed slowly. It matters a lot now: Anthropic's prompting guidance for Claude Opus 5 explicitly says to *remove* instruction patterns that earlier models needed. Mandatory verification steps, standing review gates, and delegate-by-default rules were written against models that under-delivered. On current models they cause over-verification, wasted subagent spawns, and token burn with no quality gain. Anthropic said this about their own scaffolding when they cut over 80% of Claude Code's system prompt, noting they "were overconstraining Claude Code, both through our system prompt and in our CLAUDE.md files and skills."

The diagnosis is public. What this repo adds is the measurement and the correction: which of *your* installed instructions are superseded, and a mechanism that applies the current model's doctrine from the one layer that outranks every plugin.

## How it works

Claude Code's instruction precedence is: user instructions, then skills, then default behavior. A plugin's skill text cannot be edited durably (the plugin cache re-downloads on every release), but it can be outranked. This repo operates at the user-instruction layer, so no plugin needs to cooperate and plugins installed next month are covered the same as plugins installed today.

Three pieces:

**`scripts/scan-superseded.py`** scans every instruction source on the machine for six superseded instruction classes, each traceable to a specific line of Anthropic guidance (or explicitly marked as a local extension where it is not). It matches on what an instruction *does*, never on which plugin ships it. A hit is a line to read and rule on, not an automatic defect: the regexes deliberately over-match so nothing slips past.

| Class | Superseded pattern | Source |
|---|---|---|
| A | Mandated verification before completion claims | "remove verification instructions; they cause over-verification" |
| B | Standing review gates and subagent verification | "do not use subagents to verify or double-check your own work" |
| C | Delegate-by-default | "delegate only for large, genuinely independent tracks; keep spawn counts low" |
| D | Re-check / double-check instructions | "avoid instructing re-checks it already performs" |
| E | Mandatory-invocation thresholds and ceremony | Local extension, marked arguable: Anthropic states no rule here |
| F | Fixed-template padding in deliverables | "match length to what the task needs; do not pad" |

**`hooks/inject-model-profile.{ps1,sh}`** is a SessionStart hook that resolves the running model and prints the matching doctrine from `model-profiles/` into session context. It fires on startup, resume, clear, and compact, so the doctrine survives compaction. An unrecognized model gets a one-line "derive a profile" nudge rather than silently applied wrong rules.

**`hooks/conformance-check.{ps1,sh}`** is a staleness nudge with four deliberately unequal triggers: a model change (full re-derivation), a Claude Code version change (mechanics scan), any plugin update or new install (re-scan plus override-expiry check), and 90 days elapsed (catches silent doc revisions). It prints nothing when the audit is current.

The audit procedure itself lives in `SKILL.md`, and its findings go to a dated per-machine ledger with three verdicts: CONFORM, OVERRIDE (deliberate, with the reason recorded), or DRIFT (unintentional, needs action). Recording overrides is what stops a later audit from re-litigating a decision already made. Every override is version-gated: it expires the day the upstream plugin ships a model-aware release.

## The split that makes edits safe

Files you own get fixed at the source: the superseded line is rewritten to say the right thing for the current model, with history in git and rationale in the ledger. Files you do not own (the plugin cache) are never edited, because the cache auto-updates and silently reverts your edit with no warning. Those are superseded from above instead. The residual cost is honest and bounded: the model still reads the superseded text and reconciles it against the doctrine, roughly 450 tokens of rule against the hundreds to thousands of tokens of unneeded verification *work* it suppresses.

## Install

This repo is itself a Claude Code skill. Clone it into your skills directory:

```
git clone https://github.com/Nyx000/claude-conformance.git ~/.claude/skills/anthropic-conformance
```

Then register the two hooks in your `settings.json` under `SessionStart` (use the `.ps1` variants on Windows, `.sh` on macOS and Linux). The staleness check belongs under a `startup` matcher; the injector should have no matcher so it also fires on resume, clear, and compact. Run the scanner directly any time:

```
python3 ~/.claude/skills/anthropic-conformance/scripts/scan-superseded.py
```

## Status and honest scoping

The current profile is derived from the Claude Opus 5 prompting guidance and deliberately also matches Fable 5 and Mythos 5, because Anthropic publishes no prompting guidance for those models yet; the profile header says to split it the day that changes. One profile, honestly labeled, rather than a premature multi-model abstraction.

The simplest version of this idea is a grep for "verify" and "double-check" followed by deleting what you find. The scanner is a nicer, testable, classified version of that grep, not a different idea. The parts that are genuinely additive: the class taxonomy with per-class source lines, the three-verdict ledger, version-gated overrides, and the model-matched injection that survives compaction.

## License

MIT
