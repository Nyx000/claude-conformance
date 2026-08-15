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
if (-not $model) {
    try {
        $model = (Get-Content (Join-Path $HOME '.claude\settings.json') -Raw | ConvertFrom-Json).model
    } catch {}
}

$dir = Join-Path (Split-Path $PSScriptRoot -Parent) 'model-profiles'
if (-not $model -or -not (Test-Path $dir)) { exit 0 }

foreach ($f in Get-ChildItem $dir -Filter '*.md' | Sort-Object Name) {
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
