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
# Windows counterpart to inject-model-profile.sh.

$ErrorActionPreference = 'SilentlyContinue'

# Windows PowerShell 5.1 (the registered binary) reads files as ANSI and writes the OEM
# codepage by default; either direction turns the profile's em-dashes into mojibake in
# session context (seen live 2026-08-14). Force UTF-8 on both ends.
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$model = $null
$modelSource = 'payload'
try {
    $stdin = [Console]::In.ReadToEnd()
    if ($stdin) {
        $obj = $stdin | ConvertFrom-Json
        $model = $obj.model
        # PostModelSwitch's payload carries `to_model`, not `model` (SessionStart is the
        # only event with `model`, per the hooks docs). Both are the session payload
        # itself, so a hit here is never a fallback and gets no label.
        if ($model -isnot [string]) { $model = $obj.to_model }
    }
} catch {}
# The sh port extracts a STRING-valued "model"/"to_model" with sed. ConvertFrom-Json
# would happily hand back an object and stringify it later, so the two ports resolved
# different values for the same payload. Accept a string or nothing.
if ($model -isnot [string]) { $model = $null }
# A run-time override (`claude --model X`, or ANTHROPIC_MODEL) never touches
# settings.json. Resolving from settings alone injected the PINNED model's doctrine into
# an overridden session — the silently-applied wrong profile the header says cannot
# happen. Env sits ahead of settings for exactly that case. Both of these ARE fallbacks
# (the session payload carried nothing usable), so both get the label below.
if (-not $model -and $env:ANTHROPIC_MODEL) {
    $model = [string]$env:ANTHROPIC_MODEL
    $modelSource = 'the ANTHROPIC_MODEL env var'
}
if (-not $model) {
    $modelSource = 'settings.json'
    try {
        $model = (Get-Content (Join-Path $HOME '.claude\settings.json') -Raw | ConvertFrom-Json).model
    } catch {}
    if ($model -isnot [string]) { $model = $null }
}

$dir = Join-Path (Split-Path $PSScriptRoot -Parent) 'model-profiles'
if (-not $model -or -not (Test-Path $dir)) { exit 0 }

# Sort on the lowercased name, matching the sh port's LC_ALL=C glob over lowercase
# filenames. Plain `Sort-Object Name` is culture-aware and case-insensitive, so the two
# ports ordered profiles differently — and "first matching profile wins" then injects
# different doctrine per machine once two overlapping regexes exist.
foreach ($f in Get-ChildItem $dir -Filter '*.md' | Sort-Object { $_.Name.ToLowerInvariant() }) {
    $first = Get-Content $f.FullName -TotalCount 1 -Encoding UTF8
    if ($first -match '<!--\s*match:\s*(.+?)\s*-->') {
        $rx = $Matches[1]
        # -match is case-insensitive; the regex covers id and display-name aliases alike
        if ($model -match $rx) {
            if ($modelSource -ne 'payload') {
                "<!-- resolved from $modelSource `"$model`": the session payload carried no model. If the session banner names another family, apply model-profiles/$($f.BaseName).md instead and flag it -->"
            }
            [IO.File]::ReadAllText($f.FullName)
            exit 0
        }
    }
}

Write-Output "No conformance profile matches model '$model' - its doctrine has never been derived. Run the 'anthropic-conformance' skill to derive one; profiles at $dir"
exit 0
