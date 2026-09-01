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

> **v4 (2026-08-31 audit).** Implementation audit findings:
> - **FIXED — scope bug in generated toggles:** the free-mode `add_dynasty_prestige` top-up
>   was emitted at root *character* scope, but the effect is dynasty-scope only. `error.log`
>   confirmed `Inconsistent effect scopes (character vs. dynasty)` for **every generated
>   toggle** (~110 load errors). Generator template fixed (top-up moved inside
>   `var:DI_dynasty_selected_dynasty`, gated via `root = { has_variable = ... }`) and files
>   regenerated. **Action: relaunch once and confirm these errors are gone from error.log.**
> - **DLC trees ARE handled correctly** (the main worry — verdict: fine):
>   - All DLC legacy/perk definitions live in `game/common/` and load for **everyone**
>     regardless of ownership — perk keys are always defined, so `has_dynasty_perk` /
>     `add_dynasty_perk` on DLC perks **never errors** for users without the DLC. The
>     `HasDlcFeature(...)` row-hiding is cosmetic parity with vanilla, not error prevention.
>   - Vanilla gates tracks exactly the way the generator does: `is_shown = { has_dlc_feature
>     = X }` in `common/dynasty_legacies/*.txt` (verified in all 10 DLC files), and vanilla GUI
>     itself uses `HasDlcFeature('...')` (verified in `frontend_bookmarks.gui`). The
>     generator's gate parsing matches vanilla's own pattern — this is the idiomatic approach.
>   - Gate→track attribution verified correct, including the edge cases: single-line
>     `is_shown` blocks (99_legacies.txt), the commented-out gate in 97_ep1_legacies.txt
>     (correctly ignored), and 94_ce1_legacies.txt having two differently-gated tracks
>     (`ce1_heroic_track` → `legends`, `ce1_legitimacy_legacy_track` → `legends_of_the_dead`).
>   - Note: `HasDlcFeature`/script `has_dlc_feature` check the **host's** DLC — irrelevant in
>     single player, correct behavior in multiplayer.
>   - Design choice to consider: hidden DLC rows mean a user without Northern Lords *can't*
>     cheat in pillage perks, even though the script would allow it (keys defined). Optional:
>     a "show DLC-gated tracks" window toggle. Your call — vanilla parity is the safer default.
> - **Appendix track table was wrong** (real keys differ, 21 tracks not 20) — see corrected
>   note in the appendix. The generator reading real files is exactly why this doesn't matter.
> - Minor: generator log line referenced `$tracks` before it was built — fixed.

> **v5 (2026-09-01, in-game test results).**
> - **`add_dynasty_perk` renown deduction CONFIRMED in-game** (cost varies per perk, matching
>   `250 + 500 × total owned`). The flat +2750 top-up was replaced by an **exact pre-grant
>   refund** via generated script value `DI_dynasty_perk_cost_next`
>   (`common/script_values/DI_generated_perk_values.txt`): 250 base + 500 per owned perk using
>   the auto-generated `<track>_legacy_track_perks` triggers. Net renown change ≈ 0 → **no
>   splendor level inflation** (splendor tracks current prestige, per the user's own earlier
>   observation that re-adding prestige pushes the level back up).
> - **Buttons now vanilla-styled** (`DI_ce_present_dark_button` family): track icon
>   (`gfx/interface/icons/dynasty/<track>.dds` — verified to exist in vanilla), localized perk
>   names via `<perk_key>_name` loc keys, track headers via `<track>_name`/`<track>_desc`.
>   Note: perks have **no** `_desc` loc keys (vanilla builds perk tooltips in C++); button
>   tooltips fall back to the perk name for now. `fp3_persianate_legacy_track.dds` is an
>   orphaned vanilla icon with no track/perk defs — correctly ignored by the generator.
> - **Layout overlap fixed:** the grid was in a floating overlay widget (`margin_top = 150`)
>   over the header/selector; scrollbox moved into the main vbox flow. Also fixed earlier:
>   inverted free-mode toggle button, free mode now defaults ON at window open (`default`).
> - **Open test item:** does `remove_dynasty_perk` refund renown? If yes, toggling a perk off
>   gains renown — check in-game and compensate if unwanted.

