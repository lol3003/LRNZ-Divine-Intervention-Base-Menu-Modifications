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

# --- Free-edit renown handling ------------------------------------------------
# add_dynasty_perk likely deducts renown (250 + unlocked*500). In free mode we
# top up the dynasty BEFORE the grant with a flat worst-case amount so the
# purchase can never fail. Excess renown is acceptable for a cheat tool.
# Set to 0 to disable top-up entirely (then free mode = normal cost).
$FreeModeTopUp = 2750

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

Write-Host "Parsing perk files..."
$perks = Get-Perks -Directories $perkDirs
if ($perks.Count -eq 0) { throw "No perks parsed - check -GameDir" }

# group by track, preserving first-seen order
$tracks = [ordered]@{}
foreach ($k in $perks.Keys) {
    $t = $perks[$k]
    if (-not $tracks.Contains($t)) { $tracks[$t] = [System.Collections.Generic.List[string]]::new() }
    $tracks[$t].Add($k)
}
Write-Host "Parsed $($perks.Count) perks across $($tracks.Count) tracks"

# --- Generate scripted guis ----------------------------------------------------
$sgui = [System.Text.StringBuilder]::new()
[void]$sgui.AppendLine("# =============================================================================")
[void]$sgui.AppendLine("# GENERATED FILE - do not hand-edit.")
[void]$sgui.AppendLine("# Regenerate with: tools/generate_perk_editor.ps1")
[void]$sgui.AppendLine("# One toggle scripted gui per dynasty perk: adds if missing, removes if owned.")
[void]$sgui.AppendLine("# Operates on the dynasty selected in the DI perk editor")
[void]$sgui.AppendLine("# (player variable DI_dynasty_selected_dynasty).")
[void]$sgui.AppendLine("# =============================================================================")
[void]$sgui.AppendLine("")
foreach ($k in $perks.Keys) {
    [void]$sgui.AppendLine("DI_perk_toggle_$k = {")
    [void]$sgui.AppendLine("    scope = character")
    [void]$sgui.AppendLine("")
    [void]$sgui.AppendLine("    effect = {")
    [void]$sgui.AppendLine("        # free-edit mode: top up renown so the grant can never fail")
    [void]$sgui.AppendLine("        if = {")
    [void]$sgui.AppendLine("            limit = { has_variable = DI_legacy_editor_free_mode }")
    [void]$sgui.AppendLine("            add_dynasty_prestige = $FreeModeTopUp")
    [void]$sgui.AppendLine("        }")
    [void]$sgui.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    [void]$sgui.AppendLine("            if = {")
    [void]$sgui.AppendLine("                limit = { has_dynasty_perk = $k }")
    [void]$sgui.AppendLine("                remove_dynasty_perk = $k")
    [void]$sgui.AppendLine("            }")
    [void]$sgui.AppendLine("            else = {")
    [void]$sgui.AppendLine("                add_dynasty_perk = $k")
    [void]$sgui.AppendLine("            }")
    [void]$sgui.AppendLine("        }")
    [void]$sgui.AppendLine("    }")
    [void]$sgui.AppendLine("}")
    [void]$sgui.AppendLine("")
}
if (-not $WhatIf) {
    Set-Content -Path $outSgui -Value $sgui.ToString() -Encoding UTF8
    Write-Host "Wrote $outSgui"
}

# --- Generate GUI grid ---------------------------------------------------------
# Perk/track loc: vanilla loc keys are the perk/track keys themselves.
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
    [void]$gui.AppendLine("        # ---- $t ($($perkList.Count) perks) ----")
    [void]$gui.AppendLine("        vbox = {")
    [void]$gui.AppendLine("            layoutpolicy_horizontal = expanding")
    [void]$gui.AppendLine("            margin = { 5 5 }")
    [void]$gui.AppendLine("")
    [void]$gui.AppendLine("            text_single = {")
    [void]$gui.AppendLine("                layoutpolicy_horizontal = expanding")
    [void]$gui.AppendLine("                text = ""$t""")
    [void]$gui.AppendLine("                default_format = ""#high""")
    [void]$gui.AppendLine("            }")
    [void]$gui.AppendLine("")
    [void]$gui.AppendLine("            flowcontainer = {")
    [void]$gui.AppendLine("                layoutpolicy_horizontal = expanding")
    [void]$gui.AppendLine("                spacing = 5")
    [void]$gui.AppendLine("")
    foreach ($k in $perkList) {
        [void]$gui.AppendLine("                button_standard = {")
        [void]$gui.AppendLine("                    text = ""$k""")
        [void]$gui.AppendLine("                    tooltip = ""$k""")
        [void]$gui.AppendLine("                    onclick = ""[GetScriptedGui('DI_perk_toggle_$k').Execute(GuiScope.SetRoot(GetPlayer.MakeScope).End)]""")
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
    Set-Content -Path $outGui -Value $gui.ToString() -Encoding UTF8
    Write-Host "Wrote $outGui"
}

Write-Host "Done. $($perks.Count) toggles, $($tracks.Count) track rows generated."
