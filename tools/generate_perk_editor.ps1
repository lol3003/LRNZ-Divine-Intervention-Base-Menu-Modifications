# =============================================================================
# DI Dynasty Perk Editor - Generator (Phase 1 step 0, plan v2)
# =============================================================================
# Reads vanilla (and optionally mod) common/dynasty_perks/*.txt and generates:
#   1. common/scripted_guis/DI_generated_perk_toggles_sgui.txt
#      - one per-perk toggle scripted gui: add if missing, remove if owned
#   2. gui/DI_generated_perk_grid.gui
#      - a `di_generated_perk_grid` type (vbox: one row per track, N perk buttons)
#
# Usage:
#   pwsh -File tools/generate_perk_editor.ps1
#   pwsh -File tools/generate_perk_editor.ps1 -GameDir "H:\SteamLibrary\steamapps\common\Crusader Kings III\game" -ModDir . -ExtraPerkDirs "C:\path\to\some_mod\common\dynasty_perks"
#
# Re-run after every game patch or when adding perk mods. Output is fully
# regenerated (idempotent). Do not hand-edit the generated files.
# =============================================================================

param(
    [string]$GameDir = "H:\SteamLibrary\steamapps\common\Crusader Kings III\game",
    [string]$ModDir  = "$PSScriptRoot\..",
    [string[]]$ExtraPerkDirs = @(),   # e.g. AGOT mod's common/dynasty_perks
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

$perkDirs   = @("$GameDir\common\dynasty_perks") + $ExtraPerkDirs
$outSgui    = Join-Path $ModDir "common\scripted_guis\DI_generated_perk_toggles_sgui.txt"
$outGui     = Join-Path $ModDir "gui\DI_generated_perk_grid.gui"
$outValues  = Join-Path $ModDir "common\script_values\DI_generated_perk_values.txt"

# --- Free-edit renown handling ------------------------------------------------
# add_dynasty_perk DEDUCTS renown at the vanilla cost (user-confirmed in-game):
#   cost = 250 (PERK_COST_BASE) + 500 (PERK_COST_MULTIPLIER) x total perks owned
# Free mode tops up the dynasty with the EXACT cost right before the grant, so
# the net renown change is zero. A flat top-up (previous design) left renown
# inconsistent and inflated the splendor level; exact refunds avoid both (the
# deduction brings current prestige - and thus splendor - back to baseline).
# The exact cost is computed by a generated script value: DI_dynasty_perk_cost_next
# (common/script_values/DI_generated_perk_values.txt).

# --- DLC gating ----------------------------------------------------------------
# Tracks can be DLC-gated in vanilla via is_shown = { has_dlc_feature = X }.
# The generator parses that gate and wraps each track row in the grid with
# HasDlcFeature('X') so the row is hidden when the DLC is missing (no errors,
# no dead buttons). Tracks without a gate are always shown.
# NOTE: only the FIRST has_dlc_feature in is_shown is used; vanilla tracks use
# exactly one (sometimes followed by OR game-rule/government conditions, which
# are ignored - worst case a gated track shows for players who disabled the
# "unrestricted legacies" game rule, which is acceptable for a cheat menu).

# --- Parse --------------------------------------------------------------------
function Get-Perks {
    param([string[]]$Directories)
    $perks = [ordered]@{}   # key -> track
    foreach ($dir in $Directories) {
        if (-not (Test-Path $dir)) { Write-Warning "perk dir not found: $dir"; continue }
        foreach ($file in Get-ChildItem $dir -Filter '*.txt' | Sort-Object Name) {
            $lines = Get-Content $file.FullName
            $currentKey = $null
            $depth = 0
            foreach ($line in $lines) {
                $trimmed = ($line -replace '#.*$', '').TrimEnd()
                if ($trimmed -match '^(\w+)\s*=\s*\{\s*$' -and $depth -eq 0) {
                    $currentKey = $Matches[1]
                    $depth = 1
                    continue
                }
                if ($null -ne $currentKey) {
                    $chars = $trimmed.ToCharArray() | Where-Object { $_ -eq '{' -or $_ -eq '}' }
                    foreach ($c in $chars) { if ($c -eq '{') { $depth++ } else { $depth-- } }
                    if ($depth -le 0) { $currentKey = $null; $depth = 0; continue }
                    if ($trimmed -match '^\s*legacy\s*=\s*(\w+)') {
                        $perks[$currentKey] = $Matches[1]
                    }
                }
            }
        }
    }
    return $perks
}

# Parse legacy track files: track key -> DLC feature (or $null if ungated)
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
                    if ($depth -le 0) { $currentKey = $null; $depth = 0; $inIsShown = $false; continue }
                    if ($inIsShown -and $trimmed -match 'has_dlc_feature\s*=\s*(\w+)') {
                        if (-not $gates.ContainsKey($currentKey)) { $gates[$currentKey] = $Matches[1] }
                    }
                }
            }
        }
    }
    return $gates
}

