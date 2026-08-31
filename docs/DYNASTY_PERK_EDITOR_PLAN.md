# Dynasty Perk Editor — Action Plan

> Companion to `DYNASTY_PERK_EDITOR_OPTIONS.md`. This is the concrete "what to do next" plan,
> based on research into the installed game files (patch 1.19, `H:\SteamLibrary\...`).

> **v2 (audit-refined).** Changes vs v1:
> - **Generator-first:** the PowerShell generator (old Phase 3a) is now *Phase 1 step 0* — do
>   not hand-write per-track effects. The grid is per-perk toggles (105 vanilla perks), which
>   makes hand-writing infeasible and the generator non-optional.
> - **Per-perk toggles, not "add next":** the stated goal is *any perk, any time* — so each
>   perk gets its own toggle (add if missing, remove if owned), replacing the sequential
>   `else_if` chain design.
> - **Scope bug fixed in the example:** `add_dynasty_prestige` is a *dynasty-scope* effect
>   (effects.log) — the v1 example placed it in character scope where it would error. It also
>   must run *before* the grant, or the purchase can still fail.
> - **Shipping model decided:** base mod = vanilla tracks only; each perk-mod gets its own
>   sub-mod (AGOT pattern). See "Phase 3 — Shipping modded-track variants".
> - `add_dynasty_perk` renown deduction downgraded from "confirmed" to "likely — verify in the
>   first test" (if script grants bypass costs like the console command, refund logic can be
>   dropped entirely).

> **v3 (2026-08-31).** Test 1 result + generator split:
> - **Option A Test 1 FAILED as predicted:** the gated vanilla-window override enabled every
>   perk button, but `DynastyView.SelectPerk` re-validates prerequisites/renown internally in
>   C++ — clicks were silently ignored. The override was removed; the scripted per-perk toggle
>   grid is the editor (Phase 1 implemented, commits `a6c543f`/`bc18b87`).
> - **Generator split into two tools** (user decision): one for vanilla+DLC perks (shipped in
>   the base mod), one for scanning the user's installed mods / playsets (Phase 3, spec below).
> - Phase 3 rewritten as a full spec with UX flow, output modes, and playset integration —
>   **spec is a draft; user will add more specifications later.**

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

- Works inside a `dynasty` scope → we can target the selected dynasty. **Scope access fix:** the
  selection is stored as a *player-scope variable* (set via `scope:target.set_variable`), so the
  correct script access is `scope:player.var:DI_dynasty_selected_dynasty` (or `var:DI_...` when
  already inside the player scope) — **not** `scope:DI_dynasty_selected_dynasty` (that syntax is
  for `save_scope_as` saved scopes, which this is not).
- ⚠️ **COST WARNING (likely — verify in first test):** `add_dynasty_perk` probably **deducts
  renown** from the dynasty. Confirm with exact before/after renown numbers in the very first
  Phase 1 test — if the script effect turns out to bypass costs (the way the
  `gain_all_dynasty_perks` console command does), the whole refund/top-up design below can be
  dropped.
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

## Phase 0 — Clean the test baseline (do before any Option A testing)

The current WIP has real parser errors that would contaminate any Option A test results
(unrelated `gui_warnings.log` noise). Fix or remove:

- [ ] `gui/DI_dynasty_perk_editor.gui:219` — invalid `GetAllDynasties.GetLegacies` datamodel
      (GetAllDynasties has no GetLegacies). Remove or replace with a working source.
- [ ] `gui/DI_dynasty_perk_editor.gui:236` — invalid top-level `di_confirmation_popup`
      (confirmation popups must be declared inside a window/`confirmation_popup` context).
- [ ] `gui/DI_dynasty_perk_editor.gui:6-8` — three competing root `datacontext` declarations;
      only the last wins. Keep one (the `Var('DI_dynasty_selected_dynasty').Dynasty` one) and
      delete the rest.
