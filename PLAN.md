# claude-conformance

A model-conformance layer for Claude Code: keeps local instructions (CLAUDE.md, skills, plugins) aligned with the model actually in use.

Split out of `fieldkit` on 2026-08-14 because it is not machine-provisioning — it is a tool with its own audience.

## Why it exists

**Claude Code has no model-awareness mechanism for plugins.** Verified against the docs 2026-08-14:

| Mechanism | Model-aware? |
|---|---|
| `plugin.json` | No compatibility / minimum-model / target-model field |
| Skill frontmatter | None. `disable-model-invocation` controls *who* invokes, not which model |
| Interpolation | `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`, `${CLAUDE_PROJECT_DIR}`, env vars, `${user_config.*}` — no model variable, no `$CLAUDE_MODEL` |
| `InstructionsLoaded` hook | Fires *after* load; "output and exit code are ignored" — cannot filter or correct |
| `SessionStart` hook | **The only** hook receiving `model`, and "not guaranteed to be present". Can return `additionalContext` |

So every plugin ships one instruction set for every model, forever, and **user precedence is the only correction point the platform has.** That is the durable problem. Opus 5 is the occasion, not the scope.

Anthropic said this about their own prompt — they cut 80%+ of Claude Code's system prompt for Opus 5, stating they "were overconstraining Claude Code, both through our system prompt and in our CLAUDE.md files and skills". The diagnosis is public. What is not covered anywhere found so far: **measuring which installed plugins still carry the superseded instructions.**

## Scope decision, 2026-08-14

**Opus 5 first. Refine against it. Only then generalize the adapter to other models.** Do not build a multi-model abstraction before the single-model case is proven.

**Amendment, same day: the machine now runs Fable 5** (`/model` switch, `claude-fable-5[1m]` in settings). The arrangement: **Fable is the auditor, Opus is the audited fleet** — the cavecrew agents (`lead`, `worker-x`, `reviewer`) still run Opus 5, so the doctrine's consumers are real. Anthropic publishes **no** Fable 5 prompting guidance (announcement checked 2026-08-14), so `opus-5.md` deliberately matches `fable|mythos` too, with an in-file comment saying to split it the day Fable guidance lands. This is not premature generalization: it is one profile whose match honestly states its coverage.

## Design decision, 2026-08-14: fix at source, override only where you can't

An override block is a patch over a wound. The model still reads the bad instruction, *then* reads the correction, then reconciles the two — which is precisely the "spending reasoning cycles resolving contradictions" that Anthropic cited when they cut 80% of Claude Code's system prompt. **An override reproduces a weaker version of the problem it fixes, and costs context every session forever.**

So: **rewrite the instruction at its source wherever we own the file.** Override only where source editing is structurally impossible.

| Instruction source | Own it? | Approach |
|---|---|---|
| `~/.claude/CLAUDE.md` | Yes | Edit at source |
| `~/.claude/skills/*` (via fieldkit) | Yes | Edit at source — **done**: cavecrew and research rewritten 2026-08-14 |
| `~/.claude/agents/*` | Yes | Edit at source — **not yet scanned, see next steps** |
| Plugin skills in `~/.claude/plugins/cache/**` | **No** | Override. The cache is versioned per release and auto-updates; an edit there is silently orphaned the moment the next version lands. Worst failure mode there is: it reverts without telling you |

Escape hatches for the plugin tier, none free: uninstall the plugin, fork it and install from the fork (MIT allows it; costs a rebase per upstream release), or override via precedence. **Override is the default because it is the only one with no ongoing cost.**

This is also why the "no native model-awareness" finding is the project's spine rather than trivia: if plugins could declare model compatibility, or a hook could correct instructions before the model reads them, the override tier would not need to exist at all.

**Consequence for the injector:** the model profile must *replace* the CLAUDE.md block, never sit alongside it. Net session context should end flat or lower. Measure it, don't assume it.

## State

| Piece | Status | Lives at |
|---|---|---|
| Six superseded instruction classes (A–F) | Working, in use on both machines | `fieldkit/claude/CLAUDE.{hq,mac}.md` |
| `scan-superseded.py` detector | Working, **verified** (see below) | `fieldkit/claude/skills/anthropic-conformance/scripts/` |
| Per-machine conformance ledger | Working | `fieldkit/claude/CONFORMANCE-{hq,mac}.md` |
| Staleness hook (model / version / plugin / 90-day triggers) | Working, fired for real twice | `fieldkit/claude/skills/anthropic-conformance/hooks/` |
| `model-profiles/opus-5.md` | Re-verified under Fable against the live Opus 5 page; match widened to fable/mythos | same skill dir |
| **SessionStart doctrine injector** | **Written + registered 2026-08-14**; tested match / no-match nudge / settings fallback / display-name alias. End-to-end verify needs a restart | `hooks/inject-model-profile.{ps1,sh}` |

