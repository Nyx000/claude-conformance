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
    $ledger = Join-Path $HOME '.claude\CONFORMANCE.md'
    if (-not (Test-Path $ledger)) { exit 0 }

    $text = Get-Content $ledger -Raw

    $auditedDate    = [regex]::Match($text, '(?m)^\-\s\*\*Last audited:\*\*\s*(\S+)').Groups[1].Value
    $auditedVersion = [regex]::Match($text, '(?m)^\-\s\*\*Claude Code:\*\*\s*([0-9][0-9.]*)').Groups[1].Value
    $auditedModel   = [regex]::Match($text, '(?m)^\-\s\*\*Model audited:\*\*\s*(.+?)\s*$').Groups[1].Value
    $auditedPlugins = [regex]::Match($text, '(?m)^\-\s\*\*Plugins audited:\*\*\s*(.+?)\s*$').Groups[1].Value

    $reasons = @()

    # Model drift — the expensive one
    try {
        $settings = Join-Path $HOME '.claude\settings.json'
        if (Test-Path $settings) {
            $model = (Get-Content $settings -Raw | ConvertFrom-Json).model
            if ($model -and $auditedModel -notmatch [regex]::Escape($model)) {
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
    try {
        $cache = Join-Path $HOME '.claude\plugins\cache'
        if (Test-Path $cache) {
            $was = @{}
            foreach ($m in [regex]::Matches($auditedPlugins, '([A-Za-z0-9_.-]+)\s+([0-9][0-9A-Za-z.\-]*)')) {
                $was[$m.Groups[1].Value] = $m.Groups[2].Value
            }
            $changed = @(); $added = @()
            foreach ($pd in Get-ChildItem $cache -Directory -ErrorAction SilentlyContinue) {
                foreach ($plug in Get-ChildItem $pd.FullName -Directory -ErrorAction SilentlyContinue) {
                    # Version dirs only — plugin caches also hold git-hash directories
                    $now = (Get-ChildItem $plug.FullName -Directory -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -match '^\d+\.\d+' } |
                            Sort-Object { try { [version]($_.Name -replace '[^0-9.].*$','') } catch { [version]'0.0.0' } } |
                            Select-Object -Last 1).Name
                    if (-not $now) { continue }
                    if (-not $was.ContainsKey($plug.Name)) { $added += "$($plug.Name) $now" }
                    elseif ($was[$plug.Name] -ne $now)     { $changed += "$($plug.Name) $($was[$plug.Name]) -> $now" }
                }
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
