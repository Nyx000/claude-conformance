#!/usr/bin/env bash
# SessionStart hook: nudge when the Anthropic conformance audit is stale.
# Four triggers, deliberately NOT equal in cost — the message names the scope so a
# cheap trigger doesn't read like an expensive one:
#   model change   -> full re-derivation (the doctrine block is entirely model-calibrated)
#   version change -> mechanics scan only (env vars, tool names, feature floors)
#   plugin change  -> override-expiry check (a version-gated override may be retirable)
#   90 days        -> periodic, catches silent doc revisions
# Prints nothing when current. Always exits 0 — a hook must never block a session start.
# macOS/Linux counterpart to conformance-check.ps1.

set +e

# Per-machine ledger: CONFORMANCE-<host>.md if present, else CONFORMANCE.md
host=$(hostname -s 2>/dev/null || echo unknown)
ledger="$HOME/.claude/CONFORMANCE-$host.md"
[ -f "$ledger" ] || ledger="$HOME/.claude/CONFORMANCE.md"
[ -f "$ledger" ] || exit 0

field() { sed -n "s/^- \*\*$1:\*\* *//p" "$ledger" | head -1; }

audited_date=$(field "Last audited")
audited_ver=$(field "Claude Code" | grep -oE '^[0-9][0-9.]*')
audited_model=$(field "Model audited")
audited_ids=$(field "Model ids audited")
audited_plugins=$(field "Plugins audited")

reasons=""
add() { reasons="${reasons:+$reasons; }$1"; }

# Model drift — the expensive one
settings="$HOME/.claude/settings.json"
if [ -f "$settings" ]; then
  model=$(sed -n 's/.*"model" *: *"\([^"]*\)".*/\1/p' "$settings" | head -1)
  # settings.json holds an ALIAS ('opus[1m]'), the prose 'Model audited' line holds a display
  # name ('Claude Opus 5'). Substring-matching one against the other nudges on every session
  # after a /model switch that changed nothing about the doctrine. Compare against the explicit
  # id list instead; fall back to the prose only on an old ledger that lacks the field.
  if [ -n "$model" ]; then
    if [ -n "$audited_ids" ]; then
      if ! printf '%s' "$audited_ids" | tr ',' '\n' | sed 's/^[ `]*//; s/[ `]*$//' | grep -qixF "$model"; then
        add "MODEL now '$model' (not in audited ids: $audited_ids) - full re-derivation"
      fi
    elif ! printf '%s' "$audited_model" | grep -qF "$model"; then
      add "MODEL now '$model' (ledger: '$audited_model') - full re-derivation"
    fi
  fi
fi

# Claude Code version drift — mechanics only
current_ver=$(claude --version 2>/dev/null | grep -oE '^[0-9][0-9.]*')
if [ -n "$current_ver" ] && [ -n "$audited_ver" ] && [ "$current_ver" != "$audited_ver" ]; then
  add "Claude Code $audited_ver -> $current_ver - mechanics scan"
fi

# Plugin drift — ANY plugin, not a named list. A plugin installed after the last
# audit can ship superseded instruction classes just as easily as an updated one.
cache="$HOME/.claude/plugins/cache"
if [ -d "$cache" ]; then
  changed=""; added=""
  for plug in "$cache"/*/*; do
    [ -d "$plug" ] || continue
    name=$(basename "$plug")
    # temp_git_* is an in-flight clone, not an installed plugin
    case "$(basename "$(dirname "$plug")")" in temp_git_*) continue ;; esac
    # Prefer a version dir. A plugin installed from a git ref has ONLY a hash dir, and
    # skipping those made live plugins invisible to drift detection entirely (context7,
    # frontend-design — found 2026-08-15). Fall back to the newest hash dir and track
    # the hash as the version.
    now=$(ls -1 "$plug" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' | sort -V | tail -1)
    # Hash-shaped (or literally 'unknown') dirs only — a plugin checked out FLAT has
    # ordinary subdirs (src, tests, skills) that would each read as a phantom plugin
    [ -n "$now" ] || now=$(ls -1t "$plug" 2>/dev/null | grep -E '^([0-9a-f]{7,40}|unknown)$' | head -1)
    [ -n "$now" ] || continue
    was=$(printf '%s' "$audited_plugins" | tr ',' '\n' | awk -v n="$name" '$1==n {print $2; exit}')
    if [ -z "$was" ]; then
      added="${added:+$added, }$name $now"
    elif [ "$was" != "$now" ]; then
      changed="${changed:+$changed, }$name $was -> $now"
    fi
  done
  [ -n "$changed" ] && add "plugins changed: $changed - re-scan for superseded classes"
  [ -n "$added" ] && add "plugins NEW since audit: $added - never scanned"
fi

# Age — weakest signal, catches silent doc revisions
if [ -n "$audited_date" ] && command -v python3 >/dev/null 2>&1; then
  age=$(python3 -c "import datetime
try:
    d=datetime.date.fromisoformat('$audited_date'); print((datetime.date.today()-d).days)
except Exception: print(0)" 2>/dev/null)
  if [ -n "$age" ] && [ "$age" -gt 90 ] 2>/dev/null; then
    add "$age days since last audit - periodic"
  fi
fi

[ -n "$reasons" ] && echo "Conformance audit stale: $reasons. Run the 'anthropic-conformance' skill; ledger at $ledger"

exit 0
