# Dynasty Perk Editor — Action Plan

> Companion to `DYNASTY_PERK_EDITOR_OPTIONS.md`. This is the concrete "what to do next" plan,
> based on research into the installed game files (patch 1.19, `H:\SteamLibrary\...`).

---

## 🎉 Key research findings (new — verified in vanilla files)

### 1. The grant effect EXISTS: `add_dynasty_perk`

Found in `common/scripted_effects/00_mongol_invasion_effects.txt` — vanilla itself uses it to
grant legacies to the Mongol empire:

```paradox
dynasty = {
    add_dynasty_prestige_level = 5
    add_dynasty_prestige = 10000
    add_dynasty_perk = warfare_legacy_1
    add_dynasty_perk = warfare_legacy_2
    ...
}
```

- Works inside a `dynasty` scope → we can target `scope:DI_dynasty_selected_dynasty.Dynasty`
- ⚠️ **COST WARNING (confirmed):** `add_dynasty_perk` **deducts renown** from the dynasty.
  Evidence:
  - `DYNASTY_PRESTIGE_COST_LONG` loc = `"Renown: [dynasty_prestige_i] $VALUE|0$"` — dynasty
    prestige **is** renown.
  - Cost formula from defines: `COST = PERK_COST_BASE (250) + unlocked_perks * PERK_COST_MULTIPLIER (500)`
    → perks cost 250 / 750 / 1250 / 1750 / 2250 (total 6,250 for a full track).
  - The Mongol event grants `add_dynasty_prestige = 10000` **alongside** its 5+ perks — consistent
    with the script effect charging renown and the event compensating for it.
  - In-game memory confirms: granting a perk consumes the required renown; re-adding prestige
    afterwards pushes the renown *level* back up.
