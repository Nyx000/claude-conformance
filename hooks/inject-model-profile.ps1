# SessionStart hook: inject the conformance doctrine for the model actually in use.
# Resolves the model (hook stdin JSON `model` field, else settings.json), then prints the
# first model-profiles/*.md whose first-line `<!-- match: <regex> -->` matches it.
# stdout reaches session context, so the printed profile IS the doctrine injection.
# No match -> a one-line "derive a profile" nudge, never a silently-applied wrong profile.
# Always exits 0 — a hook must never block a session start.
# Windows counterpart to inject-model-profile.sh.

$ErrorActionPreference = 'SilentlyContinue'

# Windows PowerShell 5.1 (the registered binary) reads files as ANSI and writes the OEM
# codepage by default; either direction turns the profile's em-dashes into mojibake in
# session context (seen live 2026-08-14). Force UTF-8 on both ends.
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$model = $null
try {
    $stdin = [Console]::In.ReadToEnd()
    if ($stdin) { $model = ($stdin | ConvertFrom-Json).model }
} catch {}
# The sh port extracts a STRING-valued "model" with sed. ConvertFrom-Json would happily
# hand back an object and stringify it later, so the two ports resolved different values
# for the same payload. Accept a string or nothing.
if ($model -isnot [string]) { $model = $null }
# A run-time override (`claude --model X`, or ANTHROPIC_MODEL) never touches
# settings.json. Resolving from settings alone injected the PINNED model's doctrine into
# an overridden session — the silently-applied wrong profile the header says cannot
# happen. Env sits ahead of settings for exactly that case.
if (-not $model -and $env:ANTHROPIC_MODEL) { $model = [string]$env:ANTHROPIC_MODEL }
if (-not $model) {
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
            [IO.File]::ReadAllText($f.FullName)
            exit 0
        }
    }
}

Write-Output "No conformance profile matches model '$model' - its doctrine has never been derived. Run the 'anthropic-conformance' skill to derive one; profiles at $dir"
exit 0
