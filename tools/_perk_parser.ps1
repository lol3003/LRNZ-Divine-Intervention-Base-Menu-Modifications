# =============================================================================
# _perk_parser.ps1 - SHARED dynasty-perk/track parser (dot-sourced by both generators)
# =============================================================================
# Dot-source this file, then call Get-Perks / Get-TrackDlcGates.
#
# Consumed by:
#   - generate_perk_editor.ps1  (vanilla + DLC; ships in the base mod)
#   - generate_mod_perks.ps1    (Phase 3 F1 scanner / sub-mod generator)
#
# Hardening per plan v9 F1 / F5:
#   - Get-Perks supports single-line perk blocks (`my_perk = { legacy = x }`), which
#     mod authors write; the old regex only matched `key = {` with the brace alone
#     on the line and silently dropped them.
#   - Get-Perks warns when a dynasty_perks/*.txt file parses to 0 perks (parse miss,
#     not necessarily an empty file).
#   - Extraction note (v10): moved verbatim out of generate_perk_editor.ps1 so one
#     parser fix fixes both tools.
# =============================================================================

# Parse common/dynasty_perks/*.txt: perk key -> its track.
# Returns an ordered hashtable keyed by perk key.
function Get-Perks {
    param([string[]]$Directories)
    $perks = [ordered]@{}
    foreach ($dir in $Directories) {
        if (-not (Test-Path $dir)) { Write-Warning "perk dir not found: $dir"; continue }
        foreach ($file in Get-ChildItem $dir -Filter '*.txt' | Sort-Object Name) {
            $lines = Get-Content $file.FullName
            $fileKeyCount = 0
            $currentKey = $null
            $depth = 0
            foreach ($line in $lines) {
                $trimmed = ($line -replace '#.*$', '').Trim()
                # --- block opener on its own line: `key = {` ---
                if ($trimmed -match '^(\w+)\s*=\s*\{\s*$') {
                    $currentKey = $Matches[1]
                    $depth = 1
                    continue
                }
                # --- single-line block opener + content: `key = { legacy = x }` ---
                if ($trimmed -match '^(\w+)\s*=\s*\{\s*(.*)\}$') {
                    $currentKey = $Matches[1]
                    $inner = $Matches[2]
                    if ($inner -match 'legacy\s*=\s*(\w+)') {
                        $perks[$currentKey] = $Matches[1]
                        $fileKeyCount++
                    }
                    $currentKey = $null
                    $depth = 0
                    continue
                }
                if ($null -ne $currentKey) {
                    $chars = $trimmed.ToCharArray() | Where-Object { $_ -eq '{' -or $_ -eq '}' }
                    foreach ($c in $chars) { if ($c -eq '{') { $depth++ } else { $depth-- } }
                    if ($depth -le 0) {
                        $currentKey = $null
                        $depth = 0
                        continue
                    }
                    if ($trimmed -match '^\s*legacy\s*=\s*(\w+)') {
                        if (-not $perks.Contains($currentKey)) {
                            $perks[$currentKey] = $Matches[1]
                            $fileKeyCount++
                        }
                    }
                }
            }
            if ($fileKeyCount -eq 0) {
                Write-Warning "No perks parsed from $($file.Name) (parse miss or empty)"
            }
        }
    }
    return $perks
}

# Parse common/dynasty_legacies/*.txt: track key -> DLC feature (or $null if ungated).
# Returns a hashtable track key -> DLC feature string.
function Get-TrackDlcGates {
    param([string[]]$Directories)
    $gates = @{}
    foreach ($dir in $Directories) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($file in Get-ChildItem $dir -Filter '*.txt' | Sort-Object Name) {
            $lines = Get-Content $file.FullName
            $currentKey = $null
            $depth = 0
            $inIsShown = $false
            foreach ($line in $lines) {
                $trimmed = ($line -replace '#.*$', '').TrimEnd()
                if ($trimmed -match '^(\w+)\s*=\s*\{\s*$' -and $depth -eq 0) {
                    $currentKey = $Matches[1]
                    $depth = 1
                    $inIsShown = $false
                    continue
                }
                if ($null -ne $currentKey) {
                    if ($trimmed -match '^\s*is_shown\s*=\s*\{') { $inIsShown = $true }
                    $chars = $trimmed.ToCharArray() | Where-Object { $_ -eq '{' -or $_ -eq '}' }
                    foreach ($c in $chars) { if ($c -eq '{') { $depth++ } else { $depth-- } }
                    if ($depth -le 0) {
                        $currentKey = $null
                        $depth = 0
                        $inIsShown = $false
                        continue
                    }
                    if ($inIsShown -and $trimmed -match 'has_dlc_feature\s*=\s*(\w+)') {
                        if (-not $gates.ContainsKey($currentKey)) {
                            $gates[$currentKey] = $Matches[1]
                        }
                    }
                }
            }
        }
    }
    return $gates
}

# Group a perk-key->track map into an ordered track -> List[perk-key] map,
# preserving first-seen order.
function Group-PerksByTrack {
    param($PerkMap)
    $tracks = [ordered]@{}
    if ($null -eq $PerkMap) { return $tracks }
    foreach ($k in $PerkMap.Keys) {
        $t = $PerkMap[$k]
        if (-not $tracks.Contains($t)) { $tracks[$t] = [System.Collections.Generic.List[string]]::new() }
        $tracks[$t].Add($k)
    }
    return $tracks
}