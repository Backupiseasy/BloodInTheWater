# Blood in the Water

A Feral Druid addon for Cat Form. It adds its own energy bar, combo points, timers for important debuffs, and icons for key procs and cooldowns, all positioned exactly where you want them. It stays out of the way outside Cat Form.

## Features

- **Energy bar** for Cat Form — its own always-accurate, up-to-date display, including talents that raise max energy above 100
- **Combo point display** with per-count color (0 / 1–3 / 4 / 5), an overflow-buffer indicator for banked points above the 5-point cap, fully repositionable
- **Debuff timers** — Rake, Rip, and Moonfire tracked as icons with 0.1s precision countdowns, plus a pandemic (early-refresh window) glow
- **Proc icons** for Clearcasting and Predatory Swiftness
- **Cooldown icons** for Tiger's Fury, Berserk, and Incarnation
- Automatically hidden for non-Druids and outside Cat Form — no manual toggling needed

## Under the hood

- **Config Mode** — force-shows every row with placeholder art and randomized dummy countdowns so you can position everything without a live target or active buffs; a one-off UI aid, not saved between sessions
- **LibSharedMedia support** — custom bar texture, border, and one shared font for every text element. Font, texture, and border ship with the addon and are used again automatically if a selected one is no longer available (for example because the addon providing it was disabled)
- **Libraries included** — Ace3 and LibSharedMedia are embedded, nothing else to install
- **Per-character/profile settings** via AceDB-3.0 (position, size, colors, fonts, spacing — all persist across `/reload` and relogin), switchable/copyable/resettable via the Profiles tab
- Zero overhead when hidden — no processing while outside Cat Form

## Configuration

Type `/bitw` to open the configuration dialog.

- **Energy Bar tab** — bar size, position, texture, border, font size
- **Combo Points tab** — text position, font size, per-count colors, overflow-buffer position and font size
- **Icons tab** — shared icon size, typeface, and countdown font size used across all rows
- **Debuffs tab** — Rake/Rip/Moonfire icon position, countdown text color, pandemic-glow color and style (Simple Border or WoW Border)
- **Proccs tab** — Clearcasting/Predatory Swiftness icon position, countdown text color, stack-count text position
- **Cooldowns tab** — Tiger's Fury/Berserk/Incarnation icon position, spacing, countdown text color
- **Profiles tab** — switch, copy, or reset per-character profiles
- **Toggle Config Mode** button (top of the dialog) — preview every row at once for positioning

## Known limitations

- Druid-only, Cat Form-only — by design, not a bug
- Supports Retail and WoW Forever. On WoW Forever Rake, Rip, Tiger's Fury (all ranks), Berserk and Clearcasting are tracked; Moonfire, Predatory Swiftness, Incarnation and the overflow buffer don't exist there

## Feedback & Issues

Comments are disabled on the CurseForge project page. Please use GitHub instead:

- [Issues](https://github.com/Backupiseasy/BloodInTheWater/issues) — bug reports and feature requests
- [Discussions](https://github.com/Backupiseasy/BloodInTheWater/discussions) — questions, ideas, and general feedback

## License

All Rights Reserved.
