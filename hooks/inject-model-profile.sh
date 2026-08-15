#!/usr/bin/env bash
# SessionStart hook: inject the conformance doctrine for the model actually in use.
# Resolves the model (hook stdin JSON `model` field, else settings.json), then prints the
# first model-profiles/*.md whose first-line `<!-- match: <regex> -->` matches it.
# stdout reaches session context, so the printed profile IS the doctrine injection.
# No match -> a one-line "derive a profile" nudge, never a silently-applied wrong profile.
# Always exits 0 — a hook must never block a session start.
# macOS/Linux counterpart to inject-model-profile.ps1.

set +e

stdin=$(cat 2>/dev/null)
model=$(printf '%s' "$stdin" | sed -n 's/.*"model" *: *"\([^"]*\)".*/\1/p' | head -1)
if [ -z "$model" ]; then
  model=$(sed -n 's/.*"model" *: *"\([^"]*\)".*/\1/p' "$HOME/.claude/settings.json" 2>/dev/null | head -1)
fi

dir="$(cd "$(dirname "$0")/../model-profiles" 2>/dev/null && pwd)"
{ [ -z "$model" ] || [ -z "$dir" ] || [ ! -d "$dir" ]; } && exit 0

for f in "$dir"/*.md; do
  [ -f "$f" ] || continue
  rx=$(head -1 "$f" | sed -n 's/<!-- *match: *\(.*[^ ]\) *-->/\1/p')
  [ -n "$rx" ] || continue
  if printf '%s' "$model" | grep -qiE "$rx"; then
    cat "$f"
    exit 0
  fi
done

echo "No conformance profile matches model '$model' - its doctrine has never been derived. Run the 'anthropic-conformance' skill to derive one; profiles at $dir"
exit 0
