# Changelog

## [1.3.0] - 2026-11-20

### Added
- **Shadow Word: Death kill alert** (priests): a big Shadow Word: Death icon pops up when your target's health is at or below the spell's damage (the lowest number in its tooltip, so it kills even without a crit). It stays hidden while the spell is on cooldown. It works in combat on WoW Forever too, where addons can't read target health. Uses your highest rank automatically. `/quinta swd` to move it.
- **Raid marker panel** (off by default, turn it on in `/quinta`): click a mark to put it on your target (click it again, or X, to remove it). It shows while you have a target and can be dragged anywhere.
- **Movable loot roll window**: Shift-drag a Need/Greed/Pass roll to move it, or type `/quinta loot` to place it without a roll up. `/quinta loot reset` puts it back.

### Removed
- The player frame border option (and `/quinta nudge`).

## [1.2.0] - 2026-11-15

- New **Player frame border** option in `/quinta`: Normal, Elite (gold dragon), Boss (winged gold dragon) or Rare elite (silver dragon) around your player portrait. Works on both the classic and the modern player frame.
- `/quinta nudge <x> <y>` moves the dragon a few pixels if it doesn't line up (right/up are positive). Each style remembers its own position.

## [1.1.0] - 2026-11-15

- New **Hide chat** option: hides chat all the time, not only in combat. While it's on, "Hide chat in combat" is greyed out. The typing box still shows when you press Enter.

## [1.0.0] - 2026-11-15

First public release.

- UI scale slider (0.3 to 1.2).
- Hide chat while in combat.
- Hide the menu bar, bag bar and quest tracker until you hover over them.
- Max camera distance slider.
- Auto-upgrade spell ranks on your action bars when you learn a new rank.
- All options in one small window: type `/quinta`.