> **v6 (2026-09-01, second in-game test).**
> - **Click semantics split (user requirement):** left click = add, right click = remove,
>   inapplicable direction is a no-op. Perk buttons grey out when owned (the add scripted
>   gui's `is_shown` = `NOT has_dynasty_perk`, surfaced via `GetScriptedGui(...).IsValid` —
>   the mod's standard enabled pattern). This also gives owned-state visual feedback for
>   free, solving the old "can't show owned state" limitation.
> - **Per-track buttons added** (user request): each track header has a "Track" button —
>   left click unlocks all missing perks in the track, right click removes all owned.
>   Effects skip already-in-target-state perks so renown is only touched on real grants.
> - **Loc mystery solved ("only Bureaucrats loaded"):** the AGOT-replace theory was WRONG
>   (user wasn't running AGOT; AGOT's replace file keeps the vanilla keys anyway). Actual
>   cause: **bare loc keys in modded GUI `text =`/`tooltip =` properties don't resolve** —
>   vanilla never does that; its keys are only reached via `$key$` loc links or
>   `GetDynastyPerk(...).GetName` (C++ path). "Bureaucrats" was the single exception because
>   it's the only perk whose name also appears in a `*_modifier` loc key rendered through a
>   working text path elsewhere. **Fix: the generator now emits
>   `[Localize('<perk>_name')]` explicitly** for all button text/tooltips and track headers.
>   Fallback if Localize misbehaves: generate `DI_perk_<key>_name: "$<key>_name$"` loc keys.
>   (Side note: AGOT does ship `localization/replace/english/dynasty_legacies/legacies_l_english.yml`
>   which wholesale replaces vanilla's base legacy loc when AGOT IS loaded — keep in mind
>   for the AGOT sub-mod; it renamed `blood_legacy_5_name` → "Old Kings".)
> - **Splendor note (SUPERSEDED by v6.1):** there is NO `set_dynasty_prestige` effect
>   (checked effects.log) — only `add_dynasty_prestige`. ~~splendor tracks current prestige~~
>   WRONG, corrected in v6.1: splendor tracks **lifetime earned** prestige.
> - Tooltip limitation stands: perks have no `_desc` loc keys (C++-built tooltips), button
>   tooltip = perk name. Perk *effect* text could be added later via custom loc calling
>   `GetDynastyPerk('<key>').GetEffectDescription` if desired.
> - **CRASH FIX (same day):** `flowcontainer` rejects `hbox`/`vbox` roots as direct children
>   (`pdx_gui_container.cpp:142`, crash on map load). `DI_ce_present_dark_button` is an hbox →
>   added `DI_ce_present_dark_widget_button` (identical but widget-rooted) in
>   `DI_char_editor_templates.gui`; the generator now uses it for perk buttons.
> - **v6.1 (same day, test 3):**
>   - Perk buttons unclickable → the `enabled=` greying inside the button was disabling its
>     own hit area; fixed by putting `button_ignore = none` on the widget wrapper.
>   - Free mode default → widget `default=` never fired; moved to the window's `_show`/`_hide`
>     state `on_start` (ON at open, OFF at close), which is the reliable lifecycle hook.
>   - **Splendor CONFIRMED to track lifetime earned prestige, not current balance:** user
>     observed level increasing with renown flat at -6133. Net-zero refund keeps the
>     *balance* flat but splendor still climbs (+cost then -cost = lifetime gain). There is
>     no `set_dynasty_prestige` and no splendor-agnostic grant — a truly splendor-neutral
>     free mode is impossible via script; the editor's free mode is therefore defined as
>     **renown-cost-free, not splendor-free**. Noted in the cheat-mode tooltip.
> - **v6.2 (same day, test 4):**
>   - **Template+blockoverride buttons abandoned.** The `DI_ce_present_dark_*_button` family
>     lost right-clicks and clicks entirely (button_standard_clean + blockoverride appears to
>     mishandle input). Perk buttons switched to the mod's proven pattern — plain
>     `button_standard` with inline icon+text content, `onclick`/`onrightclick`/`enabled`
>     directly on the button (as in the skills tab / title manager). `DI_ce_present_dark_
>     widget_button` kept in the templates file but no longer used by the generator.
>   - Top controls consolidated into one fixed-size row after the header (free-mode toggle
>     210px + splendor label/−1/+1/reset) — the previous expanding rows spread buttons across
>     the full window width.
>   - Reminder: GUI changes need a game restart; testing without one shows stale UI.

> **v7 (2026-09-01, end-of-day status — CURRENT STATE)**
>
> **✅ Working (user-confirmed in-game):**
> - Per-perk buttons: left click adds, right click removes, owned perks grey out
>   (`enabled` = add sgui's `is_shown` via `IsValid`)
> - Track buttons: left click unlocks whole track, right click locks whole track
> - Perk/track names and icons render (via explicit `[Localize('<key>_name')]`)
> - Cross-dynasty selection (char picker → `DI_dynasty_selected_dynasty`) works
> - Free mode: renown stays flat (exact pre-grant refund), defaults ON at window open,
>   OFF at close (state `on_start` hooks), toggleable mid-session
> - Splendor editor row: +1/−1/Reset-to-0 via `add_dynasty_prestige_level`
> - Window scrolls; all 21 tracks reachable
>
> **⚠️ Known limitations (by design / unfixable via script):**
> - Splendor level creeps up in free mode even with exact refunds — it tracks *lifetime
>   earned* prestige and `LEVEL_DROP_MAX_RETAINED_PROGRESS_PRESTIGE = 0.5` makes drops
>   asymmetric. No script fix exists (no `set_dynasty_prestige`); the splendor row is the
>   user-side correction. Vanilla's own scripted precedent (Mongol event) is *sloppier*
>   (brute-force +10000 renown + 5 levels).
> - Perk tooltips = perk name only. **v8: effect tooltips confirmed IMPOSSIBLE** — the only
>   effect-text API is `DynastyPerk.GetEffectDescription(GetPlayer)` (vanilla cooltip.gui),
>   which requires a DynastyPerk *datacontext*. That context comes only from engine-bound
>   datamodels (`DynastyView.GetLegacies` / `DynastyLegacy.GetPerks`), and there is no
>   `GetDynastyPerk(key)` global lookup, no Dynasty→Legacy promotion, and no `_desc` loc keys
>   (effect text is C++-built). The earlier "custom loc" idea is dead. Perk-name tooltips stay.
> - Owned state = greyed button only; no per-perk tooltip count/checkmark.
>
> **❓ Not yet re-tested after latest changes (restart pending at time of writing):**
> - Window at 50% width (was 80%, ~40% dead space)
> - Controls consolidated top-left; header shows selected dynasty's name via loc key
>   `DI_dynasty_perks_editor_heading` = `"[Dynasty.GetNameNoTooltip|U] Dynasty — Legacy
>   Perk Editor"`
> - Dead `dynasty_legacies_container` overlay widget removed (it caused the original
>   overlap bugs)
>
> **📋 Next steps, in priority order:**
> 1. **Restart + regression pass:** verify the v7 layout (50% width, control bar, dynasty
>    name in header) and re-confirm clicks/track buttons still work after the layout rework.
>    Also answer the last open test-matrix item: does `remove_dynasty_perk` refund renown?
>    (If yes, toggling off gains renown → add a compensating deduction.)
> 2. **Out-of-order grant check** (plan test matrix item #1): click a tier-3 perk with 0
>    owned — confirm scripted grants ignore track order (expected) or handle if not.
> 3. **Trait-selection perk check** (item #2): `blood_legacy_4` (Architected Ancestry) —
>    scripted grant behavior unknown (default trait / nothing extra / error).
> 4. **Phase 2 polish:** localization pass for other languages (only english has the new
>    keys); silence the `DI_dynasty_selected_*_copy` "set but never used" warnings (comment
>    out setters in `DI_dynasty_selected_char_copy` until the copy feature is built); the
>    explanation text loc (`DYNASTY_VIEW_SHOW_LEGACY_EXPLANATION_*`) hardcodes the *player's*
>    dynasty — consider a DI-owned loc with the selected dynasty's name.
> 5. **Phase 3:** the Mod Support Generator (`tools/generate_mod_perks.ps1`) — DRAFT spec
>    below, user to add more specifications before implementation.
> 6. **Workshop readiness:** the `is_shown`-driven greying means the editor needs no
>    compat patches for vanilla; sub-mods only needed for modded tracks (Phase 3).

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

#### Open questions — RESOLVED (v8 research, 2026-09-01)

- [x] **Playset formats (verified on this machine):**
  - Paradox launcher playsets exist as **plain JSON** in `<CK3 user folder>/playsets_backup/`:
    `{"game":"ck3","name":"...","mods":[{"displayName","enabled","position","steamId"}]}`.
    Trivially parseable with `ConvertFrom-Json`. (The modern launcher's own storage is
    elsewhere/SQLITE, but the user folder JSONs are current — one was written 2 days ago —
    and are the same format Irony exports. Support the JSON dir as the primary source.)
  - Irony Mod Manager was not found under standard `%APPDATA%` paths on this machine —
    the JSON playsets above cover the same need. Irony support = accept its JSON exports
    via `-PlaysetFile <path>` if a user has them.
- [x] **Window inclusion mechanism — DECIDED (extension-slot pattern):**
  - CK3 types/templates are **global across load order, name-keyed, last-loads-wins**.
  - The base window keeps instantiating `di_generated_perk_grid` (vanilla rows, from the
    vanilla generator). The base ALSO defines `di_perk_grid_extension` — an **empty vbox
    type** — and instantiates it right below the vanilla grid.
  - Standalone sub-mods / combined playset mods **redefine `di_perk_grid_extension`** with
    their rows. Base behavior unchanged when absent (empty slot renders nothing); with a
    sub-mod enabled, its rows appear after the vanilla ones. No base-mod edit needed per
    sub-mod; N slots not needed — one extension type suffices (only one mod can win the
    name anyway, which is exactly the combined-mod model).
  - Verified: types need no `scripted_widgets` registration; any loaded gui file's types
    are global. AGOT parser test passed: **158 perks / 38 tracks** (105 vanilla + 53 AGOT).
- [x] **Naming:** standalone sub-mods get prefix from the source mod
  (`DI_perk_add_agot_*`, type `di_perk_grid_extension` — shared name is intentional and
  IS the inclusion mechanism). Combined playset mods emit the full extension grid in one file.
- [x] **Descriptor dependencies:** standalone sub-mods declare
  `dependencies = { "<Perk Mod Name>" }` (launcher orders after the perk mod). Combined
  playset mods declare dependencies on all source perk mods present in the playset.
- [x] **UI:** interactive terminal menu (numbered lists, y/n prompts) with CLI flags as
  escape hatch — no WinForms; keeps the tool dependency-free PowerShell.

> **Status: spec ready for implementation. Remaining user additions still welcome —
> implement incrementally.**

### Implementation order (v8)

1. **Extension slot in base mod** — add empty `di_perk_grid_extension` type + instantiation
   below the vanilla grid in `DI_dynasty_perk_editor.gui`; vanilla generator emits it.
2. **F1 scanner** — `tools/generate_mod_perks.ps1 -Scan`: enumerate local `mod/` +
   Workshop dirs, resolve names via `ugc_*.mod`, report perk/track counts (parser already
   validated against AGOT).
3. **F3 standalone mode** — `-Mod <name>`: generate one sub-mod (sgui + grid extension +
   loc + descriptor with dependencies), auto-register `.mod` in `mod/`.
4. **F4 playset mode** — `-Playset <name|path>`: read playset JSON, scan its enabled mods,
   emit ONE combined mod with the full extension grid.
5. **F2 interactive menu** — default no-args run: scan → list → pick → choose output mode.
6. **Community guide** — `docs/ADDING_PERK_MOD_SUPPORT.md`.

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

## Appendix — Vanilla legacy tracks

> ⚠️ **v4 correction:** this hand-written table was inaccurate — the generator (which reads
> the real files) found **21 tracks / 105 perks**, and several key prefixes differ:
> `ce1_heroic_track` exists (5 perks, gate `legends`), and the TGP tracks are actually
> `tgp_chinese_legacy_*`, `tgp_japan_legacy_*`, `tgp_sea_legacy_*` (not `tgp_china_` /
> `tgp_southeast_asia_`). **Trust the generated files, not this table.** Keeping the table only
> as a rough orientation of which DLC owns which track.

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
