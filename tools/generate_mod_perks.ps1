# =============================================================================
# DI Dynasty Perk Editor - Mod Support Generator (Phase 3)
# =============================================================================
# Discovers installed CK3 mods that add dynasty perks/tracks and generates
# editor support ("DI Perks" compatch) for them.
#
# Model (v15): CK3 GUI type registration is first-loaded-wins, so a compatch
# "extension" type can never replace the base mod's grid. -SubMod therefore
# emits a COMPLETE same-path override of gui/DI_generated_perk_grid.gui
# (compatch must load AFTER the base mod in the playset).
#   - Use -SubMod to generate a compatch for a single perk mod.
#   - Use -Playset (F4) to merge several perk mods from a playset into ONE
#     combined compatch. This is the recommended way to show several perk mods
#     together. Only one DI Perks compatch may be active in a modlist at once.
#   - Run with no args for the interactive menu (F2).
#
# Tools:
#   tools/generate_perk_editor.ps1  <-- vanilla+DLC generator (ships in base mod)
#   tools/generate_mod_perks.ps1    <-- THIS tool: perk-mod support generator
#   tools/_perk_parser.ps1          <-- shared parser (dot-sourced by both)
#
# Usage:
#   pwsh -File tools/generate_mod_perks.ps1 -Scan
#   pwsh -File tools/generate_mod_perks.ps1 -SubMod "Hiraeth"
#   pwsh -File tools/generate_mod_perks.ps1 -Playset "IronyModManager"
#   pwsh -File tools/generate_mod_perks.ps1 -Playset "IronyModManager" -TargetFolder "C:\temp\out"
#   pwsh -File tools/generate_mod_perks.ps1            (interactive menu)
#
# The shared parser (tools/_perk_parser.ps1) is dot-sourced so counts match the
# vanilla generator. Mods are enumerated from mods_registry.json (primary) + a
# directory scan. Playsets are read from the launcher's launcher-v2.sqlite via a
# temp copy (Python sqlite3), so the live DB is never locked.
# =============================================================================