Write-Host "Parsing perk files..."
$perks = Get-Perks -Directories $perkDirs
if ($perks.Count -eq 0) { throw "No perks parsed - check -GameDir" }

# parse DLC gates from the same dirs' sibling dynasty_legacies folders
$legacyDirs = $perkDirs | ForEach-Object { $_ -replace 'dynasty_perks$', 'dynasty_legacies' }
$trackGates = Get-TrackDlcGates -Directories $legacyDirs
$gatedCount = ($trackGates.Values | Where-Object { $_ }).Count
Write-Host "Parsed $($perks.Count) perks ($gatedCount DLC-gated tracks)"

# group by track, preserving first-seen order
$tracks = [ordered]@{}
foreach ($k in $perks.Keys) {
    $t = $perks[$k]
    if (-not $tracks.Contains($t)) { $tracks[$t] = [System.Collections.Generic.List[string]]::new() }
    $tracks[$t].Add($k)
}
Write-Host "Parsed $($perks.Count) perks across $($tracks.Count) tracks"

# --- Output encoding -----------------------------------------------------------
# CK3's lexer wants UTF-8 with BOM for script files; plain UTF8 spams an error.log
# warning per generated file on every load.
$utf8Bom = [System.Text.UTF8Encoding]::new($true)

# --- Generate scripted guis ----------------------------------------------------
# Per perk: separate add (left click) and remove (right click) effects, each with
# is_shown gating so the GUI can grey out the inapplicable direction via
# GetScriptedGui(...).IsValid (the mod's standard enabled pattern).
$sgui = [System.Text.StringBuilder]::new()
[void]$sgui.AppendLine("# =============================================================================")
[void]$sgui.AppendLine("# GENERATED FILE - do not hand-edit.")
[void]$sgui.AppendLine("# Regenerate with: tools/generate_perk_editor.ps1")
[void]$sgui.AppendLine("# Per dynasty perk: add/remove effects (left click adds, right click removes),")
[void]$sgui.AppendLine("# plus per-track add-all/remove-all effects.")
[void]$sgui.AppendLine("# Operates on the dynasty selected in the DI perk editor")
[void]$sgui.AppendLine("# (player variable DI_dynasty_selected_dynasty).")
[void]$sgui.AppendLine("# =============================================================================")
[void]$sgui.AppendLine("")
foreach ($k in $perks.Keys) {
    [void]$sgui.AppendLine("DI_perk_add_$k = {")
    [void]$sgui.AppendLine("    scope = character")
    [void]$sgui.AppendLine("")
    [void]$sgui.AppendLine("    is_shown = {")
    [void]$sgui.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    [void]$sgui.AppendLine("            NOT = { has_dynasty_perk = $k }")
    [void]$sgui.AppendLine("        }")
    [void]$sgui.AppendLine("    }")
    [void]$sgui.AppendLine("")
    [void]$sgui.AppendLine("    effect = {")
    [void]$sgui.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    [void]$sgui.AppendLine("            if = {")
    [void]$sgui.AppendLine("                limit = { NOT = { has_dynasty_perk = $k } }")
    [void]$sgui.AppendLine("                # free-edit mode: top up the EXACT vanilla cost before the grant")
    [void]$sgui.AppendLine("                # (inside dynasty scope; gate checks root = player character)")
    [void]$sgui.AppendLine("                if = {")
    [void]$sgui.AppendLine("                    limit = { root = { has_variable = DI_legacy_editor_free_mode } }")
    [void]$sgui.AppendLine("                    add_dynasty_prestige = DI_dynasty_perk_cost_next")
    [void]$sgui.AppendLine("                }")
    [void]$sgui.AppendLine("                add_dynasty_perk = $k")
    [void]$sgui.AppendLine("            }")
    [void]$sgui.AppendLine("        }")
    [void]$sgui.AppendLine("    }")
    [void]$sgui.AppendLine("}")
    [void]$sgui.AppendLine("")
    [void]$sgui.AppendLine("DI_perk_remove_$k = {")
    [void]$sgui.AppendLine("    scope = character")
    [void]$sgui.AppendLine("")
    [void]$sgui.AppendLine("    is_shown = {")
    [void]$sgui.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    [void]$sgui.AppendLine("            has_dynasty_perk = $k")
    [void]$sgui.AppendLine("        }")
    [void]$sgui.AppendLine("    }")
    [void]$sgui.AppendLine("")
    [void]$sgui.AppendLine("    effect = {")
    [void]$sgui.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    [void]$sgui.AppendLine("            if = {")
    [void]$sgui.AppendLine("                limit = { has_dynasty_perk = $k }")
    [void]$sgui.AppendLine("                remove_dynasty_perk = $k")
    [void]$sgui.AppendLine("            }")
    [void]$sgui.AppendLine("        }")
    [void]$sgui.AppendLine("    }")
    [void]$sgui.AppendLine("}")
    [void]$sgui.AppendLine("")
}

