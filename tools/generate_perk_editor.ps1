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
    [switch]$WhatIf,
    [switch]$Check   # dry-run summary only (no writes); used by validate_perk_editor.ps1
)

$ErrorActionPreference = "Stop"
$WhatIf = $WhatIf -or $Check

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

# --- Shared parser (dot-sourced) -------------------------------------------------
# Both generators use the same parser so a fix/feature lands in both. Extraction
# moved verbatim here into _perk_parser.ps1 (plan v9 F5). The vanilla-look grid
# writers live in _grid_templates.ps1 and are dot-sourced further down - AFTER the
# parse and the encoding setup, because that module is definitions-only and the
# emit below needs $perks / $tracks / $trackGates / $utf8Bom in scope.
. (Join-Path $PSScriptRoot "_perk_parser.ps1")

Write-Host "Parsing perk files..."
$perks = Get-Perks -Directories $perkDirs
if ($perks.Count -eq 0) { throw "No perks parsed - check -GameDir" }
if (-not (Test-PerksModel $perks)) { throw "Parsed perk model is inconsistent - aborting before writing generated files" }

# parse DLC gates from the same dirs' sibling dynasty_legacies folders
$legacyDirs = $perkDirs | ForEach-Object { $_ -replace 'dynasty_perks$', 'dynasty_legacies' }
$trackGates = Get-TrackDlcGates -Directories $legacyDirs
$gatedCount = ($trackGates.Values | Where-Object { $_ }).Count
Write-Host "Parsed $($perks.Count) perks ($gatedCount DLC-gated tracks)"

# group by track, preserving first-seen order
$tracks = Group-PerksByTrack $perks
Write-Host "Parsed $($perks.Count) perks across $($tracks.Count) tracks"

# --- Output encoding -----------------------------------------------------------
# CK3's lexer wants UTF-8 with BOM for script files; plain UTF8 spams an error.log
# warning per generated file on every load.
$utf8Bom = [System.Text.UTF8Encoding]::new($true)

# --- Shared grid writers (dot-sourced after parse + encoding) --------------------
# Definitions only: Write-VanillaTrackSection / Write-VanillaPerkButton. The actual
# grid emit is the "Generate GUI grid" section at the bottom of this file, which is
# the only place that owns $gui / $outGui / the file write.
. (Join-Path $PSScriptRoot "_grid_templates.ps1")

# --- Shared SGUI/track emission helpers -----------------------------------------
# Extracted (plan step 1) so the add/remove and add-all/remove-all rules live in
# exactly one place; output must remain byte-identical to the pre-refactor build.
function Write-PerPerkBlocks {
    param($Sb, [string]$Key)
    [void]$Sb.AppendLine("DI_perk_add_$Key = {")
    [void]$Sb.AppendLine("    scope = character")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("    is_shown = {")
    [void]$Sb.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    [void]$Sb.AppendLine("            NOT = { has_dynasty_perk = $Key }")
    [void]$Sb.AppendLine("        }")
    [void]$Sb.AppendLine("    }")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("    effect = {")
    [void]$Sb.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    [void]$Sb.AppendLine("            if = {")
    [void]$Sb.AppendLine("                limit = { NOT = { has_dynasty_perk = $Key } }")
    [void]$Sb.AppendLine("                # free-edit mode: top up the EXACT vanilla cost before the grant")
    [void]$Sb.AppendLine("                # (inside dynasty scope; gate checks root = player character)")
    [void]$Sb.AppendLine("                if = {")
    [void]$Sb.AppendLine("                    limit = { root = { has_variable = DI_legacy_editor_free_mode } }")
    [void]$Sb.AppendLine("                    add_dynasty_prestige = DI_dynasty_perk_cost_next")
    [void]$Sb.AppendLine("                }")
    [void]$Sb.AppendLine("                add_dynasty_perk = $Key")
    [void]$Sb.AppendLine("            }")
    [void]$Sb.AppendLine("        }")
    [void]$Sb.AppendLine("    }")
    [void]$Sb.AppendLine("}")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("DI_perk_remove_$Key = {")
    [void]$Sb.AppendLine("    scope = character")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("    is_shown = {")
    [void]$Sb.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    [void]$Sb.AppendLine("            has_dynasty_perk = $Key")
    [void]$Sb.AppendLine("        }")
    [void]$Sb.AppendLine("    }")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("    effect = {")
    [void]$Sb.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    [void]$Sb.AppendLine("            if = {")
    [void]$Sb.AppendLine("                limit = { has_dynasty_perk = $Key }")
    [void]$Sb.AppendLine("                remove_dynasty_perk = $Key")
    [void]$Sb.AppendLine("            }")
    [void]$Sb.AppendLine("        }")
    [void]$Sb.AppendLine("    }")
    [void]$Sb.AppendLine("}")
    [void]$Sb.AppendLine("")
}

