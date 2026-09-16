#!/usr/bin/env bash
# SessionStart / PostModelSwitch hook: inject the conformance doctrine for the model
# actually in use. Resolves the model (hook stdin JSON `model` or `to_model` field, else
# ANTHROPIC_MODEL, else settings.json), then prints the first model-profiles/*.md whose
# first-line `<!-- match: <regex> -->` matches it.
# stdout reaches session context on both SessionStart and PostModelSwitch (the hooks docs
# name PostModelSwitch as one of the few events where plain-text stdout becomes context),
# so the printed profile IS the doctrine injection either way.
# No match -> a one-line "derive a profile" nudge, never a silently-applied wrong profile.
# When the model came from the env var or settings.json fallback rather than the session
# payload, a visible HTML-comment label is prepended so a misfire (payload absent, wrong
# model pinned) is catchable from inside the session instead of silent (measured
# 2026-09-16: a Fable 5.1 session with no stdin `model` field fell through to settings.json
# and got the Opus 5 doctrine with no marker).
# Always exits 0 — a hook must never block a session start.
# macOS/Linux counterpart to inject-model-profile.ps1.

set +e

# Profile filenames must be lowercase ASCII. LC_ALL=C makes the glob below sort
# bytewise; the ps1 port sorts on the lowercased name. Without both, "first matching
# profile wins" resolves to DIFFERENT files on the two machines the moment a second
# profile with an overlapping regex lands — sh globs by LC_COLLATE (uppercase first
# under C), ps1 sorted culture-aware and case-insensitive.
LC_ALL=C
export LC_ALL

stdin=$(cat 2>/dev/null)
model_source="payload"
model=$(printf '%s' "$stdin" | sed -n 's/.*"model" *: *"\([^"]*\)".*/\1/p' | head -1)
# PostModelSwitch's payload carries "to_model", not "model" (SessionStart is the only
# event with "model", per the hooks docs). Both are the session payload itself, so a hit
# here is never a fallback and gets no label.
if [ -z "$model" ]; then
  model=$(printf '%s' "$stdin" | sed -n 's/.*"to_model" *: *"\([^"]*\)".*/\1/p' | head -1)
fi
# A run-time override (`claude --model X`, or an exported ANTHROPIC_MODEL) never
# touches settings.json. Resolving from settings alone therefore injected the PINNED
# model's doctrine into an overridden session — a silently-applied WRONG profile,
# which the header above promises cannot happen. Env sits ahead of settings for that.
# Both of these ARE fallbacks (the session payload carried nothing usable), so both get
# the label below.
if [ -z "$model" ]; then
  model="${ANTHROPIC_MODEL:-}"
  if [ -n "$model" ]; then model_source="the ANTHROPIC_MODEL env var"; fi
fi
if [ -z "$model" ]; then
  model_source="settings.json"
  model=$(sed -n 's/.*"model" *: *"\([^"]*\)".*/\1/p' "$HOME/.claude/settings.json" 2>/dev/null | head -1)
fi

dir="$(cd "$(dirname "$0")/../model-profiles" 2>/dev/null && pwd)"
{ [ -z "$model" ] || [ -z "$dir" ] || [ ! -d "$dir" ]; } && exit 0

for f in "$dir"/*.md; do
  [ -f "$f" ] || continue
  rx=$(head -1 "$f" | sed -n 's/<!-- *match: *\(.*[^ ]\) *-->/\1/p')
  [ -n "$rx" ] || continue
  if printf '%s' "$model" | grep -qiE "$rx"; then
    if [ "$model_source" != "payload" ]; then
      base="$(basename "$f" .md)"
      echo "<!-- resolved from $model_source \"$model\": the session payload carried no model. If the session banner names another family, apply model-profiles/$base.md instead and flag it -->"
    fi
    cat "$f"
    exit 0
  fi
done

echo "No conformance profile matches model '$model' - its doctrine has never been derived. Run the 'anthropic-conformance' skill to derive one; profiles at $dir"
exit 0
