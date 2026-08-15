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
        $settings = Join-Path $HOME '.claude\settings.json'
        if (Test-Path $settings) {
            $model = (Get-Content $settings -Raw | ConvertFrom-Json).model
            # settings.json holds an ALIAS ('opus[1m]'), the prose 'Model audited' line holds a
            # display name ('Claude Opus 5'). Substring-matching one against the other nudges on
            # every session after a /model switch that changed nothing about the doctrine. Compare
            # against the explicit id list instead; fall back to the prose only on an old ledger.
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
            # Version token may be a git hash or the literal 'unknown', not just a semver
            foreach ($m in [regex]::Matches($auditedPlugins, '([A-Za-z0-9_.-]+)\s+([A-Za-z0-9][0-9A-Za-z.\-]*)')) {
                $was[$m.Groups[1].Value] = $m.Groups[2].Value
            }
            $changed = @(); $added = @()
            foreach ($pd in Get-ChildItem $cache -Directory -ErrorAction SilentlyContinue) {
                # temp_git_* is an in-flight clone, not an installed plugin
                if ($pd.Name -like 'temp_git_*') { continue }
                foreach ($plug in Get-ChildItem $pd.FullName -Directory -ErrorAction SilentlyContinue) {
                    # Prefer a version dir. A plugin installed from a git ref has ONLY a
                    # hash dir, and skipping those made live plugins invisible to drift
                    # detection entirely (context7, frontend-design — found 2026-08-15).
                    # Fall back to the newest hash dir and track the hash as the version.
                    $dirs = Get-ChildItem $plug.FullName -Directory -ErrorAction SilentlyContinue
                    $now = ($dirs | Where-Object { $_.Name -match '^\d+\.\d+' } |
                            Sort-Object { try { [version]($_.Name -replace '[^0-9.].*$','') } catch { [version]'0.0.0' } } |
                            Select-Object -Last 1).Name
                    if (-not $now) {
                        # Hash-shaped (or literally 'unknown') dirs only — a plugin checked out
                        # FLAT has ordinary subdirs (src, tests, skills) that would each read as
                        # a phantom plugin
                        $now = ($dirs | Where-Object { $_.Name -match '^([0-9a-f]{7,40}|unknown)$' } |
                                Sort-Object LastWriteTime | Select-Object -Last 1).Name
                    }
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