param(
    [switch]$Scan,                      # F1: list installed perk mods (read-only)
    [string]$SubMod = "",               # F3: standalone compatch for one perk mod
    [string[]]$SubModExtraDirs = @(),   # F3: extra ordered perk-mod dirs to merge (engine load order; later wins)
    [string]$Playset,                   # F4: combined compatch from a playset's enabled mods
    [string]$PlaysetMods = "",      # F4: comma/semicolon-separated perk mod names to combine
    [string]$SubMods = "",          # F4: alias for $PlaysetMods (explicit list to combine)
    [string]$CombinedName = "",         # F4: name for the combined compatch (auto if empty)
    [string]$TargetFolder = "",         # emit files here (default: mod/DI Perks - <Name>)
    [string]$ModDir      = "$PSScriptRoot\..",  # base DI mod dir (descriptor name for dependency)
    [string]$ModsRegistry = "$env:USERPROFILE\OneDrive\Dokumente\Paradox Interactive\Crusader Kings III\mods_registry.json",
    [string]$UserFolder   = "$env:USERPROFILE\OneDrive\Dokumente\Paradox Interactive\Crusader Kings III",
    [string[]]$ExtraScanDirs = @(),     # extra dirs to scan for common/dynasty_perks
    [string]$GameDir = "H:\SteamLibrary\steamapps\common\Crusader Kings III\game",
    [string[]]$LocDirs = @("H:\SteamLibrary\steamapps\common\Crusader Kings III\game\localization\english"),
    [string]$Python = "python",
    [switch]$WhatIf,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

# --- Shared parser (dot-sourced) ------------------------------------------------
. (Join-Path $PSScriptRoot "_perk_parser.ps1")

# --- Shared vanilla-look grid writers (definitions only; used by -SubMod) --------
. (Join-Path $PSScriptRoot "_grid_templates.ps1")

# --- Candidate resolution --------------------------------------------------------
# Returns @{ Name; Path; Source; SteamId } for every folder that could hold a CK3 mod.
function Get-ModCandidates {
    $cands = [System.Collections.Generic.List[object]]::new()

    # Primary: the launcher's own registry.
    if ($ModsRegistry -and (Test-Path $ModsRegistry)) {
        try {
            $reg = Get-Content $ModsRegistry -Raw | ConvertFrom-Json
            foreach ($p in $reg.PSObject.Properties) {
                $v = $p.Value
                if (-not $v.dirPath) { continue }
                # Skip already-generated DI Perks compatch entries - they are not source
                # perk mods (they redefine di_perk_grid_extension, not real perks).
                if ($v.displayName -like 'DI Perks*' -or $v.dirPath -like '*DI Perks - *') { continue }
                $cands.Add([pscustomobject]@{
                    Name    = $v.displayName
                    Path    = $v.dirPath
                    Source  = if ($v.source) { $v.source } else { $p.Name }
                    SteamId = if ($v.steamId) { $v.steamId } else { $p.Name }
                })
            }
        } catch {
            Write-Warning "Could not read mods_registry.json ($ModsRegistry): $_"
        }
    } else {
        Write-Warning "mods_registry.json not found at $ModsRegistry"
    }

    # Secondary: local mod/ folder + extra scan dirs.
    $localDir = Join-Path $UserFolder "mod"
    if (Test-Path $localDir) {
        Get-ChildItem $localDir -Directory | ForEach-Object {
            # Skip already-generated DI Perks compatch output dirs - they are not source
            # perk mods (they redefine di_perk_grid_extension, not real perks).
            if ($_.Name -like "DI Perks*") { return }
            $cands.Add([pscustomobject]@{ Name = $_.Name; Path = $_.FullName; Source = "local"; SteamId = $null })
        }
    }
    foreach ($d in $ExtraScanDirs) {
        if (Test-Path $d) {
            $cands.Add([pscustomobject]@{ Name = $d; Path = $d; Source = "extra"; SteamId = $null })
        }
    }
    return ($cands | Sort-Object Path -Unique)
}

# --- F1: scan for installed perk mods ---------------------------------------------
function Invoke-DiScan {
    $cands = Get-ModCandidates
    $results = @()
    foreach ($c in $cands) {
        $perkDir = Join-Path $c.Path "common\dynasty_perks"
        if (-not (Test-Path $perkDir)) { continue }
        if ($Verbose) { Write-Host "Scanning $($c.Name) ..." }
        $perks = Get-Perks -Directories $perkDir
        $trackMap = Group-PerksByTrack $perks
        $legacyDir = Join-Path $c.Path "common\dynasty_legacies"
        $gates = @{}
        if (Test-Path $legacyDir) { $gates = Get-TrackDlcGates -Directories $legacyDir }
        $results += [pscustomobject]@{
            Name = $c.Name; Source = $c.Source; SteamId = $c.SteamId; Path = $c.Path
            PerkCount = $perks.Count; TrackCount = $trackMap.Count
            GatedTracks = ($gates.Values | Where-Object { $_ }).Count
        }
    }
    return $results
}
function Show-ScanTable {
    param($Results)
    if (-not $Results -or $Results.Count -eq 0) { Write-Host "No perk mods found."; return }
    Write-Host ""
    Write-Host ("{0,-5} {1,-6} {2,-46} {3}" -f "Perks", "Tracks", "Mod", "Path")
    Write-Host ("{0,-5} {1,-6} {2,-46} {3}" -f "-----", "------", "----", "----")
    foreach ($r in $Results) {
        $full  = $r.Path + "\common\dynasty_perks"
        $short = if ($full.Length -gt 55) { "..." + $full.Substring($full.Length - 55) } else { $full }
        Write-Host ("{0,-5} {1,-6} {2,-46} {3}" -f $r.PerkCount, $r.TrackCount, $r.Name, $short)
    }
    Write-Host ""
    Write-Host "$($Results.Count) perk mod(s) found."
}

# --- Vanilla perk-key set (for duplicate-key exclusion) ---------------------------
function Get-VanillaPerkSet {
    param([string]$GameDir)
    $perkDir = Join-Path $GameDir "common\dynasty_perks"
    return Get-Perks -Directories $perkDir
}

# --- Base DI mod display name -----------------------------------------------------
function Get-BaseDiName {
    $baseDesc = Join-Path $ModDir "descriptor.mod"
    $name = "Divine Intervention Cheat Menu Dynasty Legacy Perk Test"
    if (Test-Path $baseDesc) {
        $m = Select-String -Path $baseDesc -Pattern 'name="([^"]+)"' | Select-Object -First 1
        if ($m) { $name = $m.Matches[0].Groups[1].Value }
    }
    return $name
}

# --- Emit a descriptor + auto-register the launcher .mod ---------------------------
function Write-Descriptor {
    param([string]$OutDir, [string]$ModName, [string[]]$Depends, [string]$UserFolder, [bool]$WriteLauncher)
    $utf8Bom = [System.Text.UTF8Encoding]::new($true)
    $depsBlock = ($Depends | ForEach-Object { "`t`"$_`"" }) -join "`n"
    $desc = @"
version="0.1.0"
tags={
	"Utilities"
}
name="$ModName"
supported_version="1.19.*"
dependencies = {
$depsBlock
}
path="$($OutDir -replace '[\\/]','/')"
"@
    if (-not (Test-Path (Join-Path $OutDir "descriptor.mod"))) {
        [System.IO.File]::WriteAllText((Join-Path $OutDir "descriptor.mod"), $desc, $utf8Bom)
    }
    if ($WriteLauncher) {
        $launcherModDir = Join-Path $UserFolder "mod"
        if (-not (Test-Path $launcherModDir)) { New-Item -ItemType Directory -Force -Path $launcherModDir | Out-Null }
        [System.IO.File]::WriteAllText((Join-Path $launcherModDir "$ModName.mod"), $desc, $utf8Bom)
        Write-Host "Registered launcher mod: $($launcherModDir)\$ModName.mod"
    }
}

# --- Helper: snapshot of vanilla files NOT shadowed by same-name mod files --------
# CK3 file override rule: a mod file with the same relative name replaces the
# vanilla file entirely. Returns a temp dir holding the surviving vanilla files
# (caller removes it). Parsing order [modDir, snapshot] then gives first-seen-wins
# key precedence to the mod on top of the correct file-level replacement.
function Get-VanillaSurvivorSnapshot {
    param([string]$ModDir, [string]$VanillaDir, [string]$Tag)
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("di_merge_" + $Tag + "_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    if (Test-Path $VanillaDir) {
        $modNames = @{}
        Get-ChildItem $ModDir -Filter '*.txt' | ForEach-Object { $modNames[$_.Name] = $true }
        foreach ($vf in (Get-ChildItem $VanillaDir -Filter '*.txt')) {
            if (-not $modNames.ContainsKey($vf.Name)) {
                Copy-Item -LiteralPath $vf.FullName -Destination (Join-Path $tmp $vf.Name)
            }
        }
    }
    return $tmp
}

# --- F3: standalone compatch for ONE perk mod --------------------------------------
# v15: the grid is a COMPLETE same-path override of the base mod's
# gui/DI_generated_perk_grid.gui, computed from mod files + vanilla game files
# (mod same-name files replace vanilla files; new hth_*-style keys are added).
# Non-free mode requires dynasty_prestige >= <cost value> before granting.
function Write-SubModSguiBlocks {
    param($Sb, $PerkMap, $Tracks, [string]$CostRef)
    foreach ($k in $PerkMap.Keys) {
        [void]$Sb.AppendLine("DI_perk_add_$k = {")
        [void]$Sb.AppendLine("    scope = character")
        [void]$Sb.AppendLine("    is_shown = { var:DI_dynasty_selected_dynasty = { NOT = { has_dynasty_perk = $k } } }")
        [void]$Sb.AppendLine("    effect = { var:DI_dynasty_selected_dynasty = {")
        [void]$Sb.AppendLine("        if = {")
        [void]$Sb.AppendLine("            limit = { NOT = { has_dynasty_perk = $k } }")
        [void]$Sb.AppendLine("            if = {")
        [void]$Sb.AppendLine("                limit = { root = { has_variable = DI_legacy_editor_free_mode } }")
        [void]$Sb.AppendLine("                add_dynasty_prestige = $CostRef")
        [void]$Sb.AppendLine("                add_dynasty_perk = $k")
        [void]$Sb.AppendLine("            }")
        [void]$Sb.AppendLine("            else_if = {")
        [void]$Sb.AppendLine("                limit = { dynasty_prestige >= $CostRef }")
        [void]$Sb.AppendLine("                add_dynasty_perk = $k")
        [void]$Sb.AppendLine("            }")
        [void]$Sb.AppendLine("        }")
        [void]$Sb.AppendLine("    } }")
        [void]$Sb.AppendLine("}")
        [void]$Sb.AppendLine("")
        [void]$Sb.AppendLine("DI_perk_remove_$k = {")
        [void]$Sb.AppendLine("    scope = character")
        [void]$Sb.AppendLine("    is_shown = { var:DI_dynasty_selected_dynasty = { has_dynasty_perk = $k } }")
        [void]$Sb.AppendLine("    effect = { var:DI_dynasty_selected_dynasty = {")
        [void]$Sb.AppendLine("        if = { limit = { has_dynasty_perk = $k } remove_dynasty_perk = $k }")
        [void]$Sb.AppendLine("    } }")
        [void]$Sb.AppendLine("}")
        [void]$Sb.AppendLine("")
    }
    foreach ($t in $Tracks.Keys) {
        $trk = $Tracks[$t]
        [void]$Sb.AppendLine("DI_track_add_all_$t = {")
        [void]$Sb.AppendLine("    scope = character")
        [void]$Sb.AppendLine("    is_shown = { var:DI_dynasty_selected_dynasty = { NOT = { $($t)_perks >= $($trk.Count) } } }")
        [void]$Sb.AppendLine("    effect = { var:DI_dynasty_selected_dynasty = {")
        foreach ($k in $trk) {
            [void]$Sb.AppendLine("        if = {")
            [void]$Sb.AppendLine("            limit = { NOT = { has_dynasty_perk = $k } }")
            [void]$Sb.AppendLine("            if = {")
            [void]$Sb.AppendLine("                limit = { root = { has_variable = DI_legacy_editor_free_mode } }")
            [void]$Sb.AppendLine("                add_dynasty_prestige = $CostRef")
            [void]$Sb.AppendLine("                add_dynasty_perk = $k")
            [void]$Sb.AppendLine("            }")
            [void]$Sb.AppendLine("            else_if = {")
            [void]$Sb.AppendLine("                limit = { dynasty_prestige >= $CostRef }")
            [void]$Sb.AppendLine("                add_dynasty_perk = $k")
            [void]$Sb.AppendLine("            }")
            [void]$Sb.AppendLine("        }")
        }
        [void]$Sb.AppendLine("    } }")
        [void]$Sb.AppendLine("}")
        [void]$Sb.AppendLine("")
        [void]$Sb.AppendLine("DI_track_remove_all_$t = {")
        [void]$Sb.AppendLine("    scope = character")
        [void]$Sb.AppendLine("    is_shown = { var:DI_dynasty_selected_dynasty = { $($t)_perks > 0 } }")
        [void]$Sb.AppendLine("    effect = { var:DI_dynasty_selected_dynasty = {")
        foreach ($k in $trk) {
            [void]$Sb.AppendLine("        if = { limit = { has_dynasty_perk = $k } remove_dynasty_perk = $k }")
        }
        [void]$Sb.AppendLine("    } }")
        [void]$Sb.AppendLine("}")
        [void]$Sb.AppendLine("")
    }
}

function New-DiSubMod {
    param(
        [string]$PerkModPath,
        [string]$PerkModName,
        [string]$BaseDIName,
        [string]$GameDir,
        [string]$TargetFolder,
        [string]$UserFolder,
        [string[]]$LocDirs,
        [string[]]$ExtraPerkModDirs = @(),   # ordered submod paths; engine order, later wins
        [switch]$WhatIf
    )
    $perkDir = Join-Path $PerkModPath "common\dynasty_perks"
    if (-not (Test-Path $perkDir)) { throw "No common\dynasty_perks at $PerkModPath" }
    $utf8Bom = [System.Text.UTF8Encoding]::new($true)

    $dirName = if ($PerkModName) { $PerkModName } else { Split-Path $PerkModPath -Leaf }
    $prefix  = ($dirName -replace '[^A-Za-z0-9_]', '_').ToLowerInvariant()
    if ($prefix -match '^[0-9]') { $prefix = "_$prefix" }

    # --- merged perk model: mods in reverse engine order (first-seen parse wins,
    # so later-loaded mods win key collisions), then surviving vanilla files ---
    $vanillaPerkDir = Join-Path $GameDir "common\dynasty_perks"
    $allPerkDirs = @($perkDir) + $ExtraPerkModDirs
    $shadowNames = @{}
    foreach ($d in $allPerkDirs) { Get-ChildItem $d -Filter '*.txt' -ErrorAction SilentlyContinue | ForEach-Object { $shadowNames[$_.Name] = $true } }
    $tmpVanillaPerks = Get-VanillaSurvivorSnapshot -ModDir $allPerkDirs[0] -VanillaDir $vanillaPerkDir -Tag "perks_$prefix"
    # The survivor snapshot above only knows the first mod dir's shadows; remove
    # vanilla files shadowed by ANY mod dir so same-name replacements win.
    Get-ChildItem $tmpVanillaPerks -Filter '*.txt' | ForEach-Object {
        if ($shadowNames.ContainsKey($_.Name)) { Remove-Item -LiteralPath $_.FullName -Force }
    }
    $parseDirs = @()
    for ($i = $ExtraPerkModDirs.Count - 1; $i -ge 0; $i--) { $parseDirs += $ExtraPerkModDirs[$i] }
    $parseDirs += $perkDir
    $parseDirs += $tmpVanillaPerks
    try {
        $perks = Get-Perks -Directories $parseDirs
        $effectTexts = Get-PerkEffectTextKeys -Directories $parseDirs
        $perkModifiers = Get-PerkModifierBlocks -Directories $parseDirs
    } finally { Remove-Item -LiteralPath $tmpVanillaPerks -Recurse -Force -ErrorAction SilentlyContinue }
    if ($perks.Count -eq 0) { Write-Warning "No perks parsed from $perkDir or $vanillaPerkDir"; return }
    if (-not (Test-PerksModel $perks)) { throw "Parsed perk model is inconsistent - aborting before writing" }
    $tracks = Group-PerksByTrack $perks

    # --- DLC gates from the same merged sources' dynasty_legacies folders ---------
    $vanillaLegacyDir = Join-Path $GameDir "common\dynasty_legacies"
    $legacyDirs = @()
    foreach ($d in $allPerkDirs) {
        $ld = Join-Path $d "common\dynasty_legacies"
        if (Test-Path $ld) { $legacyDirs += $ld }
    }
    if (Test-Path $vanillaLegacyDir) { $legacyDirs += $vanillaLegacyDir }
    $trackGates = if ($legacyDirs.Count -gt 0) { Get-TrackDlcGates -Directories $legacyDirs } else { @{} }

    $vanilla = Get-VanillaPerkSet $GameDir
    $newCount = 0
    foreach ($k in $perks.Keys) { if (-not $vanilla.Contains($k)) { $newCount++ } }
    Write-Host "Merged grid: $($perks.Count) perks / $($tracks.Count) tracks (mod adds $newCount new keys; same-name mod files replace vanilla files)."

    $costRef = "DI_dynasty_perk_cost_next_$prefix"

    # -- effect_localization + loc values for static tooltip text --
    $effLocDirs = @((Join-Path $GameDir "common\effect_localization"))
    if (Test-Path (Join-Path $PerkModPath "common\effect_localization")) { $effLocDirs += (Join-Path $PerkModPath "common\effect_localization") }
    $effectLocMap = Get-EffectLocalization -Directories $effLocDirs
    $locMap = Get-LocValues -Directories $LocDirs
    # Fallback: some mods ship loc outside localization\english (e.g. AGOT nests it
    # in english\agot\, Hiraeth in localization\ directly). If a mod-added perk's
    # name key is unresolvable, append that mod's localization tree - all extra
    # dirs collected first, then ONE rebuild over vanilla + extras so "later wins"
    # applies and the vanilla map is never discarded.
    $langPattern = '(simp_chinese|french|german|spanish|russian|polish|braz_por|japanese|korean|chinese|turkish)'
    $extraLocDirs = @()
    foreach ($d in $allPerkDirs) {
        $missing = $false
        foreach ($k in $perks.Keys) { if (-not $vanilla.Contains($k) -and [string]::IsNullOrEmpty($locMap["$($k)_name"])) { $missing = $true; break } }
        if (-not $missing) { continue }
        # $d is a perk dir (<modroot>\common\dynasty_perks); the mod's localization
        # tree hangs off the mod root (Hiraeth: localization\ directly, AGOT:
        # localization\english\agot\). Try the derived root, then $d itself in case
        # a caller passed a mod root directly.
        foreach ($cand in @((Split-Path (Split-Path $d -Parent) -Parent), $d)) {
            $root = Join-Path $cand "localization"
            if (-not (Test-Path $root)) { continue }
            foreach ($y in (Get-ChildItem $root -Filter '*.yml' -Recurse)) {
                if ($y.FullName -notmatch $langPattern) { $extraLocDirs += $y.DirectoryName }
            }
            break
        }
    }
    if ($extraLocDirs.Count -gt 0) {
        $locMap = Get-LocValues -Directories ($LocDirs + ($extraLocDirs | Sort-Object -Unique))
    }

    # -- modifier definitions (value-formatting metadata); vanilla first, then any
    # perk mod's own modifier_definition_formats (mod definitions win) --
    $modDefDirs = @((Join-Path $GameDir "common\modifier_definition_formats"))
    foreach ($d in $allPerkDirs) {
        foreach ($cand in @((Split-Path (Split-Path $d -Parent) -Parent), $d)) {
            $md = Join-Path $cand "common\modifier_definition_formats"
            if (Test-Path $md) { $modDefDirs += $md; break }
        }
    }
    $modifierDefs = Get-ModifierDefinitions -Directories $modDefDirs

    # -- scripted guis --
    $sgui = [System.Text.StringBuilder]::new()
    [void]$sgui.AppendLine("# GENERATED FILE - do not hand-edit. generate_mod_perks.ps1 -SubMod")
    [void]$sgui.AppendLine("# Cost refunds use $costRef (vanilla + this sub-mod's tracks).")
    [void]$sgui.AppendLine("")
    Write-SubModSguiBlocks -Sb $sgui -PerkMap $perks -Tracks $tracks -CostRef $costRef

    # -- grid: COMPLETE same-path override of the base mod's generated grid --
    # CK3 GUI type registration is first-loaded-wins; a second di_perk_grid_extension
    # definition is silently rejected, so the extension-slot approach can never render.
    # This compatch therefore ships the ENTIRE grid (vanilla + mod perks) at the base
    # mod's exact path and must load AFTER the base mod in the playset.
    $gui = [System.Text.StringBuilder]::new()
    [void]$gui.AppendLine("### GENERATED FILE - do not hand-edit. generate_mod_perks.ps1 -SubMod")
    [void]$gui.AppendLine("### Same-path full-file override of the base mod's gui/DI_generated_perk_grid.gui.")
    [void]$gui.AppendLine("### This compatch must be loaded AFTER the base mod in the playset.")
    [void]$gui.AppendLine("### Owned state IS rendered via the remove SGUI's IsShown binding (gold border +")
    [void]$gui.AppendLine("### checkmark; fully-owned tracks tint gold). Buttons stay enabled for left-add /")
    [void]$gui.AppendLine("### right-remove; the SGUI is_shown guards make wrong-direction clicks no-ops.")
    [void]$gui.AppendLine("")
    [void]$gui.AppendLine("types DI_DynastyGeneratedPerks {")
    [void]$gui.AppendLine("    type di_generated_perk_grid = vbox {")
    [void]$gui.AppendLine("        layoutpolicy_horizontal = expanding")
    [void]$gui.AppendLine("        spacing = 5")
    [void]$gui.AppendLine("")
    foreach ($t in $tracks.Keys) {
        $gate = $null
        if ($trackGates.ContainsKey($t)) { $gate = $trackGates[$t] }
        Write-VanillaTrackSection $gui $t $tracks[$t] $gate
    }
    [void]$gui.AppendLine("    }")
    [void]$gui.AppendLine("    type di_perk_grid_extension = vbox {")
    [void]$gui.AppendLine("        layoutpolicy_horizontal = expanding")
    [void]$gui.AppendLine("    }")
    [void]$gui.AppendLine("}")

    # -- tooltip loc: STATIC resolved text (same format as the base generator).
    # CRITICAL: emit ONLY mod-added perk keys - vanilla keys are already covered by
    # the base mod's DI_generated_perk_tooltips_l_english.yml, and duplicate
    # definitions break loc resolution engine-side (pdx_localize errors).
    $ttLoc = [System.Text.StringBuilder]::new()
    [void]$ttLoc.AppendLine("# =============================================================================")
    [void]$ttLoc.AppendLine("# GENERATED FILE - do not hand-edit. generate_mod_perks.ps1 -SubMod")
    [void]$ttLoc.AppendLine("# Grid button tooltips: perk name (bold) + effect description lines.")
    [void]$ttLoc.AppendLine("# =============================================================================")
    [void]$ttLoc.AppendLine("")
    [void]$ttLoc.AppendLine("l_english:")
    $modCount = 0
    foreach ($k in $perks.Keys) {
        if ($vanilla.Contains($k)) { continue }
        $name = $locMap["$($k)_name"]
        if ([string]::IsNullOrEmpty($name)) { $name = "$($k)_name" }
        $parts = "#bold $name#!"
        if ($effectTexts.ContainsKey($k)) {
            foreach ($e in $effectTexts[$k]) {
                $locKey = if ($effectLocMap.ContainsKey($e)) { $effectLocMap[$e] } else { $e }
                $eff = $locMap[$locKey]
                if ([string]::IsNullOrEmpty($eff)) { $eff = $e }
                $parts += "\n$eff"
            }
        }
        if ($perkModifiers.ContainsKey($k)) {
            foreach ($mline in (ConvertTo-PerkModifierTooltipLines -ModifierBlocks $perkModifiers[$k] -ModifierDefs $modifierDefs -LocMap $locMap -PerkKey $k -PerkNameText $name)) {
                $parts += "\n$mline"
            }
        }
        $escaped = $parts -replace '"', '\"'
        [void]$ttLoc.AppendLine(" DI_perk_tt_${k}:0 `"$escaped`"")
        $modCount++
    }
    Write-Host "Tooltip loc: $modCount mod-added entries (vanilla keys resolve from the base mod's loc file)."

    # -- script value: per-prefix cost over ALL merged tracks --
    $values = [System.Text.StringBuilder]::new()
    [void]$values.AppendLine("$costRef = {")
    [void]$values.AppendLine("    value = 250   # PERK_COST_BASE")
    foreach ($t in $tracks.Keys) { for ($i=1;$i -le $tracks[$t].Count;$i++){ [void]$values.AppendLine("    if = { limit = { $($t)_perks >= $i } add = 500 }") } }
    [void]$values.AppendLine("}")

    # -- output --
    $outDir = $TargetFolder
    if (-not $outDir) { $outDir = Join-Path $UserFolder "mod\DI Perks - $dirName" }
    if ($WhatIf) { Write-Host "[WhatIf] Would generate sub-mod override grid (prefix=$prefix, $($perks.Count) perks / $($tracks.Count) tracks) -> $outDir"; return }
    New-Item -ItemType Directory -Force -Path (Join-Path $outDir "common\scripted_guis") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $outDir "common\script_values") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $outDir "gui") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $outDir "localization\english") | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $outDir "common\scripted_guis\DI_generated_submod_${prefix}_toggles_sgui.txt"), $sgui.ToString(), $utf8Bom)
    [System.IO.File]::WriteAllText((Join-Path $outDir "common\script_values\DI_generated_submod_${prefix}_values.txt"), $values.ToString(), $utf8Bom)
    [System.IO.File]::WriteAllText((Join-Path $outDir "gui\DI_generated_perk_grid.gui"), $gui.ToString(), $utf8Bom)
    [System.IO.File]::WriteAllText((Join-Path $outDir "localization\english\DI_generated_perk_tt_l_english.yml"), $ttLoc.ToString(), $utf8Bom)
    # remove the pre-v15 extension-slot grid if a previous run created it
    $staleGrid = Join-Path $outDir "gui\DI_generated_submod_${prefix}_grid.gui"
    if (Test-Path $staleGrid) { Remove-Item -LiteralPath $staleGrid -Force; Write-Host "Removed stale extension-slot grid: $staleGrid" }
    $deps = @($dirName)
    foreach ($d in $ExtraPerkModDirs) {
        $desc = Join-Path $d "descriptor.mod"
        $nm = $null
        if (Test-Path $desc) { $m = Select-String -Path $desc -Pattern 'name="([^"]+)"' | Select-Object -First 1; if ($m) { $nm = $m.Matches[0].Groups[1].Value } }
        if (-not $nm) { $nm = Split-Path $d -Leaf }
        $deps += $nm
    }
    $deps += $BaseDIName
    Write-Descriptor -OutDir $outDir -ModName "DI Perks - $dirName" -Depends $deps -UserFolder $UserFolder -WriteLauncher $true
    Write-Host "Wrote sub-mod to $outDir"
}

# --- F4: combined compatch for a set of perk mods --------------------------------
function New-DiCombinedMod {
    param(
        [object[]]$PerkMods,          # @{Path; Name}
        [string]$CombinedName,
        [string]$BaseDIName,
        [string]$GameDir,
        [string]$TargetFolder,
        [string]$UserFolder,
        [string[]]$LocDirs,
        [switch]$WhatIf
    )
    if (-not $PerkMods -or $PerkMods.Count -eq 0) { throw "No perk mods supplied to combined generation." }
    $utf8Bom = [System.Text.UTF8Encoding]::new($true)
    $vanilla = Get-VanillaPerkSet $GameDir

    # Merge NEW keys across all mods, dedup by perk key; collect manifest data.
    $newPerks = [ordered]@{}
    $trackGates = @{}
    $manifestRows = @()
    foreach ($m in $PerkMods) {
        $perkDir = Join-Path $m.Path "common\dynasty_perks"
        if (-not (Test-Path $perkDir)) { Write-Warning "Skipping $($m.Name) - no perks dir"; continue }
        $perks = Get-Perks -Directories $perkDir
        $added = 0
        foreach ($k in $perks.Keys) {
            if (-not $vanilla.Contains($k) -and -not $newPerks.Contains($k)) { $newPerks[$k] = $perks[$k]; $added++ }
        }
        $legacyDir = Join-Path $m.Path "common\dynasty_legacies"
        if (Test-Path $legacyDir) {
            foreach ($g in (Get-TrackDlcGates -Directories $legacyDir).GetEnumerator()) {
                if (-not $trackGates.ContainsKey($g.Key)) { $trackGates[$g.Key] = $g.Value }
            }
        }
        $manifestRows += [pscustomobject]@{ Name = $m.Name; NewCount = $added }
    }
    if ($newPerks.Count -eq 0) { Write-Warning "No new (non-vanilla) keys across selected mods - nothing to generate."; return }
    $newTracks = Group-PerksByTrack $newPerks

    $modName = $CombinedName
    if (-not $modName) { $modName = "DI Perks - Combined" }
    $prefix = ($modName -replace '[^A-Za-z0-9_]', '_').ToLowerInvariant()
    if ($prefix -match '^[0-9]') { $prefix = "_$prefix" }
    $costRef = "DI_dynasty_perk_cost_next_$prefix"
    Write-Host "Combined: $($newPerks.Count) new perks / $($newTracks.Count) tracks from $($PerkMods.Count) mod(s)."

    # -- scripted guis --
    $sgui = [System.Text.StringBuilder]::new()
    [void]$sgui.AppendLine("# GENERATED FILE - do not hand-edit. generate_mod_perks.ps1 -Playset / combined")
    [void]$sgui.AppendLine("# Cost refunds use $costRef (vanilla + all merged tracks).")
    [void]$sgui.AppendLine("")
    foreach ($k in $newPerks.Keys) {
        [void]$sgui.AppendLine("DI_perk_add_$k = {")
        [void]$sgui.AppendLine("    scope = character")
        [void]$sgui.AppendLine("    is_shown = { var:DI_dynasty_selected_dynasty = { NOT = { has_dynasty_perk = $k } } }")
        [void]$sgui.AppendLine("    effect = { var:DI_dynasty_selected_dynasty = {")
        [void]$sgui.AppendLine("        if = { limit = { NOT = { has_dynasty_perk = $k } }")
        [void]$sgui.AppendLine("                if = { limit = { root = { has_variable = DI_legacy_editor_free_mode } } add_dynasty_prestige = $costRef }")
        [void]$sgui.AppendLine("                add_dynasty_perk = $k }")
        [void]$sgui.AppendLine("    } }")
        [void]$sgui.AppendLine("}")
        [void]$sgui.AppendLine("")
        [void]$sgui.AppendLine("DI_perk_remove_$k = {")
        [void]$sgui.AppendLine("    scope = character")
        [void]$sgui.AppendLine("    is_shown = { var:DI_dynasty_selected_dynasty = { has_dynasty_perk = $k } }")
        [void]$sgui.AppendLine("    effect = { var:DI_dynasty_selected_dynasty = {")
        [void]$sgui.AppendLine("        if = { limit = { has_dynasty_perk = $k } remove_dynasty_perk = $k }")
        [void]$sgui.AppendLine("    } }")
        [void]$sgui.AppendLine("}")
        [void]$sgui.AppendLine("")
    }
    foreach ($t in $newTracks.Keys) {
        $trk = $newTracks[$t]
        [void]$sgui.AppendLine("DI_track_add_all_$t = {")
        [void]$sgui.AppendLine("    scope = character")
        [void]$sgui.AppendLine("    is_shown = { var:DI_dynasty_selected_dynasty = { NOT = { $($t)_perks >= $($trk.Count) } } }")
        [void]$sgui.AppendLine("    effect = { var:DI_dynasty_selected_dynasty = {")
        foreach ($k in $trk) {
            [void]$sgui.AppendLine("        if = { limit = { NOT = { has_dynasty_perk = $k } }")
            [void]$sgui.AppendLine("                if = { limit = { root = { has_variable = DI_legacy_editor_free_mode } } add_dynasty_prestige = $costRef }")
            [void]$sgui.AppendLine("                add_dynasty_perk = $k }")
        }
        [void]$sgui.AppendLine("    } }")
        [void]$sgui.AppendLine("}")
        [void]$sgui.AppendLine("")
        [void]$sgui.AppendLine("DI_track_remove_all_$t = {")
        [void]$sgui.AppendLine("    scope = character")
        [void]$sgui.AppendLine("    is_shown = { var:DI_dynasty_selected_dynasty = { $($t)_perks > 0 } }")
        [void]$sgui.AppendLine("    effect = { var:DI_dynasty_selected_dynasty = {")
        foreach ($k in $trk) {
            [void]$sgui.AppendLine("        if = { limit = { has_dynasty_perk = $k } remove_dynasty_perk = $k }")
        }
        [void]$sgui.AppendLine("    } }")
        [void]$sgui.AppendLine("}")
        [void]$sgui.AppendLine("")
    }

    # -- grid: single di_perk_grid_extension merging all rows --
    $gui = [System.Text.StringBuilder]::new()
    [void]$gui.AppendLine("### GENERATED FILE - do not hand-edit. generate_mod_perks.ps1 -Playset / combined")
    [void]$gui.AppendLine("types DI_DynastyGeneratedCombined$prefix {")
    [void]$gui.AppendLine("    type di_perk_grid_extension = vbox {")
    [void]$gui.AppendLine("        layoutpolicy_horizontal = expanding")
    [void]$gui.AppendLine("        spacing = 5")
    foreach ($t in $newTracks.Keys) {
        $perkList = $newTracks[$t]
        $gate = $null
        if ($trackGates.ContainsKey($t)) { $gate = $trackGates[$t] }
        [void]$gui.AppendLine("        # ---- $t ($($perkList.Count) perks)$(if ($gate) { " [DLC: $gate]" }) ----")
        [void]$gui.AppendLine("        vbox = {")
        if ($gate) { [void]$gui.AppendLine("            visible = ""[HasDlcFeature( '$gate' )]""") }
        [void]$gui.AppendLine("            layoutpolicy_horizontal = expanding")
        [void]$gui.AppendLine("            margin = { 5 5 }")
        [void]$gui.AppendLine("            hbox = {")
        [void]$gui.AppendLine("                layoutpolicy_horizontal = expanding")
        [void]$gui.AppendLine("                spacing = 8")
        [void]$gui.AppendLine("                icon = {")
        [void]$gui.AppendLine("                    texture = ""gfx/interface/icons/dynasty/$t.dds""")
        [void]$gui.AppendLine("                    size = { 24 24 }")
        [void]$gui.AppendLine("                }")
        [void]$gui.AppendLine("                text_single = {")
        [void]$gui.AppendLine("                    layoutpolicy_horizontal = expanding")
        [void]$gui.AppendLine('                    text = "[Localize('''+ $t + '_name'')]"')
        [void]$gui.AppendLine('                    tooltip = "[Localize('''+ $t + '_desc'')]"')
        [void]$gui.AppendLine('                    default_format = ""#high""')
        [void]$gui.AppendLine("                }")
        [void]$gui.AppendLine("                button_standard = {")
        [void]$gui.AppendLine("                    size = { 130 26 }")
        [void]$gui.AppendLine("                    text = DI_DYNASTY_EDITOR_TRACK_BUTTON")
        [void]$gui.AppendLine("                    onclick = ""[GetScriptedGui('DI_track_add_all_$t').Execute(GuiScope.SetRoot(GetPlayer.MakeScope).End)]""")
        [void]$gui.AppendLine("                    onrightclick = ""[GetScriptedGui('DI_track_remove_all_$t').Execute(GuiScope.SetRoot(GetPlayer.MakeScope).End)]""")
        [void]$gui.AppendLine("                    tooltip = DI_DYNASTY_EDITOR_TRACK_BUTTON_TT")
        [void]$gui.AppendLine("                }")
        [void]$gui.AppendLine("            }")
        [void]$gui.AppendLine("            flowcontainer = {")
        [void]$gui.AppendLine("                layoutpolicy_horizontal = expanding")
        [void]$gui.AppendLine("                spacing = 5")
        foreach ($k in $perkList) {
            [void]$gui.AppendLine("                button_standard = {")
            [void]$gui.AppendLine("                    size = { 260 44 }")
            [void]$gui.AppendLine("                    button_ignore = none")
            [void]$gui.AppendLine("                    onclick = ""[GetScriptedGui('DI_perk_add_$k').Execute(GuiScope.SetRoot(GetPlayer.MakeScope).End)]""")
            [void]$gui.AppendLine("                    onrightclick = ""[GetScriptedGui('DI_perk_remove_$k').Execute(GuiScope.SetRoot(GetPlayer.MakeScope).End)]""")
            [void]$gui.AppendLine('                    tooltip = "[Localize('''+ $k + '_name'')]"')
            [void]$gui.AppendLine("                    hbox = {")
            [void]$gui.AppendLine("                        margin = { 5 0 }")
            [void]$gui.AppendLine("                        spacing = 8")
            [void]$gui.AppendLine("                        icon = {")
            [void]$gui.AppendLine("                            size = { 34 34 }")
            [void]$gui.AppendLine("                            texture = ""gfx/interface/icons/dynasty/$t.dds""")
            [void]$gui.AppendLine("                        }")
            [void]$gui.AppendLine("                        text_single = {")
            [void]$gui.AppendLine("                            layoutpolicy_horizontal = expanding")
            [void]$gui.AppendLine('                            text = "[Localize(''' + $k + '_name'')]"')
            [void]$gui.AppendLine('                            default_format = ""#clickable""')
            [void]$gui.AppendLine("                        }")
            [void]$gui.AppendLine("                    }")
            [void]$gui.AppendLine("                }")
        }
        [void]$gui.AppendLine("            }")
        [void]$gui.AppendLine("        }")
    }
    [void]$gui.AppendLine("    }")
    [void]$gui.AppendLine("}")

    # -- script value: combined cost (vanilla + all tracks) --
    $values = [System.Text.StringBuilder]::new()
    [void]$values.AppendLine("$costRef = {")
    [void]$values.AppendLine("    value = 250   # PERK_COST_BASE")
    $vanTracks = Group-PerksByTrack $vanilla
    foreach ($t in $vanTracks.Keys) { for ($i=1;$i -le $vanTracks[$t].Count;$i++){ [void]$values.AppendLine("    if = { limit = { $($t)_perks >= $i } add = 500 }") } }
    foreach ($t in $newTracks.Keys) { for ($i=1;$i -le $newTracks[$t].Count;$i++){ [void]$values.AppendLine("    if = { limit = { $($t)_perks >= $i } add = 500 }") } }
    [void]$values.AppendLine("}")

    # -- manifest --
    $manifest = [System.Text.StringBuilder]::new()
    [void]$manifest.AppendLine("DI Perks combined compatch: $modName")
    [void]$manifest.AppendLine("Generated with tools/generate_mod_perks.ps1 -Playset or combined")
    [void]$manifest.AppendLine("This compatch adds editor toggles for the following perk mods:")
    [void]$manifest.AppendLine("")
    foreach ($r in $manifestRows) { [void]$manifest.AppendLine(("- {0}  ({1} new perks)" -f $r.Name, $r.NewCount)) }

    # -- output --
    $outDir = $TargetFolder
    if (-not $outDir) { $outDir = Join-Path $UserFolder "mod\$modName" }
    if ($WhatIf) { Write-Host "[WhatIf] Would generate combined (prefix=$prefix, $($newPerks.Count) perks / $($newTracks.Count) tracks) -> $outDir"; return }
    New-Item -ItemType Directory -Force -Path (Join-Path $outDir "common\scripted_guis") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $outDir "common\script_values") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $outDir "gui") | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $outDir "common\scripted_guis\DI_generated_combined_${prefix}_toggles_sgui.txt"), $sgui.ToString(), $utf8Bom)
    [System.IO.File]::WriteAllText((Join-Path $outDir "common\script_values\DI_generated_combined_${prefix}_values.txt"), $values.ToString(), $utf8Bom)
    [System.IO.File]::WriteAllText((Join-Path $outDir "gui\DI_generated_combined_${prefix}_grid.gui"), $gui.ToString(), $utf8Bom)
    [System.IO.File]::WriteAllText((Join-Path $outDir "README_DI_perks.txt"), $manifest.ToString(), $utf8Bom)
    $deps = @()
    foreach ($m in $PerkMods) { $deps += $m.Name }
    $deps += $BaseDIName
    Write-Descriptor -OutDir $outDir -ModName $modName -Depends $deps -UserFolder $UserFolder -WriteLauncher $true
    Write-Host "Wrote combined compatch to $outDir"
}

# --- F2: interactive menu ---------------------------------------------------------
function Invoke-DiMenu {
    Write-Host "===================================================="
    Write-Host " DI Dynasty Perk Editor - Mod Support Generator"
    Write-Host "===================================================="
    $results = Invoke-DiScan
    Show-ScanTable $results
    Write-Host ""
    if ($results.Count -eq 0) { Write-Host "No perk mods found - nothing to do."; return }
    $baseName = Get-BaseDiName
    Write-Host "Choose an action:"
    Write-Host "  1) Generate ONE combined compatch from ALL listed perk mods"
    Write-Host "  2) Generate a standalone compatch for a single perk mod"
    Write-Host "  3) Generate from a Playset (recommended for a modlist)"
    Write-Host "  q) quit"
    $choice = Read-Host "> "
    switch ($choice) {
        "1" {
            $mods = $results | ForEach { [pscustomobject]@{ Path = $_.Path; Name = $_.Name } }
            $name = Read-Host "Combined mod name [DI Perks - Combined]: "
            if (-not $name) { $name = "DI Perks - Combined" }
            New-DiCombinedMod -PerkMods $mods -CombinedName $name -BaseDIName $baseName -GameDir $GameDir -UserFolder $UserFolder -LocDirs $LocDirs -WhatIf:$WhatIf
        }
        "2" {
            Write-Host "Numbered list (or -SubMod <name> at the CLI works too):"
            for ($i=0; $i -lt $results.Count; $i++) { Write-Host ("  {0}) {1}  [{2}]" -f ($i+1), $results[$i].Name, $results[$i].Path) }
            $sel = Read-Host "> "
            $idx = [int]$sel - 1
            if ($idx -ge 0 -and $idx -lt $results.Count) {
                $s = $results[$idx]
                New-DiSubMod -PerkModPath $s.Path -PerkModName $s.Name -BaseDIName $baseName -GameDir $GameDir -UserFolder $UserFolder -LocDirs $LocDirs -WhatIf:$WhatIf
            } else { Write-Host "Bad choice." }
        }
        "3" {
            $name = Read-Host "Playset name (use -Playset <name> at CLI too): "
            if (-not $name) { $name = "IronyModManager" }
            $mods = Get-PlaysetMods -UserFolder $UserFolder -PlaysetName $name
            $pl = @($mods | ForEach { if ($_.Path -and (Test-Path (Join-Path $_.Path "common\dynasty_perks"))) { [pscustomobject]@{ Path = $_.Path; Name = $_.Name } } })
            if ($pl.Count -eq 0) { Write-Host "No perk mods in that playset."; return }
            New-DiCombinedMod -PerkMods $pl -CombinedName "DI Perks - $name" -BaseDIName $baseName -GameDir $GameDir -UserFolder $UserFolder -LocDirs $LocDirs -WhatIf:$WhatIf
        }
        default { Write-Host "Bye." }
    }
}

# --- Playset resolution ------------------------------------------------------------
function Get-PlaysetMods {
    param([string]$UserFolder, [string]$PlaysetName)
    $db = Join-Path $UserFolder "launcher-v2.sqlite"
    if (-not (Test-Path -LiteralPath $db)) { throw "launcher-v2.sqlite not found at $db" }
    $tmp = Join-Path $env:TEMP ("lv_copy_{0}.sqlite" -f ([guid]::NewGuid().ToString('N')))
    Copy-Item -LiteralPath $db -Destination $tmp -Force
    $py = "$env:TEMP\di_lv_read.py"
    @" 
import sqlite3, sys
db=sys.argv[1]; name=sys.argv[2]
c=sqlite3.connect(db); cur=c.cursor()
cur.execute("SELECT m.id, m.displayName, m.dirPath, m.source FROM playsets p JOIN playsets_mods pm ON pm.playsetId=p.id JOIN mods m ON m.id=pm.modId WHERE p.name=? AND p.isRemoved=0 AND pm.enabled=1 ORDER BY pm.position", (name,))
for r in cur.fetchall():
    print("|".join(str(x) if x is not None else "" for x in r))
"@ | Set-Content -LiteralPath $py -Encoding UTF8
    try {
        $out = python $py $tmp $PlaysetName 2>$null
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    $mods = @()
    foreach ($line in $out) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line.Split('|')
        if ($parts.Length -ge 2) { $mods += [pscustomobject]@{ Id=$parts[0]; Name=$parts[1]; Path=if($parts.Length -gt 2){$parts[2]}else{""}; Source=if($parts.Length -gt 3){$parts[3]}else{""} } }
    }
    return $mods
}

# --- Main ------------------------------------------------------------------------
$baseDIName = Get-BaseDiName
if ($Scan) {
    Show-ScanTable (Invoke-DiScan | Sort-Object PerkCount -Descending)
}
if ($Playset) {
    $pm = Get-PlaysetMods -UserFolder $UserFolder -PlaysetName $Playset
    $select = @($pm | ForEach { if ($_.Path -and (Test-Path (Join-Path $_.Path "common\dynasty_perks"))) { [pscustomobject]@{ Path=$_.Path; Name=$_.Name } } })
    $cn = $CombinedName;     if (-not $cn) { $cn = "DI Perks - $Playset" }
    New-DiCombinedMod -PerkMods $select -CombinedName $cn -BaseDIName $baseDIName -GameDir $GameDir -TargetFolder $TargetFolder -UserFolder $UserFolder -LocDirs $LocDirs -WhatIf:$WhatIf
}
elseif ($PlaysetMods -or $SubMods) {
    # Explicit list of perk mod names to combine, comma/semicolon separated.
    $listStr = if ($PlaysetMods) { $PlaysetMods } else { $SubMods }
    $names = @($listStr -split '[;,]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $cands = Get-ModCandidates
    $select = @()
    foreach ($n in $names) {
        $match = @($cands | Where { $_.Name -like "*$n*" -or $_.Path -like "*$n*" })
        if ($match.Count -gt 0) { $select += [pscustomobject]@{ Path=$match[0].Path; Name=$match[0].Name } }
        else { Write-Warning "No match for '$n' - skipped." }
    }
    if ($select.Count -eq 0) { Write-Warning "No mods matched -PlaysetMods."; exit 1 }
    Write-Host "Selected: $($select.Count) mod(s)."
    New-DiCombinedMod -PerkMods $select -CombinedName $CombinedName -BaseDIName $baseDIName -GameDir $GameDir -TargetFolder $TargetFolder -UserFolder $UserFolder -LocDirs $LocDirs -WhatIf:$WhatIf
}
elseif ($SubMod) {
    $cands = Get-ModCandidates
    $match = @($cands | Where { $_.Name -like "*$SubMod*" -or $_.Path -like "*$SubMod*" })
    if ($match.Count -eq 0) { Write-Warning "No perk mod matched '$SubMod'."; exit 1 }
    if ($match.Count -gt 1) { Write-Warning "'$SubMod' matched multiple; using first." }
    $sel = $match[0]
    Write-Host "Generating sub-mod for: $($sel.Name)"
    New-DiSubMod -PerkModPath $sel.Path -PerkModName $sel.Name -BaseDIName $baseDIName -GameDir $GameDir -TargetFolder $TargetFolder -UserFolder $UserFolder -LocDirs $LocDirs -ExtraPerkModDirs $SubModExtraDirs -WhatIf:$WhatIf
}
else {
    Invoke-DiMenu
}