function Write-TrackAddAllBlock {
    param($Sb, [string]$Track, $PerkList)
    [void]$Sb.AppendLine("DI_track_add_all_$Track = {")
    [void]$Sb.AppendLine("    scope = character")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("    is_shown = {")
    [void]$Sb.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    [void]$Sb.AppendLine("            NOT = { $($Track)_perks >= $($PerkList.Count) }")
    [void]$Sb.AppendLine("        }")
    [void]$Sb.AppendLine("    }")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("    effect = {")
    [void]$Sb.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    foreach ($k in $PerkList) {
        [void]$Sb.AppendLine("            if = {")
        [void]$Sb.AppendLine("                limit = { NOT = { has_dynasty_perk = $k } }")
        [void]$Sb.AppendLine("                if = {")
        [void]$Sb.AppendLine("                    limit = { root = { has_variable = DI_legacy_editor_free_mode } }")
        [void]$Sb.AppendLine("                    add_dynasty_prestige = DI_dynasty_perk_cost_next")
        [void]$Sb.AppendLine("                }")
        [void]$Sb.AppendLine("                add_dynasty_perk = $k")
        [void]$Sb.AppendLine("            }")
    }
    [void]$Sb.AppendLine("        }")
    [void]$Sb.AppendLine("    }")
    [void]$Sb.AppendLine("}")
    [void]$Sb.AppendLine("")
}

function Write-TrackRemoveAllBlock {
    param($Sb, [string]$Track, $PerkList)
    [void]$Sb.AppendLine("DI_track_remove_all_$Track = {")
    [void]$Sb.AppendLine("    scope = character")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("    is_shown = {")
    [void]$Sb.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    [void]$Sb.AppendLine("            $($Track)_perks > 0")
    [void]$Sb.AppendLine("        }")
    [void]$Sb.AppendLine("    }")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("    effect = {")
    [void]$Sb.AppendLine("        var:DI_dynasty_selected_dynasty = {")
    foreach ($k in $PerkList) {
        [void]$Sb.AppendLine("            if = {")
        [void]$Sb.AppendLine("                limit = { has_dynasty_perk = $k }")
        [void]$Sb.AppendLine("                remove_dynasty_perk = $k")
        [void]$Sb.AppendLine("            }")
    }
    [void]$Sb.AppendLine("        }")
    [void]$Sb.AppendLine("    }")
    [void]$Sb.AppendLine("}")
    [void]$Sb.AppendLine("")
}

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
    Write-PerPerkBlocks $sgui $k
}

# per-track add-all / remove-all (skip already-in-target-state perks so renown is
# only touched for perks actually granted)
foreach ($t in $tracks.Keys) {
    Write-TrackAddAllBlock $sgui $t $tracks[$t]
    Write-TrackRemoveAllBlock $sgui $t $tracks[$t]
}
if (-not $WhatIf) {
    New-Item -ItemType Directory -Force -Path (Split-Path $outSgui) | Out-Null
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

# --- Generate GUI grid -----------------------------------------------------------
# Vanilla-look grid: one section per track (80x80 track icon + localized <track>_name
# / <track>_desc header + add-all/remove-all button) followed by a flowcontainer of
# PER-KEY perk buttons, so each perk keeps its own add/remove scripted gui (no runtime
# perk enumeration exists in CK3). Perks are never disabled: left click adds, right
# click removes, out-of-order is intended.
# Vanilla loc: perk names = <perk_key>_name; track name/desc = <track>_name / <track>_desc.
# Track icons: gfx/interface/icons/dynasty/<track>.dds (verified in vanilla files).
$gui = [System.Text.StringBuilder]::new()
[void]$gui.AppendLine("### GENERATED FILE - do not hand-edit. Regenerate with: tools/generate_perk_editor.ps1")
[void]$gui.AppendLine("### Per-perk toggle grid for the DI dynasty perk editor.")
[void]$gui.AppendLine("### NOTE: has_dynasty_perk is a script trigger, not a GUI datafunction, so owned")
[void]$gui.AppendLine("### state cannot be rendered in the UI. Buttons are therefore always enabled:")
[void]$gui.AppendLine("### left click = add (no-op if already owned via the add SGUI's is_shown guard),")
[void]$gui.AppendLine("### right click = remove (no-op if not owned). Out-of-order add/remove is intended.")
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
    Write-VanillaTrackSection $gui $t $perkList $gate
}
[void]$gui.AppendLine("    }")
    # Empty extension slot (Phase 3). Sub-mods and combined-playset mods REDEFINE this
    # type with their extra track rows, which is why the base keeps defining it: the
    # instantiation in gui/DI_dynasty_perk_editor.gui (blockoverride "scrollbox_content")
    # must always resolve to a defined type, with or without a compatch enabled. With no
    # compatch it renders nothing. One shared name is intentional: exactly ONE DI Perks
    # compatch per modlist (see docs/DYNASTY_PERK_EDITOR_PLAN.md, "Coexistence").
[void]$gui.AppendLine("    type di_perk_grid_extension = vbox {")
[void]$gui.AppendLine("        layoutpolicy_horizontal = expanding")
[void]$gui.AppendLine("    }")
[void]$gui.AppendLine("}")

if (-not $WhatIf) {
    New-Item -ItemType Directory -Force -Path (Split-Path $outGui) | Out-Null
    [System.IO.File]::WriteAllText($outGui, $gui.ToString(), $utf8Bom)
    Write-Host "Wrote $outGui"
}

Write-Host "Done. $($perks.Count) toggles, $($tracks.Count) track rows generated."