# per-track add-all / remove-all (skip already-in-target-state perks so renown is
# only touched for perks actually granted)
foreach ($t in $tracks.Keys) {
    [void]$sgui.AppendLine("DI_track_add_all_$t = {")
    [void]$sgui.AppendLine("    scope = character")
    [void]$sgui.AppendLine("")
    [void]$sgui.AppendLine("    is_shown = {")
    [void]$sgui.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    [void]$sgui.AppendLine("            NOT = { $($t)_perks >= $($tracks[$t].Count) }")
    [void]$sgui.AppendLine("        }")
    [void]$sgui.AppendLine("    }")
    [void]$sgui.AppendLine("")
    [void]$sgui.AppendLine("    effect = {")
    [void]$sgui.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    foreach ($k in $tracks[$t]) {
        [void]$sgui.AppendLine("            if = {")
        [void]$sgui.AppendLine("                limit = { NOT = { has_dynasty_perk = $k } }")
        [void]$sgui.AppendLine("                if = {")
        [void]$sgui.AppendLine("                    limit = { root = { has_variable = DI_legacy_editor_free_mode } }")
        [void]$sgui.AppendLine("                    add_dynasty_prestige = DI_dynasty_perk_cost_next")
        [void]$sgui.AppendLine("                }")
        [void]$sgui.AppendLine("                add_dynasty_perk = $k")
        [void]$sgui.AppendLine("            }")
    }
    [void]$sgui.AppendLine("        }")
    [void]$sgui.AppendLine("    }")
    [void]$sgui.AppendLine("}")
    [void]$sgui.AppendLine("")
    [void]$sgui.AppendLine("DI_track_remove_all_$t = {")
    [void]$sgui.AppendLine("    scope = character")
    [void]$sgui.AppendLine("")
    [void]$sgui.AppendLine("    is_shown = {")
    [void]$sgui.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    [void]$sgui.AppendLine("            $($t)_perks > 0")
    [void]$sgui.AppendLine("        }")
    [void]$sgui.AppendLine("    }")
    [void]$sgui.AppendLine("")
    [void]$sgui.AppendLine("    effect = {")
    [void]$sgui.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    foreach ($k in $tracks[$t]) {
        [void]$sgui.AppendLine("            if = {")
        [void]$sgui.AppendLine("                limit = { has_dynasty_perk = $k }")
        [void]$sgui.AppendLine("                remove_dynasty_perk = $k")
        [void]$sgui.AppendLine("            }")
    }
    [void]$sgui.AppendLine("        }")
    [void]$sgui.AppendLine("    }")
    [void]$sgui.AppendLine("}")
    [void]$sgui.AppendLine("")
}
if (-not $WhatIf) {
    [System.IO.File]::WriteAllText($outSgui, $sgui.ToString(), $utf8Bom)
    Write-Host "Wrote $outSgui"
}

