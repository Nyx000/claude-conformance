---
name: anthropic-conformance
description: Use when auditing this machine's Claude Code config against Anthropic's current published guidance — after a model change, after a plugin or Claude Code update, on a scheduled review, or whenever you suspect local doctrine has drifted from vendor best practice. Also use before trusting any claim that the setup "follows best practices".
---

# Anthropic conformance audit

Local config drifts from vendor guidance silently: docs change without notice, plugins auto-update, and doctrine written for one model outlives it. Memory is not evidence. This skill re-derives conformance from fetched sources every time.

Ledger: `~/.claude/CONFORMANCE.md`. It is the output, not a reference — never answer a conformance question from it without re-running the audit or checking its `Last audited` date.

## Run it

### 1. Establish what model and version we are on

```
claude --version
```
Plus `model` and `effortLevel` in `~/.claude/settings.json`. Guidance is model-specific — auditing against the wrong model's page is worse than not auditing.

### 2. Fetch the manifest

Every URL in the ledger's Source manifest, in one parallel block. **Fetch, do not snippet.** A search summary of a guidance page is not the guidance page.

Anything you skip gets marked *not fetched* on that row of the manifest, with the date. A silently skipped source reads as coverage.

### 3. Enumerate the local surface

All of it, every pass — drift hides in whichever file you assumed was fine:

| Surface | Path |
|---|---|
| Global doctrine | `~/.claude/CLAUDE.md` |
| Settings + env caps | `~/.claude/settings.json`, `settings.local.json` |
| Output style | `~/.claude/output-styles/` |
| Own skills | `~/.claude/skills/` |
| Own agents | `~/.claude/agents/` |
| Plugin skills (auto-update, so re-read) | `~/.claude/plugins/cache/**/skills/` |
| Harness-injected text | the live system prompt in the current session |

That last row matters most and is the easiest to forget: the harness injects model-specific instructions of its own. Read what is actually in this session's system prompt before concluding a mitigation is missing — several are already supplied, and a local rule that contradicts an injected one loses at runtime.

### 4. Classify every guidance item

Three verdicts, never two:

| Verdict | Means |
|---|---|
| CONFORM | local state matches, or the harness already supplies it |
| OVERRIDE | we deliberately deviate — **record the reason on the row** |
| DRIFT | unintentional deviation — gets an action id |

Collapsing OVERRIDE into DRIFT is the failure mode that makes an audit useless: it re-opens settled decisions every pass and trains you to ignore the report. Collapsing it the other way hides real drift behind "we meant that."

### 5. Write the ledger and the audit log row

Update the table, the action list, the manifest's fetch marks, and append to the audit log. Report the delta out loud: conform count, new drift, actions opened and closed.

## When to run — and how much to run

The four triggers are not equal in cost. Running the full audit on a patch bump trains you to ignore the hook.

| Trigger | Scope | Roughly |
|---|---|---|
| **Model change** | Full re-derivation. The doctrine block is *entirely* model-calibrated — every rule exists because the previous model did or didn't do something unprompted. A new model can make an override actively harmful, not just unnecessary | an hour |
| **Claude Code version** | Mechanics only: env var names and defaults, tool renames, feature floors, hook API. Doctrine is untouched | minutes |
| **Plugin update** | Expiry check on that plugin's overrides. Diff the superseded skills against the audited version; if unchanged, record and stop | minutes |
| **90 days** | Periodic, catches silent doc revisions with no version bump. Weakest signal | a re-fetch |

Also run it on a community signal that a model behaves differently than expected — that is what started this ledger.

## The goal is to need this less

Most of the first pass was **removing scaffolding**, not adding rules: mandatory verification, standing review gates, delegate-by-default. All of it was written to compensate for models that under-delivered, and all of it had become harmful. That removal is a one-time crossing, not recurring work.

So judge this skill by whether the doctrine block **shrinks**. Every rule in it is compensation for a specific model's behavior, and compensation is a liability that has to be re-checked forever. A rule you can delete is worth more than a rule you can justify.

The end state is a CLAUDE.md carrying only genuinely personal preference — how you like output shaped, how you work — and zero model-compensating instructions. At that point a model change needs no audit at all, because nothing is being compensated for. Anything short of that, the ledger records what compensation is live and why.

## Traps

- **Guidance is versioned; treat undated advice as expired.** A blog post about the previous model is worse than nothing.
- **Don't confuse the model's floor with your layer's ceiling.** Behavior you dislike may come from a local skill amplifying a default, not from the model.
- **Skills that mandate a process are the usual drift source**, because they were written to fix a *previous* model's weakness. Ask of each: which model's failure mode was this written against?
- **CLAUDE.md reaches subagents as a session-start snapshot.** Edits need a restart before dispatched agents see them.
- **Anthropic guidance can contradict a skill you trust.** Cite both, say which is newer, and let the vendor page win unless there's a recorded reason it should not.
- **"Official marketplace" is distribution, not authorship.** Check `plugin.json` for the author and the release date before treating a plugin as vendor guidance — several in the official marketplace are third-party and predate the current model. A plugin that never names the model you are running was not calibrated for it.
- **Gate every override on a version, not on forever.** An override recorded without an expiry becomes permanent drift in the other direction once upstream fixes the problem. Each audit re-checks whether the upstream release that would retire an override has shipped.
