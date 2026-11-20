# Quinta's UI Tweaks

A few small World of Warcraft UI tweaks in one lightweight addon. Type `/quinta` to open the options.

- **UI scale** slider (0.3 to 1.2)
- **Hide chat**, all the time or only in combat (the typing box still shows when you press Enter)
- **Hide the menu bar, bag bar and quest tracker**, they fade back in when you hover over them
- **Max camera distance** slider
- **Auto-upgrade spell ranks** on your action bars when you learn a new rank, plus an **Update ranks now** button (or `/quinta ranks`) for bars that missed it, like Gamepad bars on another computer
- **Raid marker panel** (optional, off by default): click a mark to put it on your target
- **Movable loot roll window**: Shift-drag a roll, or `/quinta loot` to place it
- **Shadow Word: Death kill alert** (priests): an icon pops up when your target is low enough for it to kill, and it isn't on cooldown (`/quinta swd` to move it)

Works on Classic Era, Anniversary, TBC, Wrath/Cata/MoP Classic and Retail.

Note: on first install it uses the author's settings (UI scale 0.5, chat hidden in combat, camera 2.6). Change them in `/quinta`.

## Releasing

Push a version tag (`git tag v1.0.1 && git push origin v1.0.1`). The GitHub Action packages the addon and uploads it to CurseForge and GitHub Releases.

## License

MIT