**Extraction done 2026-08-14.** This repo (`Nyx000/claude-conformance`, **private**) IS the skill: `SKILL.md` at the root, `hooks/`, `scripts/`, `model-profiles/`, with `PLAN.md` riding along as inert repo meta. fieldkit consumes it as a **submodule** at `claude/skills/anthropic-conformance` — the exact old path, so no hook, detector, or doc path changed anywhere. `bootstrap.sh` gained a check-then-do submodule init step (fails loudly: an empty skill dir means hooks silently vanish).

**One working copy on hq.** `Documents\Projects\claude-conformance` is a junction into the submodule working tree — the old standalone checkout was deleted after verifying all three refs identical. Edits here are live immediately (skills hot-reload through `~/.claude/skills` → fieldkit → submodule). **Propagation to the Mac:** commit + push here, then bump the submodule pointer in fieldkit (`git -C fieldkit submodule update --remote` + commit + push); the Mac picks it up on `git pull && git submodule update --init`.

## Next steps

1. ~~**Extract.**~~ **Done 2026-08-14** — see above.
2. ~~**Write the SessionStart injector.**~~ **Done 2026-08-14.** As designed, with one simplification: the ledger cross-check for ambiguous aliases was dropped — substring-style match regexes (`(claude-)?(opus|fable|mythos)[- ]?5`) already cover every alias form (`opus[1m]`, `claude-fable-5[1m]`, display names like `Opus 5 (1M context)`), so the extra lookup bought nothing. Registered matcher-less (fires on startup, resume, clear, AND compact) so doctrine survives compaction once CLAUDE.md shrinks to a pointer. `settings.mac.json` gained the registration too, plus the `conformance-check.sh` line that had been live-only on the Mac and never templated.
3. ~~**Shrink CLAUDE.md**~~ **Done 2026-08-14.** Both `CLAUDE.{hq,mac}.md` doctrine blocks replaced by a pointer that **adopts the injected block's authority** — hook output is context, not automatically instruction-ranked, so the pointer's "carries the full authority of this file" line is what preserves user-layer precedence. Fallback documented: hook failure → read the profile directly and flag it.
4. ~~**Verify injection end-to-end**~~ **Done 2026-08-14.** Full profile appeared in session context via `SessionStart:resume` after restart. Found + fixed en route: PS 5.1 encoding mojibake (ANSI read / OEM write) — UTF-8 forced both ends, byte-verified under the registered binary. Context math: ~3.3 KB removed from CLAUDE.md vs ~3.6 KB injected per SessionStart event — net flat, gaining per-model matching and compaction survival.
5. ~~**Widen the detector past `skills/`.**~~ **Done 2026-08-14.** Now scans agents, output styles, and CLAUDE.md (42 units, was 32). The widening immediately earned its keep: `cavecrew-lead` still carried the unconditional review-gate and verification-command wording the skill-level fix had missed — proof that fixing a doctrine in one file doesn't fix its echoes.
6. **Rewrite, don't just neutralize.** For every source-owned hit, write the Opus-5-native replacement instruction instead of deleting the line. A skill that says nothing about verification is worse than one that says the right thing. *Applied to `cavecrew-lead:19-20` 2026-08-14; remaining local hits ruled FP in the ledger.*
7. Then, and only then, generalize: a second profile for another model.

## Verification done so far

Detector fixture test (`--root` exists for this): a synthetic skill carrying one line per class produced **all six — zero false negatives**; an ordinary synthetic skill produced **nothing — zero false positives**. Known FP rate on the real tree: 1 of 10 flagged files (`cavecrew:47` matches class A on the text of its own fix).

Live scan, 32 skills, 10 flagged. Two findings the per-plugin framing would have missed: **microsoft-docs carries class F** (a second vendor), and superpowers `writing-skills:240` instructs *"Always use subagents"* as authoring guidance, propagating the anti-pattern into anything written with it.

## Open, needs a decision

- **Public repo** — the repo now exists as **private** (`Nyx000/claude-conformance`, created 2026-08-14 with explicit approval); going public remains gated on its own approval. The `_archive` bundle is superseded by the remote as the off-machine copy.
- **Reddit post** — drafted in conversation on 2026-08-14, unposted. Must not claim novelty: Anthropic published the diagnosis themselves.
- **`/doctor` overlap** — unresolved. `claude doctor` (CLI) is an installation check only; the in-session `/doctor` claims a "full setup checkup that can also fix issues" and one blog says it proposes CLAUDE.md deletions. **Run `/doctor` and compare before publishing anything**, or the project may duplicate a shipped feature.
- **Class F** is arguably redundant with the `caveman-light` output style. **Class E is a local extension** — Anthropic states no rule on invocation thresholds — and is marked as such so it can be argued with.

## Honest scoping note

Charles Jones's version of this advice is one line: grep for "verify", "double-check", "confirm" and delete what you find. The detector is a nicer, testable, classified version of that grep — not a different idea. The parts that are genuinely additive: the class taxonomy with per-class source lines, the per-machine ledger with three verdicts (conform / deliberate override / drift), version-gated overrides, and the measurement across installed plugins.
