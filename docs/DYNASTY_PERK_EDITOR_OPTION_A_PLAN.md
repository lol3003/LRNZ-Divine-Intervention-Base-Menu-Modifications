# Dynasty Perk Editor — Option A Plan (Hybrid: reuse vanilla's legacy window)

> Companion to `DYNASTY_PERK_EDITOR_PLAN.md` (hardcoded-grid plan). This doc explores the
> alternative: **override vanilla's `window_dynasty_legacy.gui`** so its fully dynamic,
> mod-inclusive legacy tree can be used as the editor itself.
>
> Main motivation: **Workshop shareability** — no generator script, no per-mod compatibility
> patches. The tree renders whatever legacy tracks exist at runtime, from any mod.

---

## Why this is attractive

Vanilla's `window_dynasty_legacy.gui` (490 lines) already does everything the editor needs:

- **Fully dynamic** — `datamodel = "[DynastyView.GetLegacies]"` renders every track, including
  all mod-added ones, automatically. Zero maintenance when mods change.
- **Full tree UI** — perks, icons, tooltips, progress pips, trait selection popup — all native.
- **Openable for any dynasty** — `OpenGameViewData('dynasty_legacy_window', Dynasty.GetID)`
  accepts an arbitrary dynasty ID (verified: `window_dynasty_house.gui` uses exactly this to
  jump to other dynasties' trees).

The DI selection UI you already built (char picker → `DI_dynasty_selected_dynasty` variable)
plugs straight into this.

---

## Research findings (verified in game files)

### How the window works

| Concern | Mechanism | File:line |
|---|---|---|
| Dynasty binding | `datacontext = "[DynastyView.GetDynasty]"`, opened via `OpenGameViewData('dynasty_legacy_window', Dynasty.GetID)` | `window_dynasty_legacy.gui:7`, `window_dynasty_house.gui` |
| Track list | `datamodel = "[DynastyView.GetLegacies]"` | :172, :197 |
| Perk list per track | `datamodel = "[DynastyLegacy.GetPerks]"` | :378 |
| Buy button | `onclick = "[DynastyView.SelectPerk( DynastyPerk.Self )]"` | :388 |
| Buy gating | `enabled = "[DynastyView.CanSelectPerk( DynastyPerk.Self )]"` | :387 |
| Already-owned check | `visible = "[Not( Dynasty.HasPerk( DynastyPerk.Self ) )]"` | :386 |
| Dynast-only text | `visible = "[GetPlayer.IsDynast]"` vs `Not(GetPlayer.IsDynast)` | :129, :138 |

### The two blockers (and their workarounds)

**Blocker 1 — `CanSelectPerk` disables buying for non-player / non-dynast cases.**
The loc confirms intent: *"You are not the dynast so you cannot spend renown to unlock Legacies."*
When you open another dynasty's tree, buttons are disabled.

**Blocker 2 — `DynastyPerk` exposes almost nothing to script.**
Only `GetNameNoTooltip`, `GetEffectDescription`, `Self`. **No `GetKey`, no scope link** (checked
`event_targets.log`). So a modified `onclick` **cannot tell our script which perk was clicked** —
we cannot replace the buy logic with our own scripted gui per-perk.

### The workaround that makes Option A viable

**Keep vanilla's own `DynastyView.SelectPerk` as the purchase mechanism** and simply override the
`enabled` condition. The override file changes:

```paradox
# vanilla:
enabled = "[DynastyView.CanSelectPerk( DynastyPerk.Self )]"
# mod override:
enabled = "[Not( Dynasty.HasPerk( DynastyPerk.Self ) )]"
```

If the engine's `SelectPerk` does not re-validate dynast/renown internally (unknown — needs an
in-game test), this single change turns the tree into a free editor for **any** dynasty, with
**all modded tracks**, zero generator, zero compat patches.

⚠️ **This is the one unknown that decides everything** — see Test 1 below.

---

## How much of the window UI can we edit? (answer: essentially all of it)