# --- Generate script values ----------------------------------------------------
# DI_dynasty_perk_cost_next = exact renown the next perk will cost:
# 250 (PERK_COST_BASE) + 500 (PERK_COST_MULTIPLIER) per already-owned perk.
# Total owned perks = sum over tracks of each track's count, measured with the
# auto-generated <track>_legacy_track_perks comparison triggers (dynasty scope).
$values = [System.Text.StringBuilder]::new()
[void]$values.AppendLine("# =============================================================================")
[void]$values.AppendLine("# GENERATED FILE - do not hand-edit.")
[void]$values.AppendLine("# Regenerate with: tools/generate_perk_editor.ps1")
[void]$values.AppendLine("# Exact renown cost of the next dynasty perk (vanilla formula), evaluated in")
[void]$values.AppendLine("# dynasty scope. Used by the generated perk toggles' free-edit mode.")
[void]$values.AppendLine("# =============================================================================")
[void]$values.AppendLine("")
[void]$values.AppendLine("DI_dynasty_perk_cost_next = {")
[void]$values.AppendLine("    value = 250   # PERK_COST_BASE")
foreach ($t in $tracks.Keys) {
    for ($i = 1; $i -le $tracks[$t].Count; $i++) {
        [void]$values.AppendLine("    if = { limit = { $($t)_perks >= $i } add = 500 }   # PERK_COST_MULTIPLIER")
    }
}
[void]$values.AppendLine("}")
if (-not $WhatIf) {
    New-Item -ItemType Directory -Force -Path (Split-Path $outValues) | Out-Null
    [System.IO.File]::WriteAllText($outValues, $values.ToString(), $utf8Bom)
    Write-Host "Wrote $outValues"
}

