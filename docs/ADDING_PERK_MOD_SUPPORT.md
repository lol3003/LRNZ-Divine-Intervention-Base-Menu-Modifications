# Adding Perk Mod Support — User Guide

This guide covers the **DI Mod Support Generator** — how to make the Dynasty Perk Editor
work with mods that add their own dynasty legacies/perks (e.g. Hiraeth, A Game of Thrones,
Princes of Darkness, Elder Kings 2, …).

---

## 1. How it works (short version)

The **base DI mod** provides the vanilla perk editor. Perk mods (Hiraeth, AGOT, …) each add
their own dynasty perks to the game, but the editor doesn't know about them yet. This tool
**generates a "DI Perks" compatch**: a small mod that adds cheat toggles for those modded
perks into the editor window.

> **Important — one compatch per modlist.** The editor window has room for **one** DI Perks
> compatch. If you want several perk mods' perks shown together, **combine them into one
> compatch** (the recommended path below). Do **not** enable two separate DI Perks compatches
> at the same time — only one will show.

---

## 2. The tools (what's what)

| File                               | Purpose                                                                                      |
| ---------------------------------- | -------------------------------------------------------------------------------------------- |
| `tools/generate_mod_perks.ps1`   | **The tool you use.** Scans your mods and generates compatches.                        |
| `tools/generate_perk_editor.ps1` | Generates the**vanilla** perk grid (ships in the base mod; re-run after game patches). |
| `tools/_perk_parser.ps1`         | Shared parser used by both generators.                                                       |

You run these in **PowerShell** (`pwsh`). Example:

```powershell
pwsh -File tools/generate_mod_perks.ps1 -Scan
```

---

## 3. Step 1 — Find your perk mods

```powershell
pwsh -File tools/generate_mod_perks.ps1 -Scan
```

Lists every installed mod that contains `common/dynasty_perks`, with perk/track counts:

```
Perks  Tracks  Mod
-----  ------  ----
130    17      Hiraeth - Dynasty Legacies Overhaul
128    32      A Game of Thrones
445    89      Princes of Darkness
```

> The tool reads your installed mods from the Paradox launcher registry
> (`mods_registry.json`), so Workshop mods you've installed are found automatically.

---

## 4. Recommended — Combined compatch from a Playset (several mods at once)

If your current playset contains the perk mods you want (Hiraeth + AGOT + …), generate ONE
combined compatch for the whole playset:

```powershell
pwsh -File tools/generate_mod_perks.ps1 -Playset "Your Playset Name"
```

- It reads the playset's enabled mods from the launcher.
- It merges all their **new (non-vanilla)** perks into one compatch.
- Output lands in `mod/DI Perks - <Playset Name>/` and is auto-registered with the launcher.
- It writes a **manifest** (`README_DI_perks.txt`) listing exactly which perk mods are inside.

**Example:**

```powershell
pwsh -File tools/generate_mod_perks.ps1 -Playset "IronyModManager"
```

```
Combined: 98 new perks / 33 tracks from 2 mod(s).
Wrote combined compatch to ...\mod\DI Perks - IronyModManager
```

### Combine an explicit list (no playset needed)

```powershell
pwsh -File tools/generate_mod_perks.ps1 -PlaysetMods "Hiraeth;A Game of Thrones" -CombinedName "DI Perks HAGOT"
```

Separate mod names with `;` or `,`. Each name is matched against your installed mods.

---

## 5. Alternative — a single compatch for ONE perk mod

```powershell
pwsh -File tools/generate_mod_perks.ps1 -SubMod "Hiraeth"
```

Generates a compatch for just that one mod: `mod/DI Perks - Hiraeth - Dynasty Legacies Overhaul`.

Use this when you only want one extra perk mod in the editor (and are sure you won't run
another DI Perks compatch alongside it).

---

## 6. The interactive menu

Run with **no arguments** to get a menu-driven flow:

```powershell
pwsh -File tools/generate_mod_perks.ps1
```

```
DI Dynasty Perk Editor - Mod Support Generator
====================================================
Perks  Tracks  Mod
-----  ------  ----
130    17      Hiraeth - Dynasty Legacies Overhaul
...
Choose an action:
  1) Generate ONE combined compatch from ALL listed perk mods
  2) Generate a standalone compatch for a single perk mod
  3) Generate from a Playset (recommended for a modlist)
  q) quit
```

Pick a number, answer the prompts, done.

---

## 7. Useful flags

| Flag                                               | Meaning                                                          |
| -------------------------------------------------- | ---------------------------------------------------------------- |
| `-WhatIf`                                        | Dry-run: shows what would be generated without writing anything. |
| `-TargetFolder "C:\path"`                        | Emit the compatch into a specific folder instead of`mod/`.     |
| `-CombinedName "Name"`                           | Name for a combined compatch (defaults to the playset name).     |
| `-Verbose`                                       | Extra detail.                                                    |
| `-GameDir` / `-UserFolder` / `-ModsRegistry` | Override paths if your install differs.                          |

---

## 8. After generating — in the game

1. **Restart CK3** so the launcher sees the new compatch `.mod`.
2. In the launcher, **enable** the generated `DI Perks - …` compatch **and** the perk mod(s)
   it supports (e.g. Hiraeth, AGOT) **and** the base DI mod. The descriptor declares these
   dependencies, so the launcher orders them correctly.
3. Launch, open the **Dynasty Perk Editor**, and you'll find the modded perks' toggles
   below the vanilla grid (left click = add, right click = remove).

---

## 9. Troubleshooting

- **"No new (non-vanilla) keys"** — every perk in that mod already exists in vanilla (or is
  a rename), so there's nothing new to toggle. Nothing to generate.
- **Only one compatch shows** — you enabled two DI Perks compatches. Remove one, or combine
  them (Section 4).
- **A perk's button shows a raw key name** — the perk mod doesn't ship localization for that
  key; it still works, it just shows the technical name.
- **Cheat grants cost renown / splendor** — the free-mode refund keeps renown flat, but
  splendor tracks *lifetime earned* prestige (a game mechanic, no script fix).

---

## 10. A note on file collisions

The game **merges** perk data from every loaded mod, so Hiraeth's and AGOT's perks coexist
fine even when both ship a `00_dynasty_perks.txt` (that's normal — later-loaded ones replace
only the overlapping keys). The generator reads by **perk key**, not filename, so it is safe
regardless of whatever `*_dynasty_perks.txt` filenames your mods use. You never have to worry
about "two expansion_1 files".
