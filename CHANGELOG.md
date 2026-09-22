# @project-version@ (@build-time@)

* Added a fill bar next to each cooldown-buff icon (Tiger's Fury/Berserk/Incarnation), configurable in the Cooldowns tab.
* Changed the cooldown-buff row to give each spell its own AuraContainer instead of sharing one, needed to assign each a fixed bar color.
* Changed Config Mode's cooldown-buff preview to show the same icon+bar layout as the real row instead of a bare icon.
* Added an Icon-Bar Gap option and an Icon on Right option to the Cooldowns tab.
* Changed the cooldown-buff bar to shorten Incarnation's label to its short name instead of the full talent name.
* Added a configurable border to each cooldown-buff fill bar, matching the energy bar's border settings by default.
* Changed each cooldown-buff bar to have its own fill color, configurable in the Cooldowns tab.
* Fixed the cooldown-buff fill bars (Tiger's Fury/Berserk/Incarnation) not showing at all in combat, caused by querying the player's own buff duration from plain addon code, which is subject to a secret-value restriction while addon restrictions are in effect. The bars are now driven directly by the same secure widget each icon's cooldown swipe already used.
* Fixed a Lua error ("attempt to perform arithmetic on ... a secret number value") when combat ended, caused by rebuilding the cooldown-buff bar's border right after a secret-aware widget on the same icon, which Blizzard's own UI code treats defensively. Border Texture/Size/Inset changes now only reach already-shown icons after a /reload; Border Color still applies live.
* Added a Bar Texture option to the Cooldowns tab, independent of the energy bar's own texture.
* Removed the Smooth Bar Animation option from the Cooldowns tab — the fill bar now always animates smoothly.
* Changed the Cooldowns tab's Appearance and Layout sections to match the Energy Bar tab's layout: Bar Colors and the bar border options moved into Appearance; X/Y Offset, Row Spacing, Bar Width/Height/Spacing and Icon on Right regrouped under Layout.
* Changed the default Tiger's Fury and Berserk bar colors to match their ability icon art.
