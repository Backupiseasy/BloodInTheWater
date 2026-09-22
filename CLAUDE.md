# Blood in the Water

## What this is

WoW AddOn (Retail `## Interface: 120100` + WoW Forever `16001`, see "WoW Forever" below). Druid-only, Cat Form-only energy
bar with combo points, target-debuff/player-buff/cooldown-buff icon rows.
Everything is an addon-owned frame or Blizzard's `AuraContainer`/`AuraButton`
API — never Blizzard's own Cooldown Manager (CDM) frames. Config via `/bitw`.

No build system, no tests, no lint config. Validation is entirely in-game
(`/reload`, watch for red error text).

## Files

- `BloodInTheWater.toc` — metadata, load order (`Libs\embeds.xml`, then `BloodInTheWater.lua`, then `Options.lua`)
- `BloodInTheWater.lua` — addon logic: lifecycle, frame creation, aura rows, events
- `Options.lua` — AceConfig options table (`Addon:SetupOptions()`, `Addon:OpenConfig()`)
- `Libs/embeds.xml` — include list for the embedded libraries (see Framework); the libs themselves are not checked in
- `Media/` — bundled font (`Cabin.ttf`), statusbar texture (`Smooth.tga`), energy bar border (`PlainBorder.tga`), addon icon (`bitw_logo.png`)
- `.pkgmeta` — packager config (BigWigsMods/packager, used by `.github/workflows/`); fetches the `Libs/` externals, excludes `CLAUDE.md`/`README.md` from release zips
- `BloodInTheWater_Changes.log` — full changelog history; `CHANGELOG.md` — packager-facing mirror of only the current unreleased entry block (see Changelog Workflow below)

Options.lua is a separate Lua chunk — it has no access to BloodInTheWater.lua's
`local`s. It re-fetches the addon via `LibStub("AceAddon-3.0"):GetAddon(...)`
and re-declares `LSM`. Anything BloodInTheWater.lua needs Options.lua to read
or call must be a field/method on `Addon` (e.g. `Addon.previewModeActive`,
`Addon:RefreshComboPoints()`), never a bare `local`.

## Framework

Ace3 (`AceAddon-3.0`, `AceEvent-3.0`, `AceConsole-3.0`, `AceDB-3.0`,
`AceConfig-3.0`, `AceConfigDialog-3.0`, `AceDBOptions-3.0`) and
`LibSharedMedia-3.0` are **embedded** via `Libs/embeds.xml` (loaded first in
the `.toc`). No `RequiredDeps`/`OptionalDeps` — a missing standalone Ace3
addon once disabled BitW in-game. `LibSharedMedia-3.0` is still accessed with
`LibStub("LibSharedMedia-3.0", true)` and guarded with `if LSM`.

The bundled `Media/` files are registered with LSM under the keys `Cabin`
(font), `Smooth` (statusbar), `PlainBorder` (border) — the `Defaults` values.
The same files double as fallback (`FALLBACK_FONT_PATH`,
`FALLBACK_BAR_TEXTURE_PATH`, `FALLBACK_BORDER_PATH`) whenever a saved key isn't
registered (e.g. the SharedMedia addon that provided it got disabled). A new
bundled asset needs an LSM registration **and** a fallback constant.

`Libs/` is git-ignored (except `embeds.xml`); the packager fills it from the
`externals:` in `.pkgmeta` (short form = trunk HEAD, like ThreatPlates). For
local in-game testing, `Libs/` must be filled by hand from the same sources —
adding a lib means updating both `.pkgmeta` and `Libs/embeds.xml`.

## WoW Forever

"WoW Forever" is Blizzard's official Classic-rules client on the modern (Midnight-era) engine: it reports
`WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` but `GetClassicExpansionLevel() == 0` (Vanilla), Interface `16001`
(in the TOC's Interface line next to Retail's), and has AuraContainers, secret values, `C_Spell`,
`C_UnitAuras`. Background and the full list of pitfalls: the ThreatPlates repo's
`Source/Wiki/wow-forever-compatibility.md`.

**Implemented**

