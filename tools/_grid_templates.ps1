# =============================================================================
# _grid_templates.ps1 - SHARED vanilla-look grid emit (dot-sourced by both generators)
# =============================================================================
# DEFINITIONS ONLY - this file must never run top-level code. It is dot-sourced by
# generate_perk_editor.ps1 / generate_mod_perks.ps1, which own the parse, the
# StringBuilder, the encoding and the actual file writes; this module only turns one
# track (or one perk) into GUI text via the two writers below.
#
# Helpers (call after dot-sourcing):
#   Write-VanillaTrackSection $Sb $Track $PerkList $Gate   -> one track section
#   Write-VanillaPerkButton   $Sb $Key    $Track           -> one perk button
#
# Look is modelled on the vanilla legacy window
# (game/gui/window_dynasty_legacy.gui, hbox_legacy_item + perk button): 80x80 track
# icon, localized <track>_name / <track>_desc header, then 296x128 perk buttons on a
# mask_frame_horizontal / tile_frame_thin_02 background.
#
# Buttons are ALWAYS ENABLED (no `enabled = GetScriptedGui(...).IsValid(...)`):
# that binding tracks the *add* direction, so once a perk is owned the widget gets
# disabled and onrightclick (remove) can never dispatch. Left click = add (no-op if
# already owned, guarded by the add SGUI's is_shown), right click = remove (no-op if
# not owned). Out-of-order add/remove is intended.
# =============================================================================

# --- One perk button (296x128), wired to DI_perk_add_<key> / DI_perk_remove_<key> --
function Write-VanillaPerkButton {
    param($Sb, [string]$Key, [string]$Track)
    [void]$Sb.AppendLine("                button_standard = {")
    [void]$Sb.AppendLine("                    size = { 296 128 }")
    [void]$Sb.AppendLine("                    button_ignore = none")
    [void]$Sb.AppendLine("                    onclick = ""[GetScriptedGui('DI_perk_add_$Key').Execute(GuiScope.SetRoot(GetPlayer.MakeScope).End)]""")
    [void]$Sb.AppendLine("                    onrightclick = ""[GetScriptedGui('DI_perk_remove_$Key').Execute(GuiScope.SetRoot(GetPlayer.MakeScope).End)]""")
    [void]$Sb.AppendLine('                    tooltip = "[Localize(''' + $Key + '_name'')]"')
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("                    background = {")
    [void]$Sb.AppendLine("                        size = { 100% 100% }")
    [void]$Sb.AppendLine("                        texture = ""gfx/interface/component_masks/mask_frame_horizontal.dds""")
    [void]$Sb.AppendLine("                        tintcolor = { 0 0 0 0.7 }")
    [void]$Sb.AppendLine("                        alpha = 0.9")
    [void]$Sb.AppendLine("                    }")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("                    background = {")
    [void]$Sb.AppendLine("                        size = { 100% 100% }")
    [void]$Sb.AppendLine("                        texture = ""gfx/interface/component_masks/mask_frame_horizontal.dds""")
    [void]$Sb.AppendLine("                        tintcolor = { 0 0 0 0.8 }")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("                        modify_texture = {")
    [void]$Sb.AppendLine("                            texture = ""gfx/interface/component_tiles/tile_frame_thin_02.dds""")
    [void]$Sb.AppendLine("                            spriteType = Corneredtiled")
    [void]$Sb.AppendLine("                            spriteborder = { 50 50 }")
    [void]$Sb.AppendLine("                            blend_mode = alphamultiply")
    [void]$Sb.AppendLine("                            alpha = 0.2")
    [void]$Sb.AppendLine("                            texture_density = 2")
    [void]$Sb.AppendLine("                        }")
    [void]$Sb.AppendLine("                    }")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("                    vbox = {")
    [void]$Sb.AppendLine("                        margin = { 10 5 }")
    [void]$Sb.AppendLine("                        margin_top = 18")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("                        text_multi = {")
    [void]$Sb.AppendLine('                            text = "[Localize(''' + $Key + '_name'')]"')
    [void]$Sb.AppendLine("                            autoresize = yes")
    [void]$Sb.AppendLine("                            max_width = 296")
    [void]$Sb.AppendLine("                            fontsize_min = 14")
    [void]$Sb.AppendLine("                            default_format = ""#low""")
    [void]$Sb.AppendLine("                        }")
    [void]$Sb.AppendLine("                    }")
    [void]$Sb.AppendLine("                }")
    [void]$Sb.AppendLine("")
}