- **Mitigation for the editor:** after each `add_dynasty_perk`, compensate with
  `add_dynasty_prestige = <cost>` (compute from the perk's index: `250 + 500 * index`), or simpler:
  add a fixed large refund (e.g. `add_dynasty_prestige = 2500` per perk) or a separate
  "Renown +5000" cheat button. Exact per-perk refund is cleaner:
  ```paradox
  add_dynasty_perk = warfare_legacy_1
  add_dynasty_prestige = 250      # refund perk 1 cost
  ```
- Symmetric trigger `has_dynasty_perk = <key>` exists (used in `varangian_events.txt`,
  `artifact_events.txt`) → we can guard "add next perk" per track.

### 2. Perk definitions are data-driven and enumerable on disk

- Perks: `common/dynasty_perks/*.txt` — **105 perks** in vanilla (10 DLC files)
- Naming convention is 100% consistent: `<track_prefix>_legacy_<1..5>` (e.g. `warfare_legacy_1`,
  `fp1_adventure_legacy_3`)
- Each perk declares its track: `legacy = warfare_legacy_track`
- Tracks: `common/dynasty_legacies/*.txt` — **20 tracks** in vanilla (9 base + 11 DLC)

### 3. No script-side iteration exists

No `every_dynasty_perk` / `any_dynasty_perk` anywhere in vanilla. Script **cannot enumerate** the
perk list at runtime. GUI-side, only `DynastyView.GetLegacies` (engine-bound, see options doc).

### ➜ Consequence: **Option B (dynamic enumeration) is not possible in script.**
**Option C (hardcoded grid) + the discovered `add_dynasty_perk` effect is the way** — and it can
still cover modded legacies via a small compatibility pattern (see Phase 3).

---

## ✅ Script docs generated (in-game `script_docs` console command) — findings

Logs are in `Documents/Paradox Interactive/Crusader Kings III/logs/`:
`effects.log`, `triggers.log`, `event_scopes.log`, `event_targets.log`.

### Confirmed effects (both dynasty scope)
| Effect | Signature |
|---|---|
| `add_dynasty_perk` | `add_dynasty_perk = key` — adds perk (deducts renown) |
| `remove_dynasty_perk` | `remove_dynasty_perk = key` — **removal IS possible!** Phase 2 remove-buttons are go |

### Confirmed triggers (dynasty scope)
| Trigger | Signature |
|---|---|
| `has_dynasty_perk` | `has_dynasty_perk = key` |
| `<track>_legacy_track_perks` | **auto-generated per track** (20 vanilla ones found) — compares perk count: `warfare_legacy_track_perks >= 3`. **Mods adding tracks get their own trigger automatically** → tooltips/progress display can be dynamic per track! |

### Still missing
- No `every_/any_dynasty_perk` iterator → runtime enumeration remains impossible →
  Phase 3a generator still required for modded track coverage.
- No dynasty→perk scope links in `event_targets.log`.

---

## Phase 1 — Core editor: hardcoded tracks + add-next-perk (MVP)

**Goal:** Working "add next perk in track" buttons for all 20 vanilla tracks.

### 1.1 Create the scripted effects
New file: `common/scripted_effects/DI_dynasty_perk_effects.txt`

One effect per track, following the mod's lifestyle-present pattern (`NOT has → add`),
**with renown refund** (see cost warning above):

```paradox
DI_dynasty_add_warfare_perk = {
    scope = character
    effect = {
        scope:DI_dynasty_selected_dynasty.Dynasty = {
            if = {
                limit = { NOT = { has_dynasty_perk = warfare_legacy_1 } }
                add_dynasty_perk = warfare_legacy_1
                add_dynasty_prestige = 250       # refund: 250 + 500*0
            }
            else_if = {
                limit = { NOT = { has_dynasty_perk = warfare_legacy_2 } }
                add_dynasty_perk = warfare_legacy_2
                add_dynasty_prestige = 750       # refund: 250 + 500*1
            }
            else_if = {
                limit = { NOT = { has_dynasty_perk = warfare_legacy_3 } }
                add_dynasty_perk = warfare_legacy_3
                add_dynasty_prestige = 1250      # refund: 250 + 500*2
            }
            else_if = {
                limit = { NOT = { has_dynasty_perk = warfare_legacy_4 } }
                add_dynasty_perk = warfare_legacy_4
                add_dynasty_prestige = 1750      # refund: 250 + 500*3
            }
            else_if = {
                limit = { NOT = { has_dynasty_perk = warfare_legacy_5 } }
                add_dynasty_perk = warfare_legacy_5
                add_dynasty_prestige = 2250      # refund: 250 + 500*4
            }
        }
    }
}
```

> Note: refunding renown still increments the renown *level* progress — that's unavoidable
> (the level is derived from total prestige gained). If that's undesirable, the alternative is
> not refunding and letting the editor consume renown like a normal purchase, or adding a
> separate "Renown +5000" cheat button the user clicks as needed.

Repeat for all 20 tracks (keys listed in the appendix below). Removal is also possible:
`remove_dynasty_perk = <key>` (confirmed in effects.log) — add a right-click "remove last perk"
variant per track (walk the track backwards with `has_dynasty_perk` checks).

**Bonus from script_docs:** the auto-generated `<track>_legacy_track_perks` triggers (e.g.
`warfare_legacy_track_perks >= 3`) let tooltips show the current perk count per track — and since
these triggers are auto-generated for *every* track (including mod-added ones), any modded tracks
added by the generator automatically get working count tooltips too.

### 1.2 Build the UI
In `gui/DI_dynasty_perk_editor.gui`, replace the placeholder content with a grid of buttons —
copy the styling of the lifestyle present buttons (`DI_ce_present_dark_button` template):

- One button per track: icon = track icon (`DynastyLegacy.GetTrackIcon` won't work without
  DynastyView — use static `texture = gfx/interface/icons/dynasty_legacies/...` per track instead)
- Tooltip shows current unlocked count via `has_dynasty_perk` checks or a custom loc
- Left-click = add next perk; right-click = remove last (phase 2)

### 1.3 Wire up
- Register effects as scripted_guis if buttons use `GetScriptedGui(...).Execute(...)` (the mod's
  standard), or call them as scripted_effects from existing guis.
- Test in-game: select a pinned character → open editor → click track buttons → verify perks in
  the vanilla dynasty window.

**Deliverable:** functional editor for all vanilla tracks. ~1-2 hours of work.

---

## Phase 2 — Polish

- [ ] "Dynasty to Copy" feature: buttons per track that copy the *copy-dynasty's* perk count:
      ```paradox
      # pseudo: for each perk 1..5, if copy-dynasty has it and target doesn't → add
      ```
      Needs the `_copy` variables you already built.
- [ ] Renown display already works (`Dynasty.GetPrestige`) — optionally add a
      `add_dynasty_prestige = 5000` cheat button next to the grid.
- [x] ~~Remove-last-perk~~ — `remove_dynasty_perk = <key>` confirmed in effects.log; implement
      right-click remove walking the track backwards.
- [ ] Localization for all buttons/tooltips (follow `DI_l_english.yml` conventions).
- [ ] Clean up dead code (see cleanup list in DYNASTY_PERK_EDITOR_OPTIONS.md).

---

## Phase 3 — Modded legacy compatibility (the "dynamic" wish, approximated)

> **To answer the "when does the list regenerate" question directly:** the hardcoded effect/GUI
> files are ordinary mod files — the game reads them **at startup, exactly like vanilla reads its
> own** `common/dynasty_perks/`. There is **no separate script that runs at game start**. The only
> manual step is re-running the *generator* (a PowerShell tool on your PC, not part of the mod)
> when your mod list changes; it rewrites the mod files, and the next game launch picks them up
> automatically. In-game, everything is instant and native.

Script can't enumerate, but **we can generate the effect file**. Two approaches:

### 3a. Generator script (recommended)
Write a small PowerShell script (`tools/generate_perk_effects.ps1`, not shipped with the mod) that:
1. Scans `H:\SteamLibrary\...\game\common\dynasty_perks\*.txt` **plus all installed mods'**
   `common/dynasty_perks/*.txt` (IronyModManager knows the active load order)
2. Extracts every `perk_key` + its `legacy = <track>` association
3. Emits `DI_dynasty_perk_effects.txt` and the GUI button grid automatically

Re-run it when you add/change mods. This gives you "all available legacies including mods"
without runtime enumeration — the list is computed at build time instead.

### 3b. AGOT-specific note
The AGOT submod likely adds its own legacy tracks — when you play AGOT, run the generator with
the AGOT mod folder included and ship an AGOT variant of the effects file (same pattern the
AGOT-modifications repo already uses for other overrides).

---

## 🔑 New finding — the console `run` mechanism (possible true-dynamic path)

While researching the "Gain all Dynasty Legacies" cheat (the one that leaves renown negative),
it turned out to be a **hardcoded C++ console command** (`gain_all_dynasty_perks`) — not script.
It grants all perks **without deducting renown** (renown goes negative per your screenshot), which
confirms the console path bypasses costs entirely.

More interesting, vanilla's debug console window reveals:

```paradox
onclick = "[ExecuteConsoleCommand('run run.txt')]"
# tooltip: "LMB to execute script in run.txt, LMB+Shift: run_shift.txt, RMB: run_rmb.txt ..."
```

- The console `run` command executes a Paradox script file from the CK3 user folder
  (`Documents/Paradox Interactive/Crusader Kings III/run.txt`).
- `ExecuteConsoleCommand(...)` is callable from **any GUI** — so a mod button can trigger it.
- **Limitation:** every vanilla usage passes a *static string* — there is no evidence
  `ExecuteConsoleCommand` accepts dynamic arguments (e.g. concatenating a scope's dynasty ID).
  So we cannot pass the selected dynasty through this path from GUI alone.

**Possible use:** a "Gain ALL legacies (incl. mods)" button that runs a *generated*
`run.txt`-style file listing every `add_dynasty_perk` for the player's dynasty — but since the
console commands act on the *player's* dynasty and can't take our selected-dynasty argument,
this only covers the player dynasty and adds little over Phase 1. Parked unless dynamic args
are ever confirmed.

**Conclusion unchanged:** Phase 1 (scripted `add_dynasty_perk` + refund) targeting the selected
dynasty via `scope:DI_dynasty_selected_dynasty` remains the right core; Phase 3a's generator
covers modded tracks.

---

## Appendix — Vanilla legacy tracks (20)

| Track key | Source |
|---|---|
| `warfare_legacy_track` | base |
| `law_legacy_track` | base |
| `guile_legacy_track` | base |
| `blood_legacy_track` | base |
| `erudition_legacy_track` | base |
| `glory_legacy_track` | base |
| `kin_legacy_track` | base |
| `ep1_culture_legacy_track` | EP1 (Culture) |
| `ep2_activities_legacy_track` | EP2 (Activities) |
| `fp1_adventure_legacy_track` | FP1 (Northern Lords) |
| `fp1_pillage_legacy_track` | FP1 (Northern Lords) |
| `fp2_urbanism_legacy_track` | FP2 (Iberia) |
| `fp2_coterie_legacy_track` | FP2 (Iberia) |
| `fp3_khvarenah_legacy_track` | FP3 (Legacy of Persia) |
| `ce1_legitimacy_legacy_track` | CE1 (Legitimacy) |
| `mpo_nomad_legacy_track` | MPO (Khans of the Steppe) |
| `ep3_administrative_legacy_track` | EP3 (Administrative) |
| `tgp_southeast_asia_legacy_track` | TGP (Wandering Lords?) |
| `tgp_japan_legacy_track` | TGP |
| `tgp_china_legacy_track` | TGP (Celestial Legacy) |

Perk keys: `<prefix>_legacy_<1..5>` — e.g. `warfare_legacy_1`, `fp1_adventure_legacy_3`,
`tgp_china_legacy_5`. Verify exact keys per track in `common/dynasty_perks/*.txt` when writing
effects (105 perks total in vanilla).

## Appendix — Verified script API

| Effect/Trigger | Verified in | Notes |
|---|---|---|
| `add_dynasty_perk = <perk_key>` | `00_mongol_invasion_effects.txt` | Works in `dynasty` scope; **deducts renown** (compensated in Mongol event by `add_dynasty_prestige = 10000`) |
| `has_dynasty_perk = <perk_key>` | `varangian_events.txt`, `artifact_events.txt` | Trigger, usable in `dynasty` scope |
| `add_dynasty_prestige = <n>` | `00_mongol_invasion_effects.txt` | Renown add — usable as refund |
| `add_dynasty_prestige_level = <n>` | `00_mongol_invasion_effects.txt` | |
| `Dynasty.GetPrestige` / `GetNextPerkCost` / `GetNextPerkProgress` | vanilla GUI | Already used in your editor window |
| `Dynasty.GetNumberOfLegacies` | `window_ledger.gui` | Returns count only — not an iterable list |
| ~~`every_dynasty_perk`~~ / ~~`Dynasty.GetLegacies`~~ | searched, not found | Runtime enumeration NOT possible |

---

## How the game builds the modded legacy list (and why we can't emulate it at runtime)

The engine scans `common/dynasty_perks/` and `common/dynasty_legacies/` **from all loaded mods
and vanilla at startup**, merging them into an internal registry. That registry is exposed to GUI
only through two engine-owned view-models:

- `DynastyView.GetLegacies` (legacy window)
- `DynastyHouseView.GetLegacies` (dynasty house window)

Both are created by the C++ side when their game view opens — they cannot be constructed from
script or referenced from a modded window's datacontext. There is no `every_dynasty_perk` script
iterator either. **Runtime emulation is therefore not possible with current script/GUI APIs.**

The practical equivalent is **build-time enumeration** (Phase 3a in this doc): a generator script
scans the same `common/dynasty_perks/*.txt` files the engine scans — including every installed
mod's copy — and emits the hardcoded effects/GUI. Same result as dynamic, just refreshed by
re-running the generator instead of being live.