# --- Generate GUI grid ---------------------------------------------------------
# Vanilla loc: perk names = <perk_key>_name; track name/desc = <track>_name / <track>_desc.
# Track icons: gfx/interface/icons/dynasty/<track>.dds (verified in vanilla files).
$gui = [System.Text.StringBuilder]::new()
[void]$gui.AppendLine("### GENERATED FILE - do not hand-edit. Regenerate with: tools/generate_perk_editor.ps1")
[void]$gui.AppendLine("### Per-perk toggle grid for the DI dynasty perk editor.")
[void]$gui.AppendLine("### NOTE: has_dynasty_perk is a script trigger, not a GUI datafunction, so")
[void]$gui.AppendLine("### owned state cannot be shown in the UI - buttons are always clickable and")
[void]$gui.AppendLine("### toggle (left click adds, clicking again removes).")
[void]$gui.AppendLine("")
[void]$gui.AppendLine("types DI_DynastyGeneratedPerks {")
[void]$gui.AppendLine("    type di_generated_perk_grid = vbox {")
[void]$gui.AppendLine("        layoutpolicy_horizontal = expanding")
[void]$gui.AppendLine("        spacing = 5")
[void]$gui.AppendLine("")
foreach ($t in $tracks.Keys) {
    $perkList = $tracks[$t]
    $gate = $null
    if ($trackGates.ContainsKey($t)) { $gate = $trackGates[$t] }
    [void]$gui.AppendLine("        # ---- $t ($($perkList.Count) perks)$(if ($gate) { " [DLC: $gate]" }) ----")
    [void]$gui.AppendLine("        vbox = {")
    if ($gate) {
        # hide the whole track row when the DLC feature is missing
        [void]$gui.AppendLine("            visible = ""[HasDlcFeature( '$gate' )]""")
    }
    [void]$gui.AppendLine("            layoutpolicy_horizontal = expanding")
    [void]$gui.AppendLine("            margin = { 5 5 }")
    [void]$gui.AppendLine("")
    # track header: track icon + localized track name, desc as tooltip
    [void]$gui.AppendLine("            hbox = {")
    [void]$gui.AppendLine("                layoutpolicy_horizontal = expanding")
    [void]$gui.AppendLine("                spacing = 8")
    [void]$gui.AppendLine("")
    [void]$gui.AppendLine("                icon = {")
    [void]$gui.AppendLine("                    texture = ""gfx/interface/icons/dynasty/$t.dds""")
    [void]$gui.AppendLine("                    size = { 24 24 }")
    [void]$gui.AppendLine("                }")
    [void]$gui.AppendLine("")
    [void]$gui.AppendLine("                text_single = {")
    [void]$gui.AppendLine("                    layoutpolicy_horizontal = expanding")
    # bare keys don't resolve from modded GUI text= properties (only vanilla C++
    # tooltips / $link$ loc chains do) - Localize() is the explicit GUI path
    [void]$gui.AppendLine('                    text = "[Localize(''' + $t + '_name'')]"')
    [void]$gui.AppendLine('                    tooltip = "[Localize(''' + $t + '_desc'')]"')
    [void]$gui.AppendLine('                    default_format = ""#high""')
    [void]$gui.AppendLine("                }")
    [void]$gui.AppendLine("")
    # track button: left click adds all missing perks, right click removes all owned;
    # greyed out when the left-click direction is inapplicable (IsValid = is_shown)
    [void]$gui.AppendLine("                button_standard = {")
    [void]$gui.AppendLine("                    size = { 130 26 }")
    [void]$gui.AppendLine("                    text = DI_DYNASTY_EDITOR_TRACK_BUTTON")
    [void]$gui.AppendLine("                    enabled = ""[GetScriptedGui('DI_track_add_all_$t').IsValid(GuiScope.SetRoot(GetPlayer.MakeScope).End)]""")
    [void]$gui.AppendLine("                    onclick = ""[GetScriptedGui('DI_track_add_all_$t').Execute(GuiScope.SetRoot(GetPlayer.MakeScope).End)]""")
    [void]$gui.AppendLine("                    onrightclick = ""[GetScriptedGui('DI_track_remove_all_$t').Execute(GuiScope.SetRoot(GetPlayer.MakeScope).End)]""")
    [void]$gui.AppendLine("                    tooltip = DI_DYNASTY_EDITOR_TRACK_BUTTON_TT")
    [void]$gui.AppendLine("                }")
    [void]$gui.AppendLine("            }")
    [void]$gui.AppendLine("")
    [void]$gui.AppendLine("            flowcontainer = {")
    [void]$gui.AppendLine("                layoutpolicy_horizontal = expanding")
    [void]$gui.AppendLine("                spacing = 5")
    [void]$gui.AppendLine("")
    foreach ($k in $perkList) {
        # plain button_standard with inline content (the mod's proven skills-tab /
        # title-manager pattern - the template+blockoverride version lost right-click)
        # left click adds (greyed out if owned), right click removes (no-op if not owned)
        [void]$gui.AppendLine("                button_standard = {")
        [void]$gui.AppendLine("                    size = { 260 44 }")
        [void]$gui.AppendLine("                    button_ignore = none")
        [void]$gui.AppendLine("                    enabled = ""[GetScriptedGui('DI_perk_add_$k').IsValid(GuiScope.SetRoot(GetPlayer.MakeScope).End)]""")
        [void]$gui.AppendLine("                    onclick = ""[GetScriptedGui('DI_perk_add_$k').Execute(GuiScope.SetRoot(GetPlayer.MakeScope).End)]""")
        [void]$gui.AppendLine("                    onrightclick = ""[GetScriptedGui('DI_perk_remove_$k').Execute(GuiScope.SetRoot(GetPlayer.MakeScope).End)]""")
        [void]$gui.AppendLine('                    tooltip = "[Localize(''' + $k + '_name'')]"')
        [void]$gui.AppendLine("")
        [void]$gui.AppendLine("                    hbox = {")
        [void]$gui.AppendLine("                        margin = { 5 0 }")
        [void]$gui.AppendLine("                        spacing = 8")
        [void]$gui.AppendLine("")
        [void]$gui.AppendLine("                        icon = {")
        [void]$gui.AppendLine("                            size = { 34 34 }")
        [void]$gui.AppendLine("                            texture = ""gfx/interface/icons/dynasty/$t.dds""")
        [void]$gui.AppendLine("                        }")
        [void]$gui.AppendLine("")
        [void]$gui.AppendLine("                        text_single = {")
        [void]$gui.AppendLine("                            layoutpolicy_horizontal = expanding")
        [void]$gui.AppendLine('                            text = "[Localize(''' + $k + '_name'')]"')
        [void]$gui.AppendLine('                            default_format = ""#clickable""')
        [void]$gui.AppendLine("                        }")
        [void]$gui.AppendLine("                    }")
        [void]$gui.AppendLine("                }")
        [void]$gui.AppendLine("")
    }
    [void]$gui.AppendLine("            }")
    [void]$gui.AppendLine("        }")
    [void]$gui.AppendLine("")
}
[void]$gui.AppendLine("    }")
[void]$gui.AppendLine("}")
if (-not $WhatIf) {
    [System.IO.File]::WriteAllText($outGui, $gui.ToString(), $utf8Bom)
    Write-Host "Wrote $outGui"
}

Write-Host "Done. $($perks.Count) toggles, $($tracks.Count) track rows generated."