- [ ] `gui/DI_misc.gui` copy selector calls `DI_dynasty_select_char_copy` but the defined
      scripted gui is `DI_dynasty_selected_char_copy` — rename one to match (or defer the whole
      copy feature; it's not needed for MVP).
- [ ] Delete dead code: `DI_Dynastey_perk_list` in
      `common/scripted_guis/DI_dynasty_perk_editor_sgui.txt` — this is worse than dead code:
      undefined `scope:legacy` **and** an `if` with no `limit`, i.e. a hard parser error that
      spams `error.log` on every load. Also delete the empty `if = { limit = {...} }` in
      `DI_dynasty_selected_char_copy` and the commented `DI_dynasty_perk_helper`.
- [ ] After cleanup: launch once and confirm `error.log` / `gui_warnings.log` are free of
      dynasty-editor-related entries. That is the clean baseline.

---

## Phase 1 — Core editor: generated per-perk toggles for vanilla tracks (MVP)

**Goal:** Working per-perk toggle buttons (add/remove) for all 105 vanilla perks across the
20 vanilla tracks — all files **generated**, not hand-written.

### 1.0 Write the generator FIRST (do not hand-write effects)

With per-perk toggles (below), the editor needs **one effect + one button per perk** — 105 in
vanilla, more with mods. Hand-writing that guarantees typos. Write
`tools/generate_perk_effects.ps1` (not shipped with the mod) first; it:

1. Scans `H:\SteamLibrary\...\game\common\dynasty_perks\*.txt` (vanilla) — later, any perk
   mod's folder too (Phase 3).
2. Extracts every perk key + its `legacy = <track>` association (+ track order for layout).
3. Emits:
   - `common/scripted_effects/DI_dynasty_perk_effects.txt` — one toggle effect per perk
   - `gui/DI_dynasty_perk_editor_templates/DI_dynasty_perk_grid.gui` — the button grid,
     grouped by track, using the mod's existing button template styling
   - `localization/english/DI_dynasty_perks_l_english.yml` — tooltip loc referencing vanilla
     perk loc keys where possible (perk names/descs already exist in vanilla loc — reuse their
     keys instead of duplicating text)

Then every game/mod-list change is a re-run, not a rewrite.

### 1.1 Per-perk toggle effects (generated, not hand-written)

**Design change (v2):** per-perk toggles instead of per-track "add next perk" `else_if`
chains. Rationale: the stated goal is *any perk, any time, no prerequisites* — a sequential
chain contradicts that. Each perk gets one toggle effect:

```paradox
DI_dynasty_toggle_warfare_perk_1 = {
    scope = character
    effect = {
        # root is the player (SetRoot(GetPlayer.MakeScope) from GUI);
        # the selected dynasty lives in the player's variable storage
        scope:player = {
            var:DI_dynasty_selected_dynasty = {
                if = {
                    limit = { has_dynasty_perk = warfare_legacy_1 }
                    remove_dynasty_perk = warfare_legacy_1
                }
                else = {
                    # free-edit mode: top up renown FIRST, and INSIDE dynasty scope —
                    # add_dynasty_prestige is dynasty-scope only (effects.log), and granting
                    # after the purchase attempt would be too late
                    add_dynasty_prestige = 3000
                    add_dynasty_perk = warfare_legacy_1
                }
            }
        }
    }
}
```

**v1 example bugs this fixes:** the old example put `add_dynasty_prestige` in character scope
(would error — dynasty-scope effect per effects.log) and ran it *after* the grant attempt
(too late if renown was insufficient).

**Renown cost — corrected model (audit finding):** the cost formula is
`250 + TOTAL unlocked dynasty perks × 500` — based on the dynasty's **total** perk count across
all tracks, **not** the perk's position within its own track. Per-track refunds (250/750/…)
are therefore wrong once the dynasty owns perks elsewhere. Options:

- **"Free edit" mode (default):** flat top-up before each grant (as above). Note this inflates
  renown *level* progress — unavoidable, level derives from total prestige gained.
- **"Normal cost" mode:** no top-up; pair with a separate "Renown +5000" button.
  Make the mode a `GetVariableSystem` toggle in the editor window; the generated effect reads
  it via a scripted trigger if both modes are wanted, or just ship free-edit only for MVP.

> If precise cost-neutral granting is ever wanted, the refund must be computed from the dynasty's
> **total** owned perk count (`250 + total_perks × 500`) *before* the grant — countable via the
> auto-generated `<track>_legacy_track_perks` triggers summed across all tracks. Defer unless
> requested; the flat-grant cheat mode is simpler and fits the cheat intent.

**Unknowns to resolve in the first test session (the Phase 1 test matrix):**

1. Does scripted `add_dynasty_perk` allow **out-of-order** grants (perk 3 with 0 owned)?
   If the engine enforces track order even in script, the toggle UI must either grey out
   later perks or fall back to sequential chains. *Decides the final grid design.*
2. **Trait-selection perks** (blood track "Architected Ancestry"-style): does scripted grant
   apply a default trait, grant nothing extra, or error? Handle per findings.
3. Does `remove_dynasty_perk` tolerate removing a perk while later perks in the track are
   owned? (For a cheat tool, arbitrary perk sets are desirable.)
4. Record exact renown before/after — settles the cost question at the top of this doc.

**Bonus from script_docs:** the auto-generated `<track>_legacy_track_perks` triggers (e.g.
`warfare_legacy_track_perks >= 3`) let tooltips show the current perk count per track — and since
these triggers are auto-generated for *every* track (including mod-added ones), any modded tracks
added by the generator automatically get working count tooltips too.

### 1.2 Build the UI (generated grid)
In `gui/DI_dynasty_perk_editor.gui`, replace the placeholder content with the generated grid
(from 1.0) — copy the styling of the lifestyle present buttons (`DI_ce_present_dark_button`
template):

- One button per **perk** (5 per track row): left-click = toggle (add/remove via the 1.1
  effect). Show owned state by stacking two complementary-visibility widgets driven by a
  scripted_gui whose `is_shown` checks
  `scope:player = { var:DI_dynasty_selected_dynasty = { has_dynasty_perk = <key> } }` —
  the mod's existing scripted-gui pattern.
- Track row header: static `texture = gfx/interface/icons/dynasty_legacies/...` per track
  (`DynastyLegacy.GetTrackIcon` won't work without DynastyView).
- Track header tooltip shows current unlocked count via the auto-generated
  `<track>_legacy_track_perks` triggers — dynamic per track, works for modded tracks too.

### 1.3 Wire up
- Register effects as scripted_guis if buttons use `GetScriptedGui(...).Execute(...)` (the mod's
  standard), or call them as scripted_effects from existing guis.
- Test in-game per the unknowns list in 1.1 (out-of-order grant, trait-selection perks, removal
  with later perks owned, exact renown delta), then: select a character → open editor → toggle
  perks → verify in the vanilla dynasty window.

**Deliverable:** generator + functional editor for all vanilla tracks. ~3-4 hours including
the generator and the test matrix (more than v1's 1-2h estimate because the generator is now
front-loaded — it pays for itself the moment modded tracks or regenerations are needed).

---

## Phase 2 — Polish

- [ ] "Dynasty to Copy" feature: buttons per track that copy the *copy-dynasty's* perk count:
      ```paradox
      # pseudo: for each perk 1..5, if copy-dynasty has it and target doesn't → add
      ```
      Needs the `_copy` variables you already built.
- [ ] Renown display already works (`Dynasty.GetPrestige`) — optionally add a
      `add_dynasty_prestige = 5000` cheat button next to the grid.
- [ ] ~~Remove-last-perk~~ — **superseded** by the v2 per-perk toggle design (each perk
      button adds if missing, removes if owned via `remove_dynasty_perk`, confirmed in
      effects.log).
- [ ] Localization for all buttons/tooltips (follow `DI_l_english.yml` conventions).
- [ ] Clean up dead code (see cleanup list in DYNASTY_PERK_EDITOR_OPTIONS.md).

---

## Phase 3 — Shipping modded-track variants (sub-mod pattern)

> **⚠️ v3: This phase is now specified as the "Mod Support Generator" below. The original
> sub-mod rationale (why not bundle everything) still applies and is kept at the end of this
> phase. The spec is a DRAFT — the user will add more specifications later.**

### Phase 3 spec — Mod Support Generator (`tools/generate_mod_perks.ps1`)

> **Status: DRAFT — user will add more specifications. Do not implement until the spec is
> marked final.**

A **second, separate generator** (distinct from the vanilla+DLC generator
`tools/generate_perk_editor.ps1`, which stays as-is and ships in the base mod). Its job:
scan the user's installed CK3 mods, find every mod that adds dynasty perks/tracks, and
generate editor support for them. UX flow and features, in user's words + structure
(order not final):

#### F1 — Scan installed mods for perk content

- Scan all mod locations: `mod/` folder (local mods), Steam Workshop content
  (`steamapps/workshop/content/1158310/<id>/`), and any additional user-specified dirs.
- A mod "adds perks" if it contains `common/dynasty_perks/*.txt` with valid perk blocks
  (reuse the vanilla generator's parser).
- Present results as a list: mod name (from descriptor.mod), workshop ID / path, number of
  perks and tracks found, DLC-gate status of its tracks.
- Handle name resolution: workshop IDs → names via `mod/ugc_*.mod` descriptor files in the
  user folder (the launcher writes these).

#### F2 — User selection: generate for all or a subset

- Interactive menu (or CLI flags for power users): generate for **all detected perk mods**,
  or pick **one/some** via multi-select.
- Show what will be generated before writing (dry-run summary: mods → tracks → perk counts).

#### F3 — Output modes (user chooses per run)

1. **Add to main mod** — write generated files into the base DI mod folder.
   - ⚠️ Caveat to surface in the UI: Steam Workshop updates of the base mod would overwrite
     local changes; users who install the base mod from GitHub are unaffected. (The base mod
     is distributed via GitHub, so this mode is mainly for the maintainer's own install.)
2. **Generate separate standalone mods** (preferred default) — one small mod per perk mod,
   each containing only its generated files (`common/scripted_guis/`, grid `.gui`, loc stubs,
   descriptor with `dependencies = { "<Perk Mod Name>" }`).
   - Each can be independently enabled/disabled in the launcher/playset.
   - Auto-register each generated mod in `mod/` with a `.mod` descriptor so the launcher
     sees it (name pattern: `DI Perks - <Mod Name>`).
3. **Write to a target folder** — emit the generated files into an arbitrary directory so
   they can be dropped into an existing compatch mod by hand.

#### F4 — Playset integration (if feasible)

- Read **Paradox launcher playsets**: `playsets_backup/` and the launcher's own
  `launcher-v2.sqlite` / `game_data.json` in the CK3 user folder (format to be verified —
  research needed; the launcher stores playsets in a SQLite DB, mods per playset in a
  join table).
- Read **Irony Mod Manager playsets**: Irony stores playsets in its own data directory
  (`%APPDATA%/IronyModManager` or similar — format to be verified).
- Let the user pick a playset → the generator scans exactly the mods enabled in that
  playset → generates **one combined mod** containing the editor support for all perk mods
  in that playset (single enable/disable, no per-mod clutter).
- If a playset format can't be parsed reliably, fall back to F2 manual selection.

#### F5 — Shared requirements (inherited from the vanilla generator)

- Same parser, same toggle-effect template, same DLC-gating logic, same free-mode flag.
- Unique type/file naming per generated mod (`-Prefix` derived from the perk mod name) to
  avoid `di_generated_perk_grid`-style collisions when several generated mods are active.
- Idempotent regeneration; "GENERATED FILE" headers; re-run after perk-mod updates.

#### Open questions (to resolve before implementation)

- [ ] Exact playset storage formats (Paradox launcher SQLite schema; Irony export format).
- [ ] Should combined-playset mods get one shared prefix or per-source prefixes?
- [ ] Descriptor `dependencies` for combined mods: depend on all source perk mods?
- [ ] Does the user want a GUI (WinForms/terminal menu) or CLI-flags-only interface?
- [ ] **Window inclusion mechanism:** the base editor window must render each sub-mod's
      grid. Options: (a) base window lists one line per known generated type
      (`di_hiraeth_perk_grid = {}` etc. — requires base mod update per new sub-mod), or
      (b) sub-mods append rows into a shared named container the base window declares.
      Decide when finalizing the spec.
- [ ] **User: more specifications to be added — spec incomplete by design.**

### Why NOT one mod with everything bundled

CK3 tolerates effects referencing undefined keys — **nothing crashes** — but bundling every
perk mod's tracks into the base mod degrades the experience for users without those mods:

| What | Behavior when the perk mod is absent |
|---|---|
| `add_dynasty_perk = <undefined key>` | Error logged, effect does nothing |
| `has_dynasty_perk = <undefined key>` in button `is_shown`/tooltips | Trigger errors → spams `error.log`, potentially every frame for visible buttons |
| GUI `texture = gfx/.../mod_icon.dds` for missing art | Missing-texture warnings in `gui_warnings.log`, placeholder art |
| Buttons for nonexistent tracks | Dead UI clutter |

There is **no script-side way to test "does this database key exist?"**, and files can't be
conditionally included based on the loaded mod list — so a bundle-everything main mod always
produces error spam and dead buttons for someone. Unfixable from within CK3 script.

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

**Conclusion unchanged:** Phase 1 (generated per-perk toggle effects targeting the selected
dynasty via the player's `DI_dynasty_selected_dynasty` variable) remains the right core; the
same generator covers modded tracks via sub-mods (Phase 3).

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

The practical equivalent is **build-time enumeration** (Phase 1.0 in this doc): a generator
script scans the same `common/dynasty_perks/*.txt` files the engine scans — including every
supported perk mod's copy — and emits the toggle effects/GUI. Same result as dynamic, just
refreshed by re-running the generator instead of being live, and shipped as per-mod sub-mods
(Phase 3) so users without those mods see zero errors.
