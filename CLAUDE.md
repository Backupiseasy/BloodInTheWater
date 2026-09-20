# Blood in the Water

## What this is

WoW AddOn (Retail, `## Interface: 120100`). Druid-only, Cat Form-only energy
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

## Options tabs (Options.lua, in order)

1. **Energy Bar** — Layout (size/position), Appearance (texture/border/font size)
2. **Combo Points** — Appearance (per-count colors, font sizes), Layout (position, overflow buffer)
3. **Icons** — shared icon size/typeface/countdown-font-size across all rows
4. **Debuffs** — Rake/Rip/Moonfire position, countdown color, Pandemic Glow (color + Simple Border/WoW Border style)
5. **Proccs** — Clearcasting/Predatory Swiftness position, countdown color, stack-count text position
6. **Cooldowns** — Tiger's Fury/Berserk/Incarnation position, spacing, countdown color
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
- Some aura fields (`applications`/`duration`/`expirationTime`) can be secret values — check `issecretvalue(...)` before use (see `RefreshComboPointBuffer`).
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
  `BloodInTheWater_Changes.log`; consumed by the packager via `# @project-version@ (@build-time@)`.

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

`/bitwdebug` → `Addon:DebugDumpDebuffs()` — dumps the target-debuff
`AuraContainer` pipeline state (spell IDs, Cat Form, target, combat lockdown,
pool frame counts) for diagnosing a "no icon showing" report.