- `Addon.IS_FOREVER` (same formula as ThreatPlates' `Init.lua`) picks the spell set. `Options.lua` reads it
  plus `Addon:IsSlotUsed(row, i)` / `Addon:HasComboPointBuffer()` to hide rows that don't exist there.
- Spell IDs live in `SPELL_SETS` (`RETAIL` / `FOREVER`); each slot is a **list** of aura IDs because every
  Classic rank of Rake/Rip has its own ID. An empty list = unused slot (container/preview disabled, Options
  row hidden). `DEBUFF_SPELL_SETS` etc. are the precomputed `includeSpellIDs` sets.
- Forever tracks: Rake (1822, 1823, 1824, 9904), Rip (1079, 9492, 9493, 9752, 9894, 9896), Tiger's Fury
  (5217, no ranks), Berserk (417141), Clearcasting (16870 — the proc buff; 16864 is the Omen of Clarity
  talent). Not there: Moonfire (not tracked — not used in the Cat Form rotation), Predatory Swiftness,
  Incarnation, combo point overflow buffer.
  All IDs checked against Wowhead Forever: `https://nether.wowhead.com/forever/tooltip/spell/<id>` returns
  JSON whose `buff` field is the aura the spell applies (same ID). Plain `www.wowhead.com` is
  Cloudflare-blocked for scripts.
- Player power is a secret value in combat (`UnitPower("player", ...)`, confirmed live in Cat Form/combat on
  Forever — the one time this bar shows). `RefreshComboPoints` shows it via `SetText` (C-side sink) directly,
  and colors it unconditionally via `UnitPowerPercent("player", 4, false, curve)` with a step `ColorCurve`
  whose breakpoints are the 0/1-3/4/5+ tiers expressed as percent-of-max — no secret/plain branch, no
  fallback. **Not** `LuaColorCurveObject:Evaluate(cp)` — `Evaluate` takes the secret `cp` as an explicit Lua
  argument and is only `SecretArguments="AllowedWhenUntainted"`, so it throws the instant it's called in
  combat (confirmed live: "Secret values are only allowed during untainted execution for this argument").
  `UnitPowerPercent` reads the secret power value and evaluates the curve entirely C-side instead, so the
  secret number never crosses into Lua as an argument — same pattern as ThreatPlates' `UnitHealthPercent(unit,
  true, curve)` for health colors (`Elements/StatusText.lua`), not a curve's own `:Evaluate()`. No
  `C_CurveUtil`/`Enum.LuaCurveType` existence guard — confirmed present on both supported clients (Retail
  120100 and Forever 16001, both Midnight-engine; checked in `/bitwdebug`'s API table). The former Forever
  "combo points live on the target" fallback (`GetComboPoints("player", "target")`) is gone too — confirmed
  live (`/bitwdebug`'s Energy/combo points section, with a real target and combo points built, in combat) that
  `GetComboPoints` comes back just as secret as `UnitPower("player", 4)` whenever this bar is shown, so that
  fallback could never actually fire. `OnTargetChanged` still re-runs `RefreshComboPoints` on Forever because
  no power event fires on a target switch.
- `GetShapeshiftFormID() == 1` (`CAT_FORM_ID`) is Cat Form on Forever too — confirmed in-game in Cat Form.
- Config Mode (preview with unused slots) works on Forever — confirmed in-game.
- `UNIT_COMBO_POINTS` does not exist on Forever; combo points arrive via `UNIT_POWER_FREQUENT`
  (`COMBO_POINTS`) and the `PLAYER_REGEN_*`/shapeshift-driven `OnShapeshift` refresh (the old 0.5s
  `Bar.stateTicker` was removed).
- SavedVariables not loading on some Forever clients is a known client bug (see ThreatPlates' wiki, fixes
  #21-#23) — not addon-fixable. Deliberately no workaround here; don't add one.
- The auras really do show up under the Forever IDs listed above (multi-ID `includeSpellIDs` filters, incl.
  in combat) — confirmed in-game.
- Options tabs (hidden rows: Moonfire, Predatory Swiftness, stack text, overflow buffer, Incarnation text) —
  confirmed in-game.
- The Pandemic glow never triggers under Vanilla rules — confirmed in-game (Rake/Rip run their full duration,
  glow never shows). Its 3 Options widgets (`pandemicLabel`/`pandemicColor`/`pandemicStyle`, Debuffs tab) are
  now `hidden = function() return Addon.IS_FOREVER end` — the underlying `CreatePandemicGlow`/
  `AddPandemicRegion` machinery is left in place (harmless, Blizzard's own Shown-state gate just never fires),
  only the now-pointless config UI is hidden.

**Still unverified in-game**:

- The Retail code paths after the spell-table refactor (`SPELL_SETS.RETAIL`, list-based `includeSpellIDs`) —
  no Retail regression test done yet.

## Options tabs (Options.lua, in order)

1. **Energy Bar** — Layout (size/position), Appearance (texture/border/font size)
2. **Combo Points** — Appearance (per-count colors, font sizes), Layout (position, overflow buffer — hidden on Forever)
3. **Icons** — shared icon size/typeface/countdown-font-size across all rows
4. **Debuffs** — Rake/Rip/Moonfire (Moonfire hidden on Forever) position, countdown color, Pandemic Glow (color + Simple Border/WoW Border style; whole Pandemic Glow group hidden on Forever, no pandemic mechanic there)
5. **Proccs** — Clearcasting/Predatory Swiftness position, countdown color, stack-count text position (Predatory Swiftness and stack text hidden on Forever)
6. **Cooldowns** — Tiger's Fury/Berserk/Incarnation (no Incarnation on Forever) position, spacing, countdown color
7. **Profiles** — `AceDBOptions-3.0`'s stock tab (switch/copy/reset)

Plus a "Toggle Config Mode" execute button at the top (order 0).

When adding a row of options that needs a guaranteed line break, use
`GetSpacerEntry(order)` (invisible `width="full"` filler) as the last widget
in that row — don't rely on widths summing to exactly "full" on their own,
that's been unreliable in practice. For a labeled item (a name + X/Y offsets,
etc.) that must render as its own line, put it in its own nested
`inline = true` sub-group instead — group boundaries always start a fresh
line, which is more robust than width arithmetic.

## Combat gating

Bar + every icon row hidden unless **both** in Cat Form (`GetShapeshiftFormID() ==
CAT_FORM_ID`, `CAT_FORM_ID = 1`) **and** in combat, or Config Mode is on
(force-shows everything). The condition lives in one place,
`ShouldShowInCombat()`, used by `Addon:OnShapeshift()` (Bar, combo points) **and**
the three `Update*ContainerFilters()` (all icon rows) — keep them in sync, don't
re-derive it per row.

"In combat" = `Addon.inCombat or InCombatLockdown()`. `Addon.inCombat` is set by
`Addon:OnCombatStarted()` (`PLAYER_REGEN_DISABLED`) and cleared at the top of
`Addon:OnCombatEnded()` (`PLAYER_REGEN_ENABLED`); `InCombatLockdown()` covers a
`/reload` mid-combat. Do not use `InCombatLockdown()` alone: with no polling, the
Bar and combo points stayed hidden in real combat while the icon rows showed
(tested in-game; the fix with `Addon.inCombat` was confirmed working — Bar,
combo points and all rows show in combat in Cat Form and hide on leaving Cat
Form or ending combat). The likely cause is `InCombatLockdown()` still being
false inside the `PLAYER_REGEN_DISABLED` handler; that part is not verified from
documentation.

State is purely event-driven (`UPDATE_SHAPESHIFT_FORM`, `PLAYER_REGEN_*`, aura/
target events). There is deliberately **no polling ticker** — the former
`Bar.stateTicker` (separate never-hidden frame, `OnUpdate` calling `OnShapeshift`
every 0.5s) was removed as unproven. Background, in case display problems
(Bar/rows stuck hidden or shown) ever show up in-game:

- The ticker's original rationale (a code comment) was that `PLAYER_REGEN_*`/
  `UPDATE_SHAPESHIFT_FORM` might be missed or reordered, e.g. by brief
  regen-enabled blips between back-to-back pulls. Never reproduced or
  confirmed. An earlier idea that `GetShapeshiftFormID()` returns the old form
  inside the event is **unverified speculation** (Blizzard's own tutorial
  handlers read it directly inside `UPDATE_SHAPESHIFT_FORM`). A ticker has to be
  its own never-hidden frame: a hidden frame gets no `OnUpdate`.
- Blizzard's own Personal Resource Display (checked against `wow-ui-source`
  live, `Blizzard_ClassNameplateBar_Druid.lua` / `DruidComboPointBar.lua` /
  `ClassResourceBarTemplate.lua`): the Feral combo bar shows when
  `UnitPowerType("player") == Enum.PowerType.Energy` — no form-ID check —
  and re-evaluates on `UNIT_DISPLAYPOWER`, `PLAYER_ENTERING_WORLD` and
  `PLAYER_TALENT_UPDATE`. No ticker/polling. Whether the PRD shows only in
  combat is an engine CVar matter, not visible in the Lua source.
- If display problems appear, two remedies to try: (1) reinstate the 0.5s
  ticker; (2) switch the Cat Form check to
  `UnitPowerType("player") == Enum.PowerType.Energy` and additionally register
  `UNIT_DISPLAYPOWER` (closer to Blizzard; also triggers for other Energy
  situations, so it changes behavior slightly).
- Config Mode's dummy countdowns are the one place that still needs a timer:
  `Addon:SetPreviewMode()` (called by the Options toggle — never flip
  `Addon.previewModeActive` directly) runs a 0.5s `C_Timer.NewTicker` calling
  `UpdatePreviewFrames` only while Config Mode is on, cancelled when it is
  turned off.

## Callbacks

Registered in `Addon:OnInitialize()`:

- AceDB `OnProfileChanged`/`OnProfileCopied`/`OnProfileReset` → `Addon:OnProfileRefresh()`
  (`UpdateBar()` + combo-point refresh + `AceConfigRegistry-3.0:NotifyChange`).
  The Profiles tab only swaps the data, nothing repaints without this.
- AceDB `OnDatabaseShutdown` → `Addon:OnDatabaseShutdown()`. `PLAYER_LOGOUT` (also
  `/reload`) makes AceDB strip the defaults from `db.profile`; the handler
  unregisters all events, cancels the Config Mode timer and the LSM callback so
  nothing reads missing defaults afterwards.
- LSM `LibSharedMedia_Registered` → `Addon:OnMediaRegistered()`, debounced to one
  `Addon:RefreshMedia()` on the next frame (LSM fires it once per media entry,
  hundreds of times while other addons load). `RefreshMedia()` is also what
  `PLAYER_ENTERING_WORLD` runs.

`AuraContainer`s cannot be created during combat — creation is guarded by
`InCombatLockdown()` and retried from `Addon:OnCombatEnded()`.

## Critical WoW API facts

- Druid check: `select(2, UnitClass("player")) == "DRUID"`, top of `OnInitialize`/`OnEnable`.
- Energy: `UnitPower("player", 3)` / `UnitPowerMax("player", 3)` (talents raise the cap — always read max dynamically). Event: `UNIT_POWER_FREQUENT`, not `UNIT_POWER_UPDATE`.
- AceEvent has no `RegisterUnitEvent` — filter `unit == "player"` inside the handler.
- **Never touch Blizzard's own `EssentialCooldownViewer`/`BuffIconCooldownViewer`** — tainted their secret aura data and crashed the client when tried. Every row here is addon-owned or `AuraContainer`-based instead.
- Some aura fields (`applications`/`duration`/`expirationTime`) and, on Forever, `UnitPower("player", ...)` can be secret values — check `issecretvalue(...)` (file-local `IsSecret`) before comparing/`tostring`-ing (see `RefreshComboPointBuffer`, `RefreshComboPoints`). Passing one straight to `SetText`/`SetValue` is fine.
- `BackdropTemplateMixin:SetBackdrop` doesn't reliably recompute a live-shown border in place — `SetBackdrop(nil)` then rebuild the full table on every change (see `Addon:ApplyBarAppearance()`). Don't "fix" a stuck border via `Hide()`/`Show()` toggling — caused a runaway recursive layout loop (OOM crash) once.
- A freshly (re)built backdrop's border can settle back to full alpha a frame after `SetBackdrop` returns — reapply `SetBackdropBorderColor` once more via `C_Timer.After(0, ...)` to win that race (see `ApplyBarAppearance`).
- LSM-registered media from other addons may not exist yet at this addon's own load — re-apply LSM-dependent visuals on `PLAYER_ENTERING_WORLD` too (`Addon:OnPlayerEnteringWorld`).
- Real `AuraButton`s are secure/pooled: `InitializeAuraButton` runs exactly once per physical button, ever. Live setting changes re-run the same `Set*` calls via `Addon:ReapplyLiveAuraButtonSettings()` (icon size/font/color) — out of combat only, retried from `OnCombatEnded`. Anything not covered there won't update live on existing buttons until `/reload`.
- `AddPandemicRegion(region)` marks only the region's **Shown** state secret (`AddSecretAspect`) — color/size/blend stay addon-controlled always. Accepts any Region (Frame or Texture).
- The default `CooldownFrameTemplate` swipe is circular, not square — this is standard WoW behavior for aura/buff icons everywhere (target frame, unit frames, ThreatPlates all do the same), not a bug to fix.
- The main icon's spell-icon art has a thin border baked into the texture file itself — crop it with `SetTexCoord(0.08, 0.92, 0.08, 0.92)` (see `InitializeAuraButton`/`CreateIconFrame`), otherwise it shows through whenever the cooldown swipe doesn't happen to cover the edge.

## Conventions

- File-global variables: UpperCamelCase (`Addon`, `Bar`, `Defaults`).
- Local variables inside functions: lowerCamelCase.
- All code and comments: English only.
- No global (non-`local`) Lua variables except methods on `Addon` and the one
  required plain global: `BloodInTheWater_OnAddonCompartmentClick` (Blizzard
  calls Addon Compartment click handlers by name, not through the addon object).
- When two code paths do near-identical setup for different widget types
  (e.g. `InitializeAuraButton` for real secure `AuraButton`s vs.
  `CreateIconFrame` for plain preview/Config-Mode frames), a fix to one's
  visuals usually belongs on both — they're commented to cross-reference each
  other for this reason. Check both before considering a visual fix done.
- When modifying the database schema: update `Defaults` in `BloodInTheWater.lua`
  **and** the matching option in `Options.lua`'s `Addon:SetupOptions()`.

## Changelog Workflow

Two files must stay in sync for every user-facing change:

- `BloodInTheWater_Changes.log` — full project history; new version blocks/entries are prepended at
  the top:

  ```text
  ------------------------------------------------------
  <version> (<date YYYY-MM-DD>)
  ------------------------------------------------------
  * Entry one.
  * Entry two [GH-NNN].
  ```

- `CHANGELOG.md` — mirrors **only** the entries of the current unreleased (top) version block in
  `BloodInTheWater_Changes.log`; keep its heading as `# @project-version@ (@build-time@)` —
  the packager fills `@project-version@`, while `@build-time@` is our own placeholder that the
  release workflow (`_package_release.yml`) replaces with the build date via `sed` (and fails the
  run if it is missing). The `.log` keeps literal dates, it is not touched.

