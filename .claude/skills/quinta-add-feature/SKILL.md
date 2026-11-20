---
name: quinta-add-feature
description: Add, change or remove a feature or setting in Quinta's UI Tweaks (this WoW addon). Use it whenever the user asks for a new tweak, option, alert, slash command or checkbox. It picks the right category in the /quinta window, keeps the two columns balanced, and updates the README, CHANGELOG and TOC. It also covers how to cut a release.
---

# Adding a feature to Quinta's UI Tweaks

Everything lives in `Quinta.lua` (one file) plus `Quinta.toc`, `README.md` and `CHANGELOG.md`.
The `/quinta` window is built from the `SECTIONS` table in `Quinta.lua`. Never place controls by
hand with pixel offsets: add an item to `SECTIONS` and the layout stacks it automatically.

## Categories (keep this list in sync with `SECTIONS`)

| Category | Column | What belongs there |
|---|---|---|
| **General** | 1 (left) | Whole-UI or camera settings that affect everything: scale, camera distance, fonts, etc. |
| **Chat** | 1 | Anything about chat frames, chat visibility or chat behaviour. |
| **Hide until hover** | 1 | Blizzard frames that hide and fade back in on mouseover. Labels are just the frame name ("Bag bar"). |
| **Action bars** | 2 | Action buttons, spells on bars, ranks, bar layout, keybind text. |
| **Group & loot** | 2 | Party/raid tools, markers, loot rolls, loot windows. |
| **Class** | 2 | Alerts or helpers for one class or spec (label names the spell or class). |

### Choosing a category
1. Use an existing category whenever the feature reasonably fits. Read the rules above, then look at
   what's already in `SECTIONS`.
2. Make a **new category** only if the feature clearly fits none of them (e.g. a first map/minimap
   tweak → "Map"). Name it with one or two plain words.
3. Put a new category at the bottom of the **shorter column**. Roughly: a header is 22px, a checkbox
   30, a button 30, a slider 62, and each section gap is 10. If one column ends up much taller
   (more than about 60px), move a whole section to the other column. Never split a section.
4. If a category grows past about 6 items, or two categories have become one idea, suggest renaming
   or splitting it to the user before doing it.
5. Whenever categories change, update this table, the README headings and the order in `SECTIONS`
   together.
6. Tell the user which category you picked and why, in one line.

## Checklist for a new feature

1. **Default**: add a key to `DEFAULTS` at the top of `Quinta.lua`. New optional features that change
   how the game looks should usually default to off. Removed features: clear their keys in
   `ADDON_LOADED`, like the existing `db.playerBorder = nil` line.
2. **Feature code**: add a section with its own banner comment
   (`---------------------------------------------------------------------------` / `-- Name` / `---...`),
   placed **above** the "Settings window" section, so its functions are in scope for `SECTIONS`.
3. **Setting**: add one item to the right section in `SECTIONS`:
   - `{ type = "check", key = "myKey", label = "Short label", onChange = function(on) ... end }`.
     Add `disabled = function() return ... end` if it depends on another setting.
   - `{ type = "slider", key, label = "Name: %.1f", min, max, step, onChange, onRelease }`
   - `{ type = "button", label = "Do it now", onClick = function() ... end }`
   Keep labels short (about 30 characters at most, so they fit the 260px column); the header carries the context.
   Wrap callbacks in `function() X() end` instead of passing `X` directly.
4. **Events**: register in the `Events` section at the bottom. For events that only exist in some
   game versions, use `pcall(f.RegisterEvent, f, "EVENT")`, like the spell-learning events.
5. **Combat lockdown**: anything that moves protected frames or changes action bars must check
   `InCombatLockdown()` and retry on `PLAYER_REGEN_ENABLED` (see `rankPending`, `markersPending`).
6. **Multiple game versions**: the TOC supports Classic Era through Retail. Prefer
   `C_X.Func or OldFunc` fallbacks, like the ones at the top of the rank section.
7. **Slash command** (optional): add `/quinta <word>` in `SlashCmdList.QUINTA`, above the line that
   opens the panel. Mention it in the README.
8. **Docs**:
   - `README.md`: add a bullet under the matching category heading (same order as the window).
   - `CHANGELOG.md`: add a line under `## [Unreleased]` (create it at the top if missing) in
     `### Added` / `### Changed` / `### Removed`.
   - `Quinta.toc`: add a few words to `## Notes`.
9. **Verify**: there's no Lua toolchain here, so re-read the diff for nil upvalues and typos. Then
   give the user a short in-game test list (`/reload`, `/quinta`, toggle it, check the layout).

## Releasing (only when the user asks)

1. Pick the version: a new feature bumps the minor version (1.4.0 → 1.5.0); a fix only bumps the
   patch version (1.4.0 → 1.4.1). `git tag --sort=-v:refname | head -1` shows the current one.
2. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [x.y.z] - YYYY-MM-DD` (today's date).
3. Commit on `main` as `Release x.y.z: <short summary>`, then `git push origin main`.
4. `git tag vx.y.z && git push origin vx.y.z`. The GitHub Action packages the addon and uploads it to
   CurseForge and GitHub Releases.
5. Check it: `gh run list --limit 1`, `gh run watch <id> --exit-status`, then
   `gh release view vx.y.z` should list `Quinta-vx.y.z.zip`.
