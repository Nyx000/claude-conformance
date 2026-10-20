# SessionStart hook: nudge when the Anthropic conformance audit is stale.
# Four triggers, deliberately NOT equal in cost — the message names the scope so a
# cheap trigger doesn't read like an expensive one:
#   model change   -> full re-derivation (the doctrine block is entirely model-calibrated)
#   version change -> mechanics scan only (env vars, tool names, feature floors)
#   plugin change  -> override-expiry check (a version-gated override may be retirable)
#   90 days        -> periodic, catches silent doc revisions
# Prints nothing when current. Always exits 0 — a hook must never block a session start.

$ErrorActionPreference = 'Stop'

try {
    # Per-machine ledger: CONFORMANCE-<host>.md if present, else CONFORMANCE.md
    $ledger = Join-Path $HOME (".claude\CONFORMANCE-{0}.md" -f $env:COMPUTERNAME)
    if (-not (Test-Path $ledger)) { $ledger = Join-Path $HOME '.claude\CONFORMANCE.md' }
    if (-not (Test-Path $ledger)) { exit 0 }

    $text = Get-Content $ledger -Raw

    $auditedDate    = [regex]::Match($text, '(?m)^\-\s\*\*Last audited:\*\*\s*(\S+)').Groups[1].Value
    $auditedVersion = [regex]::Match($text, '(?m)^\-\s\*\*Claude Code:\*\*\s*([0-9][0-9.]*)').Groups[1].Value
    $auditedModel   = [regex]::Match($text, '(?m)^\-\s\*\*Model audited:\*\*\s*(.+?)\s*$').Groups[1].Value
    $auditedIds     = [regex]::Match($text, '(?m)^\-\s\*\*Model ids audited:\*\*\s*(.+?)\s*$').Groups[1].Value
    $auditedPlugins = [regex]::Match($text, '(?m)^\-\s\*\*Plugins audited:\*\*\s*(.+?)\s*$').Groups[1].Value

    $reasons = @()

    # Model drift — the expensive one
    try {
        # The session payload's full id first. settings.json holds an alias, and an alias can
        # change meaning under an unchanged file: on 2026-09-22 Claude Code 2.1.280 moved
        # `opus[1m]` from Opus 5 to Opus 5.5, and this check stayed quiet because the alias was
        # already in the audited list. The payload carried `claude-opus-5-5[1m]`.
        $model = $null
        if ([Console]::IsInputRedirected) {
            try { $model = ([Console]::In.ReadToEnd() | ConvertFrom-Json).model } catch { }
            if ($model -isnot [string]) { $model = $null }
        }
        $settings = Join-Path $HOME '.claude\settings.json'
        if (-not $model -and (Test-Path $settings)) {
            $model = (Get-Content $settings -Raw | ConvertFrom-Json).model
        }
        # The prose 'Model audited' line holds a display name ('Claude Opus 5'). Substring-matching
        # an id or alias against it nudges on every session after a /model switch that changed
        # nothing about the doctrine. Compare against the explicit id list instead; fall back to
        # the prose only on an old ledger.
        if ($model) {
            if ($auditedIds) {
                $ids = $auditedIds -split ',' | ForEach-Object { $_.Trim().Trim('`') }
                $known = $ids | Where-Object { $_ -and $_.ToLower() -eq $model.ToLower() }
                if (-not $known) {
                    $reasons += "MODEL now '$model' (not in audited ids: $auditedIds) - full re-derivation"
                }
            } elseif ($auditedModel -notmatch [regex]::Escape($model)) {
                $reasons += "MODEL now '$model' (ledger: '$auditedModel') - full re-derivation"
            }
        }
    } catch { }

    # Claude Code version drift — mechanics only
    try {
        $current = (& claude --version 2>$null) -replace '[^0-9.].*$', ''
        if ($current -and $auditedVersion -and $current.Trim() -ne $auditedVersion.Trim()) {
            $reasons += "Claude Code $($auditedVersion.Trim()) -> $($current.Trim()) - mechanics scan"
        }
    } catch { }

    # Plugin drift — ANY plugin, not a named list. A plugin installed after the last
    # audit can ship superseded instruction classes just as easily as an updated one.
    # Read from installed_plugins.json, not the cache dirs: an uninstall leaves its cache
    # dir behind, so the old directory scan reported removed plugins as installed (A69).
    try {
        $manifest = Join-Path $HOME '.claude\plugins\installed_plugins.json'
        if (Test-Path $manifest) {
            $was = @{}
            # Version token may be a git hash or the literal 'unknown', not just a semver
            foreach ($m in [regex]::Matches($auditedPlugins, '([A-Za-z0-9_.-]+)\s+([A-Za-z0-9][0-9A-Za-z.\-]*)')) {
                $was[$m.Groups[1].Value] = $m.Groups[2].Value
            }
            $changed = @(); $added = @()
            $installed = (Get-Content $manifest -Raw | ConvertFrom-Json).plugins
            foreach ($p in $installed.PSObject.Properties) {
                $name = ($p.Name -split '@')[0]
                $entry = @($p.Value)[0]
                # A plugin installed from a git ref may carry no semver: track its short sha
                $now = if ($entry.version -and $entry.version -ne 'unknown') { $entry.version }
                       elseif ($entry.gitCommitSha) { $entry.gitCommitSha.Substring(0, 12) }
                       else { 'unknown' }
                if (-not $was.ContainsKey($name)) { $added += "$name $now" }
                elseif ($was[$name] -ne $now)     { $changed += "$name $($was[$name]) -> $now" }
            }
            if ($changed.Count) { $reasons += "plugins changed: $($changed -join ', ') - re-scan for superseded classes" }
            if ($added.Count)   { $reasons += "plugins NEW since audit: $($added -join ', ') - never scanned" }
        }
    } catch { }

    # Age — weakest signal, catches silent doc revisions
    try {
        $d = [datetime]::ParseExact($auditedDate, 'yyyy-MM-dd', $null)
        $age = [int]((Get-Date) - $d).TotalDays
        if ($age -gt 90) { $reasons += "$age days since last audit - periodic" }
    } catch { }

    if ($reasons.Count -gt 0) {
        Write-Output ("Conformance audit stale: " + ($reasons -join '; ') + ". Run the 'anthropic-conformance' skill; ledger at ~/.claude/CONFORMANCE.md")
    }
} catch { }

exit 0