Entry format: one `*`-bullet per logical change, starting with a capitalized past-tense verb (`Fixed`,
`Added`, `Changed`, `Removed`, `Updated`; use `Hopefully fixed` when the fix is unverified), ending with
a period. Reference GitHub issues/PRs as `[GH-NNN]` or `[PR GH-NNN by author]` (CurseForge comments
are disabled — feedback goes through GitHub Issues/Discussions), placed right before the final
period — never invent reference numbers.

Wording:

- Lead with the user-visible symptom in plain, player-facing language (e.g. "a Lua error", "the combo
  point overflow buffer not clearing"), never with the internal fix or code change.
- Optionally add root cause with a `, caused by ...` clause, phrased in terms of WoW/Blizzard behavior
  (a client-side API change, a secret-value restriction, a specific patch) — never in terms of this
  addon's internal functions, files, or variables.
- Two recurring shapes: `Fixed a Lua error when <doing X>, caused by <Y>.` and `Fixed a bug where
  <symptom>, caused by <Y> [ref].`
- One bullet per independent change, even closely related ones.

If the last released tag matches the current top version block, start a **new** version block
(incremented patch version, today's date) before adding the entry; otherwise append to the existing
top (unreleased) block.

## Debugging

`/bitwdebug` → `Addon:DebugCheck()` — full WoW Forever compatibility report (client signals, API
availability, Cat Form detection, energy/combo-point sources, event registration, spell-ID existence,
assets, AuraContainer state), ending with `Addon:DebugDumpDebuffs()` — the
target-debuff `AuraContainer` pipeline state (spell IDs, Cat Form, target, combat lockdown, pool frame
counts) for diagnosing a "no icon showing" report. `/bitwdebug live [seconds]` counts which events
really fire during a window.

`/bitwauras` → `Addon:ToggleAuraWatch()` — toggles a watcher that prints spell ID + name of every new
aura on the player (HELPFUL) / target (own HARMFUL) to chat; used to find the per-rank aura IDs of
Rake/Rip/Tiger's Fury/Berserk/Clearcasting on WoW Forever. **Only works out of combat** — confirmed live
on Forever that `C_UnitAuras.GetAuraDataByIndex` throws immediately at index 1 in combat
("Auras cannot be accessed when secret while tainted by 'BloodInTheWater'"), because the whole call
chain (slash command → `AceConsole` → this addon's code) is addon-tainted; it's not a partial degrade to
`<secret>` fields, the call itself is refused. `ScanWatchedAuras` wraps the call in `pcall` and prints a
one-line "aura data inaccessible" notice instead of crashing, then stops that unit's scan. Training
dummies do **not** give an out-of-combat window on Midnight/Forever — confirmed live that hitting one
still flips `PLAYER_REGEN_DISABLED` (contrary to older-expansion behavior), so `/bitwauras` can't capture
a harmful-spell aura ID that way either. For a harmful spell's ID/ranks when no genuine out-of-combat
capture is possible, use the Wowhead Forever tooltip lookup instead (same URL pattern as above) against
known Classic rank spell IDs.

The debug commands are Forever-port diagnostics; trim them once the unverified items above are confirmed.
