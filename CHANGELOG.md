# @project-version@ (@build-time@)

* Added a fill bar next to each cooldown-buff icon, showing the buff's remaining duration.
* Added a Bar Background Color option to the Energy Bar and Cooldowns tabs.
* Changed the default cooldown settings to better match WoW's modern UI look.
* Changed Config Mode to show the energy bar at a fixed 50% fill instead of the player's real energy.
* Fixed the Border Position (Inset) option having no effect on the energy bar or the cooldown-buff bars, caused by Blizzard's backdrop API only ever repositioning a background texture neither bar uses.
* Changed Berserk and Incarnation to share a single cooldown-buff slot instead of two, since the underlying talents are mutually exclusive.
* Fixed a bug where WoW Forever was no longer detected and the addon tracked the Retail spells instead (e.g. an empty Berserk icon).