# --- One track section: vanilla-style header + flowcontainer of perk buttons -----
# $Gate is a DLC feature name (or empty); when set the whole section is hidden with
# visible = "[HasDlcFeature( '<gate>' )]" so a missing DLC leaves no dead buttons.
function Write-VanillaTrackSection {
    param($Sb, [string]$Track, $PerkList, [string]$Gate)
    [void]$Sb.AppendLine("        # ---- $Track ($($PerkList.Count) perks)$(if ($Gate) { "" [DLC: $Gate]"" }) ----")
    [void]$Sb.AppendLine("        vbox = {")
    if ($Gate) {
        [void]$Sb.AppendLine("            visible = ""[HasDlcFeature( '$Gate' )]""")
    }
    [void]$Sb.AppendLine("            layoutpolicy_horizontal = expanding")
    [void]$Sb.AppendLine("            spacing = 5")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("            hbox = {")
    [void]$Sb.AppendLine("                layoutpolicy_horizontal = expanding")
    [void]$Sb.AppendLine("                spacing = 10")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("                icon = {")
    [void]$Sb.AppendLine("                    size = { 80 80 }")
    [void]$Sb.AppendLine("                    texture = ""gfx/interface/icons/dynasty/$Track.dds""")
    [void]$Sb.AppendLine("                }")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("                vbox = {")
    [void]$Sb.AppendLine("                    layoutpolicy_horizontal = expanding")
    [void]$Sb.AppendLine("                    margin = { 5 5 }")
    [void]$Sb.AppendLine("                    spacing = 2")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("                    text_single = {")
    [void]$Sb.AppendLine("                        layoutpolicy_horizontal = expanding")
    [void]$Sb.AppendLine('                        text = "[Localize(''' + $Track + '_name'')]"')
    [void]$Sb.AppendLine("                        default_format = ""#high""")
    [void]$Sb.AppendLine("                        using = Font_Size_Medium")
    [void]$Sb.AppendLine("                        fontsize_min = 14")
    [void]$Sb.AppendLine("                    }")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("                    text_multi = {")
    [void]$Sb.AppendLine("                        layoutpolicy_horizontal = expanding")
    [void]$Sb.AppendLine('                        text = "[Localize(''' + $Track + '_desc'')]"')
    [void]$Sb.AppendLine("                        maximumsize = { -1 90 }")
    [void]$Sb.AppendLine("                        fontsize_min = 14")
    [void]$Sb.AppendLine("                    }")
    [void]$Sb.AppendLine("                }")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("                button_standard = {")
    [void]$Sb.AppendLine("                    size = { 130 26 }")
    [void]$Sb.AppendLine("                    text = DI_DYNASTY_EDITOR_TRACK_BUTTON")
    [void]$Sb.AppendLine("                    onclick = ""[GetScriptedGui('DI_track_add_all_$Track').Execute(GuiScope.SetRoot(GetPlayer.MakeScope).End)]""")
    [void]$Sb.AppendLine("                    onrightclick = ""[GetScriptedGui('DI_track_remove_all_$Track').Execute(GuiScope.SetRoot(GetPlayer.MakeScope).End)]""")
    [void]$Sb.AppendLine("                    tooltip = DI_DYNASTY_EDITOR_TRACK_BUTTON_TT")
    [void]$Sb.AppendLine("                }")
    [void]$Sb.AppendLine("            }")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("            flowcontainer = {")
    [void]$Sb.AppendLine("                layoutpolicy_horizontal = expanding")
    [void]$Sb.AppendLine("                spacing = 5")
    [void]$Sb.AppendLine("")
    foreach ($k in $PerkList) {
        Write-VanillaPerkButton $Sb $k $Track
    }
    [void]$Sb.AppendLine("            }")
    [void]$Sb.AppendLine("        }")
    [void]$Sb.AppendLine("")
}