Copying the file into the mod gives **total freedom over layout, widgets, text, and behavior** —
it's a full replacement, not a patch. Concretely:

| What | Editable? | Notes |
|---|---|---|
| Layout, size, position, styling | ✅ fully | It's our file now |
| Add new widgets (portraits, buttons, panels) | ✅ fully | Can embed the `DI_Dynasty_Select_Character` template, DI buttons, etc. |
| `visible` / `enabled` conditions | ✅ fully | This is the `CanSelectPerk` bypass |
| Text / localization | ✅ fully | |
| `onclick` behavior | ⚠️ partially — see below | The data you can pass to script is the limit |

**Adding your portrait character switcher: yes, easily.** The window is just a widget tree; you can
drop in `using = DI_Dynasty_Select_Character` (your existing template) or any DI widget, plus
`GetVariableSystem` toggles, scripted-gui buttons, whatever. The only thing to keep in mind is that
the window's root datacontext is `[DynastyView.GetDynasty]` — your added widgets can use their own
`datacontext` lines (like your editor window does with `GetPlayer.MakeScope.Var(...)`) to access
DI variables. Your existing UI being "based on it anyway" makes this trivial.

## Why can't we just change what clicking a perk button does?

Because of **what the button is allowed to tell script**, not because of the click itself:

1. Changing `onclick` is trivial — e.g. `onclick = "[GetScriptedGui('DI_x').Execute(...)]"`.
2. The problem is the **arguments**. Our script effect needs to know *which perk* to grant
   (`add_dynasty_perk = <key>`). Passing a scope works via `GuiScope.SetRoot(...).AddScope(...)`
   (vanilla does this with `Faith.MakeScope`, `Character.MakeScope`, etc.) — **but that requires
   the object to have a `MakeScope` / scope link.**
3. Verified against the script docs: `DynastyPerk` has **no scope link** (not in
   `event_targets.log`) and exposes only `GetNameNoTooltip`, `GetEffectDescription`, `Self` —
   **no `GetKey`**. `DynastyLegacy` (the track) likewise has no key/scope access.
4. So a clicked perk button cannot communicate "I am `warfare_legacy_2`" to script. The engine's
   `DynastyView.SelectPerk` can do it because it's C++ with direct registry access.

### What this means practically

| Click behavior change | Possible? |
|---|---|
| Enable buying for any dynasty (keep `SelectPerk`) | ✅ — the `enabled` override (Test 1) |
| Add DI widgets/portraits around the tree | ✅ freely |
| Route the click to our own script **per perk** | ❌ no perk key/scope access |
| Route the click to our own script **per track** | ❌ same problem (no track key access) |
| Add separate DI buttons (e.g. "add next perk in <hardcoded track>") alongside the tree | ✅ — those buttons don't need the tree's datacontext |

So the realistic Option A shape is: **vanilla tree (with `enabled` bypass) for viewing + buying,
plus your DI selection UI embedded, plus optional hardcoded DI buttons for features the tree
can't do** (remove-perk, exact renown refund). If Test 1 shows `SelectPerk` re-validates and
refuses for other dynasties, the tree degrades to a viewer and granting falls back to the
hardcoded buttons — the two plans merge rather than compete.



### Test 1 — proof of concept (do this first, ~30 min)

1. Copy `H:\SteamLibrary\...\game\gui\window_dynasty_legacy.gui` into the mod's `gui/` folder.
2. Change the one `enabled` line as shown above (leave everything else identical).
3. Launch, open console (`~`), `effect = { add_dynasty_prestige = 5000 }`, open your dynasty's
   legacy window → confirm buying still works normally (override didn't break the player case).
4. Then open another dynasty's tree (e.g. via the dynasty house view of a vassal's dynasty) →
   check whether the perk buttons are now clickable and whether clicking actually grants the perk.

**Outcomes:**
- ✅ Works → Option A is fully viable, continue with steps below.
- ❌ Buttons clickable but nothing happens / error → engine re-validates; fall back to
  **Option A′** (below) or the hardcoded plan.
- ❌ Buttons still disabled → `enabled` isn't the only gate; inspect `gui_warnings.log` and
  reconsider.

### Step 2 — Integrate with the DI selection flow

- Keep your existing char/dynasty picker (`DI_dynasty_selected_dynasty` variable).
- Add an "Edit Legacies" button in your editor window:
  ```paradox
  onclick = "[OpenGameViewData( 'dynasty_legacy_window',
      GetPlayer.MakeScope.Var('DI_dynasty_selected_dynasty').Dynasty.GetID )]"
  ```
- This opens the (overridden) legacy tree for the selected dynasty.

### Step 3 — Renown handling

If `SelectPerk` deducts renown (likely — same as script `add_dynasty_perk`):
- Simplest: a "Renown +5000" cheat button in the DI editor window
  (`add_dynasty_prestige = 5000`), click before/after buying.
- Fancier: override the cost display or auto-refund — not possible per-click without perk keys,
  so the cheat button is the pragmatic answer.

### Step 4 — Workshop-safe packaging

- The override file lives at `gui/window_dynasty_legacy.gui` in the mod — **no generator, no
  external tools, fully shareable**.
- ⚠️ **Compatibility caveat:** any other mod that *also* replaces `window_dynasty_legacy.gui`
  will conflict (last-in-load-order wins). Legacy-tree UI mods are rare, but check compatibility
  notes before publishing. This is the same conflict class as any UI overhaul mod — normal and
  accepted on the Workshop.

### Step 5 — Optional polish

- Also override the `visible = "[GetPlayer.IsDynast]"` explanation text to show a
  "Divine Intervention editor mode" note.
- Add right-click handling? Not possible per-perk (no key access) — removal stays with
  `remove_dynasty_perk` buttons in the DI window (hardcoded grid, Phase 2 of the other plan),
  or console.

---

## Option A′ — fallback if Test 1 fails

If the engine re-validates inside `SelectPerk`, the override can still change `onclick` — but
since `DynastyPerk` has no key/scope exposure, per-perk script calls are impossible. The remaining
Option A′ shape:

- Override the window to **remove gating** and change each perk button to open a small
  DI confirmation popup that grants via **positional logic**: the button's index within
  `DynastyLegacy.GetPerks` datamodel is knowable in GUI (`GetDataModelSize`/iteration order) but
  there is no clean way to pass it to script either. Practically, A′ collapses into the
  hardcoded-grid plan (`DYNASTY_PERK_EDITOR_PLAN.md`) with the vanilla tree kept as a
  *viewer* via `OpenGameViewData`.

---

## Comparison with the hardcoded plan

| | Option A (this doc) | Hardcoded grid (other doc) |
|---|---|---|
| Modded tracks | ✅ automatic | ⚠️ via generator re-run |
| Workshop shareable | ✅ yes (one file override) | ⚠️ generator is external tooling |
| Add perks to any dynasty | ❓ pending Test 1 | ✅ yes (selected dynasty variable) |
| Remove perks | ❌ not per-perk | ✅ `remove_dynasty_perk` |
| Renown handling | cheat button | exact per-perk refund |
| Maintenance | vanilla file copy (patch-day risk) | self-owned files |
| UI work | ~none (vanilla tree) | build a grid |

**Recommendation:** run Test 1. If it passes, Option A gives you the dynamic, shareable editor
you wanted with minimal effort — and the hardcoded grid can still be added later for
remove-perk and exact-renown features (the two plans are complementary, not exclusive).

---

## References

- Vanilla window: `H:\SteamLibrary\steamapps\common\Crusader Kings III\game\gui\window_dynasty_legacy.gui` (490 lines)
- Open call example: `...\game\gui\window_dynasty_house.gui`
- Script docs: `Documents/Paradox Interactive/Crusader Kings III/logs/effects.log` (`add_dynasty_perk`, `remove_dynasty_perk` — dynasty scope)
- Dynast gating loc: `DYNASTY_VIEW_SHOW_LEGACY_EXPLANATION_NOT_HEAD`
