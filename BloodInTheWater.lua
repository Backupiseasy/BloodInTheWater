-------------------------------------------------------------------------------
-- Blood in the Water
-- Displays an energy bar for Druids in Cat Form.
-- /bitw  opens the configuration dialog.
-------------------------------------------------------------------------------

local Addon = LibStub("AceAddon-3.0"):NewAddon("BloodInTheWater", "AceEvent-3.0", "AceConsole-3.0")

-- Default database values
local Defaults = {
  profile = {
    posX   = 0,
    posY   = -220,
    width  = 240,
    height = 28,
    -- Energy bar fill texture (LibSharedMedia "statusbar" key) and its
    -- border (LibSharedMedia "border" key + edge thickness/inset/color).
    -- "Smooth" is bundled by this addon itself (Media/Smooth.tga, see
    -- ADDON_FOLDER/LSM:Register below), not the SharedMedia data addon.
    barTexture       = "Smooth",
    barColor         = {0.949, 1, 0.043, 1}, -- energy bar fill color + alpha
    barFontSize      = 18,              -- energy value number font size (points)
    barBorderTexture = "PlainBorder",
    barBorderSize    = 16,               -- edge thickness (px)
    barBorderInset   = 0,                -- offset of the edge from the bar's own outer edge (px)
    barBorderColor   = {0, 0, 0, 0.3},      -- border color + alpha
    -- Combo point counter text (anchored relative to the energy bar center).
    cpPosX     = 0,   -- X offset from Bar center (px)
    cpPosY     = 78,  -- Y offset from Bar center (px)
    cpFontSize = 24,  -- font size (points)
    -- Combo point colors per threshold.
    cpColor0 = {1,   1,   1,   1},  -- 0 points  : white
    cpColor1 = {1,   1,   0,   1},  -- 1-3 points : yellow
    cpColor4 = {1,   0.5, 0,   1},  -- 4 points   : orange
    cpColor5 = {1,   0,   0,   1},  -- 5 points   : red
    -- Icons tab: one shared LibSharedMedia font/typeface and one shared
    -- icon size for every icon-based row (Debuffs/Proccs/Cooldowns) — no
    -- per-row Font/IconSize duplication. Countdown-number size is
    -- derived from icon size (appearanceFontScale), not its own absolute
    -- point size.
    appearanceFont      = "Cabin", -- LibSharedMedia font key (bundled, see ADDON_FOLDER below)
    appearanceIconSize  = 32,                 -- icon width/height (px), shared everywhere
    appearanceFontScale = 0.6,                -- countdown font size = iconSize * this (0.1-1.0)
    -- Pandemic (DoT refresh window) glow — only meaningful for the target
    -- debuffs (Options: Debuffs tab), though the region is attached to
    -- every AuraButton (see InitializeAuraButton). Shown state is driven by
    -- Blizzard's own secret AddPandemicRegion aspect, only color/alpha are
    -- addon-set.
    pandemicColor = {0.498, 1, 0, 1}, -- 7FFF00, chartreuse green
    pandemicStyle = "wow", -- "custom" (plain outset border) or "wow" (Assisted Combat-style ants glow)
    -- Target debuff icons (AuraContainer), 3 fixed, individually positioned
    -- slots (Offset X/Y each, relative to the energy bar center) — spell IDs
    -- hardcoded, see DEBUFF_SPELL_IDS.
    debuffOffsets = {
      {x = -106, y = 38},
      {x = 106,  y = 38},
      {x = 0,    y = 38},
    },
    debuffNormalColor = {1, 1, 1, 1}, -- countdown text color
    -- Combo point overflow buffer (Überquellende Macht) — spell ID is
    -- hardcoded (CP_BUFFER_SPELL_ID), not user-configured.
    cpBufferPosX     = 20,    -- X offset from Bar center (px)
    cpBufferPosY     = 78,    -- Y offset from Bar center (px)
    cpBufferFontSize = 14,    -- font size (points)
    -- Player buff icons (AuraContainer), 3 fixed, individually positioned
    -- slots — same pattern as the target debuffs above. Spell IDs hardcoded,
    -- see PLAYER_BUFF_SPELL_IDS.
    buffOffsets = {
      {x = -28, y = -40},
      {x = 28,  y = -40},
      {x = 40,  y = -40},
    },
    buffNormalColor = {1, 1, 1, 1}, -- countdown text color
    buffStacksPosX = 4,  -- stack-count text offset from icon BOTTOMRIGHT (px)
    buffStacksPosY = -8,
    -- Cooldown-buff icons (Tiger's Fury/Berserk/Incarnation by default,
    -- hardcoded — see COOLDOWN_BUFF_SPELL_IDS). Stays one positioned unit
    -- with a Spacing value (stacked vertically), unlike Debuffs/Buffs above
    -- which are individually positioned per slot.
    cooldownBuffPosX    = -280, -- X offset from Bar center (px)
    cooldownBuffPosY    = 70,  -- Y offset below Bar bottom (px)
    cooldownBuffSpacing = 4,   -- vertical spacing between stacked icons (px)
    cooldownBuffNormalColor = {1, 1, 1, 1}, -- countdown text color
  }
}

-- Config Mode: shows static placeholder icons (real spell art, random dummy
-- duration) at every row's position regardless of combat/target/buff state,
-- and force-shows the Bar outside Cat Form — lets the user position
-- everything without needing a live target or active buffs. Deliberately a
-- plain runtime field, not part of db.profile — it's a one-off UI aid while
-- editing positions, not a setting worth persisting to SavedVariables or
-- carrying across a UI reload/relog. Lives on Addon (not a file-local)
-- since Options.lua's Config Mode toggle button needs to read/flip it too.
Addon.previewModeActive = false

-- Turns Config Mode on/off (called from Options.lua's toggle button). While
-- on, a short ticker keeps the dummy countdowns cycling — UpdatePreviewFrames
-- only re-rolls a frame's countdown once its previous one ran out, so
-- without this they'd stay at 0 after the first 1-15s until some other event
-- happens to call it. Off again, the ticker is gone: zero cost outside
-- Config Mode.
function Addon:SetPreviewMode(active)
  self.previewModeActive = active and true or false
  if self.previewTicker then
    self.previewTicker:Cancel()
    self.previewTicker = nil
  end
  if self.previewModeActive then
    self.previewTicker = C_Timer.NewTicker(0.5, function()
      self:UpdatePreviewFrames()
    end)
  end
  self:OnShapeshift()
end

-- "WoW Forever" (Blizzard's Classic-rules client on the modern engine, see
-- ThreatPlates' Init.lua) reports WOW_PROJECT_ID == MAINLINE but a Classic
-- era GetClassicExpansionLevel(). Same detection formula as ThreatPlates.
-- Lives on Addon so Options.lua (separate chunk) can read it too.
Addon.IS_FOREVER = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
  and type(GetClassicExpansionLevel) == "function"
  and type(GetClassicExpansionLevel()) == "number"
  and LE_EXPANSION_MISTS_OF_PANDARIA ~= nil
  and GetClassicExpansionLevel() <= LE_EXPANSION_MISTS_OF_PANDARIA
  or false

-- All spell IDs below are hardcoded, not user-configured — no Options input
-- field exists for any of them (was tried, reverted per explicit request).
-- Each slot is a LIST of aura spell IDs, not a single one: on Forever (Classic
-- rules) every rank of Rake/Rip/Tiger's Fury has its own spell ID, and any of
-- them may be the one that's up. An empty list = slot unused on that client
-- (its container/preview stays disabled, Options hides its row — see
-- Addon:IsSlotUsed). Retail IDs are the modern ones. Forever IDs were checked
-- against Wowhead's Forever database (nether.wowhead.com/forever/tooltip/spell/<id>):
-- each spell applies its own aura under the same ID (Rake/Rip debuffs, Tiger's
-- Fury/Berserk/Clearcasting buffs); Rake has 4 ranks, Rip 6, Tiger's Fury none.
local SPELL_SETS = {
  RETAIL = {
    debuffs = {{155722}, {1079}, {155625, 164812}}, -- Rake, Rip, Moonfire (Feral aura 155625 via Lunar Inspiration, not cast ID 8921; 164812 = regular Moonfire DoT when cast without it, outside Cat Form)
    buffs = {{135700}, {69369}, {}},             -- Clearcasting, Predatory Swiftness, (unused)
    cooldowns = {{5217}, {106951}, {102543}},    -- Tiger's Fury, Berserk, Incarnation
    cpBuffer = 405189,                           -- Überquellende Macht (combo point overflow buffer)
  },
  FOREVER = {
    debuffs = {
      {1822, 1823, 1824, 9904},                  -- Rake ranks 1-4
      {1079, 9492, 9493, 9752, 9894, 9896},      -- Rip ranks 1-6
      {},
    },
    buffs = {{16870}, {}, {}},                   -- Clearcasting (Omen of Clarity proc)
    cooldowns = {
      {5217},                                    -- Tiger's Fury (single spell, no ranks on Forever)
      {417141},                                  -- Berserk
    },
    cpBuffer = nil,                              -- no overflow buffer on Forever
  },
}
local Spells = Addon.IS_FOREVER and SPELL_SETS.FOREVER or SPELL_SETS.RETAIL

local function ToSpellSet(ids)
  local set = {}
  for _, spellID in ipairs(ids) do set[spellID] = true end
  return set
end

local NUM_DEBUFF_SLOTS = 3 -- covers Rake + Rip + (Moonfire on Retail) tracked simultaneously
local DEBUFF_SPELL_IDS = Spells.debuffs
local NUM_PLAYER_BUFF_SLOTS = 3 -- matches #PLAYER_BUFF_SPELL_IDS
local PLAYER_BUFF_SPELL_IDS = Spells.buffs
local COOLDOWN_BUFF_SPELL_IDS = Spells.cooldowns
local NUM_COOLDOWN_BUFF_SLOTS = #COOLDOWN_BUFF_SPELL_IDS
local CP_BUFFER_SPELL_ID = Spells.cpBuffer -- nil when this client has no overflow buffer

-- Precomputed includeSpellIDs sets (AuraContainer candidate filters), one per
-- slot, plus a single merged set for the cooldown-buff column.
local DEBUFF_SPELL_SETS, PLAYER_BUFF_SPELL_SETS, COOLDOWN_BUFF_SPELL_SET = {}, {}, {}
for i = 1, NUM_DEBUFF_SLOTS do DEBUFF_SPELL_SETS[i] = ToSpellSet(DEBUFF_SPELL_IDS[i] or {}) end
for i = 1, NUM_PLAYER_BUFF_SLOTS do PLAYER_BUFF_SPELL_SETS[i] = ToSpellSet(PLAYER_BUFF_SPELL_IDS[i] or {}) end
for _, ids in ipairs(COOLDOWN_BUFF_SPELL_IDS) do
  for _, spellID in ipairs(ids) do COOLDOWN_BUFF_SPELL_SET[spellID] = true end
end

-- Lets Options.lua (separate chunk) hide rows whose spell doesn't exist on
-- this client. row = "debuff" | "buff" | "cooldown".
function Addon:IsSlotUsed(row, index)
  local list = row == "debuff" and DEBUFF_SPELL_IDS
    or row == "buff" and PLAYER_BUFF_SPELL_IDS
    or COOLDOWN_BUFF_SPELL_IDS
  local ids = list[index]
  return ids ~= nil and #ids > 0
end

-- Lets Options.lua hide the overflow-buffer settings on clients without it.
function Addon:HasComboPointBuffer()
  return CP_BUFFER_SPELL_ID ~= nil
end

-- Secret values (Midnight-style restricted data, also on Forever) throw on
-- comparison/arithmetic/tostring — check before touching one from Lua.
local IsSecret = issecretvalue or function() return false end

-- Comma-joined spell ID list of one slot, for debug output.
local function SpellIdsText(ids)
  if not ids or #ids == 0 then return "unused" end
  return table.concat(ids, ",")
end

-- GetShapeshiftFormID() value for Cat Form. Spec-independent and stable
-- across stance-bar reordering, unlike the positional GetShapeshiftForm()
-- index (which shifts if not all forms are unlocked/visible).
local CAT_FORM_ID = 1

-- True while the Bar and every icon row are allowed to show (besides Config
-- Mode): Cat Form **and** in combat. Combat state comes from the
-- PLAYER_REGEN_* events (Addon.inCombat, see OnCombatStarted/OnCombatEnded)
-- with InCombatLockdown() as the fallback for a /reload mid-combat.
local function ShouldShowInCombat()
  return GetShapeshiftFormID() == CAT_FORM_ID and (Addon.inCombat or InCombatLockdown())
end
local Bar            -- StatusBar frame (set in CreateEnergyBar)

-- LibSharedMedia-3.0 (embedded via Libs/embeds.xml, see .toc) is
-- the single source of the shared Appearance-tab font/typeface — replaces
-- the old per-row GameFontXXX font-object selects entirely. `true` as the
-- 2nd LibStub arg means "don't error if missing", so the addon still works
-- (falling back to the bundled font) if LSM somehow isn't loaded.
local LSM = LibStub("LibSharedMedia-3.0", true)
local DEFAULT_FONT_KEY = "Cabin"

-- Bundled media (shipped in Media/, not dependent on the separate SharedMedia
-- data addon) — self-registered with LSM below so "Cabin"/"Smooth" are
-- always available as the Appearance-tab defaults even on a bare LSM install
-- with no other media-providing addon enabled. Registering under these exact
-- key names still lets LSM3.0 fully own the fetch/dropdown/live-switch path
-- everywhere else in the file (ApplyBarAppearance/GetAppearanceFontPath) —
-- nothing else needs to change.
local ADDON_FOLDER = "BloodInTheWater"
-- The bundled files double as the fallback when the saved key isn't
-- registered (e.g. the addon that provided it got disabled).
local FALLBACK_FONT_PATH = ([[Interface\AddOns\%s\Media\Cabin.ttf]]):format(ADDON_FOLDER)
local FALLBACK_BAR_TEXTURE_PATH = ([[Interface\AddOns\%s\Media\Smooth.tga]]):format(ADDON_FOLDER)
local FALLBACK_BORDER_PATH = ([[Interface\AddOns\%s\Media\PlainBorder.tga]]):format(ADDON_FOLDER)
if LSM then
  LSM:Register("font", "Cabin", FALLBACK_FONT_PATH)
  LSM:Register("statusbar", "Smooth", FALLBACK_BAR_TEXTURE_PATH)
  LSM:Register("border", "PlainBorder", FALLBACK_BORDER_PATH)
end

-- Resolves the Appearance tab's saved LSM font key to an actual font file
-- path. Falls back to the bundled font if the saved key was never
-- registered (e.g. the addon that registered it got disabled) — SetFont
-- silently no-ops on a bad path otherwise.
local function GetAppearanceFontPath(fontKey)
  if LSM then
    local path = LSM:Fetch("font", fontKey or DEFAULT_FONT_KEY, true)
    if path then return path end
  end
  return FALLBACK_FONT_PATH
end

-- AuraContainer/AuraButton (Patch 12.1.0+) is Blizzard's secret-safe aura
-- display path: once an addon calls container:SetUnit(unitToken), Blizzard's
-- own engine owns aura fetching/filtering/updating internally, so target
-- debuffs and player buffs update live without any addon-side C_UnitAuras
-- polling. Feature-detected via a template-existence check, matching
-- ThreatPlates' own guard, since there's no dedicated expansion-level flag.
local HasAuraContainers = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") and true or false
local AuraContainerSortMethod = _G.AuraContainerSortMethod
local AuraContainerSortDirection = _G.AuraContainerSortDirection

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------

function Addon:OnInitialize()
  -- Only active for Druids
  if select(2, UnitClass("player")) ~= "DRUID" then
    return
  end

  -- Initialize persistent database
  self.db = LibStub("AceDB-3.0"):New("BloodInTheWaterDB", Defaults, true)

  -- The Profiles tab (AceDBOptions) only swaps/copies/resets the saved data
  -- underneath db.profile — nothing repaints the live frames or the open
  -- config dialog by itself, so re-apply everything on every profile change.
  self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileRefresh")
  self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileRefresh")
  self.db.RegisterCallback(self, "OnProfileReset", "OnProfileRefresh")
  -- PLAYER_LOGOUT (also fired by /reload) makes AceDB strip the defaults out
  -- of db.profile — any handler still reading them afterwards would hit nil
  -- values, so stop reacting to anything once the database shuts down.
  self.db.RegisterCallback(self, "OnDatabaseShutdown", "OnDatabaseShutdown")
  -- Media registered after this addon loaded (other addons' LSM entries)
  -- must re-trigger the LSM-dependent visuals — see OnMediaRegistered.
  if LSM then
    LSM.RegisterCallback(self, "LibSharedMedia_Registered", "OnMediaRegistered")
  end

  -- Every spell ID (target debuffs, player buffs, cooldown buffs) is
  -- hardcoded per client (SPELL_SETS) — all rows are addon-owned frames,
  -- never Blizzard's own cooldown/aura viewer frames (see CreateEnergyBar).

  -- Create the energy bar.
  self:CreateEnergyBar()

  -- Register the configuration dialog
  self:SetupOptions()

  -- Register slash command /bitw
  self:RegisterChatCommand("bitw", "OpenConfig")
  -- Forever-port diagnostics (see CLAUDE.md, "Debugging") — disabled for
  -- release; uncomment to re-enable.
  -- self:RegisterChatCommand("bitwdebug", "DebugCheck")
  -- self:RegisterChatCommand("bitwauras", "ToggleAuraWatch")
end

-- Re-applies the (new) active profile to every live frame and refreshes the
-- open config dialog. Fired by AceDB on profile switch/copy/reset.
function Addon:OnProfileRefresh()
  self:UpdateBar()
  self:RefreshComboPoints()
  LibStub("AceConfigRegistry-3.0"):NotifyChange("BloodInTheWater")
end

-- AceDB fires this right before PLAYER_LOGOUT strips the profile defaults.
function Addon:OnDatabaseShutdown()
  self.isShuttingDown = true
  self:UnregisterAllEvents()
  if self.previewTicker then self.previewTicker:Cancel() end
  if LSM then LSM.UnregisterCallback(self, "LibSharedMedia_Registered") end
end

-- LSM fires this once per registered media entry, i.e. hundreds of times in a
-- burst while SharedMedia-style addons load — coalesce them into a single
-- refresh on the next frame.
function Addon:OnMediaRegistered()
  if self.mediaRefreshPending then return end
  self.mediaRefreshPending = true
  C_Timer.After(0, function()
    self.mediaRefreshPending = false
    if not self.isShuttingDown then
      self:RefreshMedia()
    end
  end)
end

function Addon:OnEnable()
  if select(2, UnitClass("player")) ~= "DRUID" then
    return
  end

  self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "OnShapeshift")
  self:RegisterEvent("UNIT_POWER_FREQUENT", "OnPowerUpdate")
  -- A combo-point reset on target switch is an infrequent, server-confirmed
  -- change and can arrive via UNIT_POWER_UPDATE instead of
  -- UNIT_POWER_FREQUENT (Forever) — the immediate OnTargetChanged read alone
  -- caught a stale pre-reset value. Same handler, already filters by unit/
  -- powerType.
  self:RegisterEvent("UNIT_POWER_UPDATE", "OnPowerUpdate")
  self:RegisterEvent("UNIT_MAXPOWER", "OnMaxPower")
  -- AceEvent-3.0 has no RegisterUnitEvent (that's a raw Frame method); the
  -- handler itself filters for unit == "player" below. Only drives the
  -- combo-point overflow buffer now — target/player aura display is fully
  -- event-driven by AuraContainer itself, no UNIT_AURA polling needed.
  self:RegisterEvent("UNIT_AURA", "OnUnitAura")
  self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
  -- AuraContainers cannot be created during combat; retries container
  -- creation here in case OnEnable itself ran mid-combat (e.g. /reload).
  self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnded")
  -- Bar/rows are combat-gated (see OnShapeshift) — refresh visibility the
  -- instant combat starts, don't wait for the next shapeshift/aura event.
  self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStarted")
  -- Re-applies LSM-dependent visuals once everything has fully loaded (see
  -- OnPlayerEnteringWorld) — fixes the saved bar texture/border/font
  -- sometimes reverting to the default after /reload.
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")

  self:OnCombatEnded() -- creates AuraContainers now if out of combat
  -- Evaluate initial shapeshift state immediately
  self:OnShapeshift()
end

function Addon:OnDisable()
  self:UnregisterAllEvents()
  self:SetPreviewMode(false)
  if Bar then
    Bar:Hide()
    Bar.bg:Hide()
    if Bar.debuffContainers then
      for _, container in ipairs(Bar.debuffContainers) do
        container:SetEnabled(false)
      end
    end
    if Bar.buffContainers then
      for _, container in ipairs(Bar.buffContainers) do
        container:SetEnabled(false)
      end
    end
    if Bar.cooldownBuffContainer then
      Bar.cooldownBuffContainer:SetEnabled(false)
    end
  end
end

-------------------------------------------------------------------------------
-- Frame creation
-------------------------------------------------------------------------------

function Addon:CreateEnergyBar()
  local db = self.db.profile

  -- Background frame (also carries the decorative border — see
  -- ApplyBarAppearance). BackdropTemplate mixin needed for SetBackdrop.
  local bg = CreateFrame("Frame", "BiTWEnergyBarBG", UIParent, "BackdropTemplate")
  bg:SetFrameStrata("BACKGROUND")
  bg:SetSize(db.width + 4, db.height + 4)
  bg:SetPoint("CENTER", UIParent, "CENTER", db.posX, db.posY)

  local bgTex = bg:CreateTexture(nil, "BACKGROUND")
  bgTex:SetAllPoints(bg)
  bgTex:SetColorTexture(0, 0, 0, 0.75)

  -- Energy status bar
  Bar = CreateFrame("StatusBar", "BiTWEnergyBar", UIParent)
  Bar:SetFrameStrata("LOW")
  Bar:SetSize(db.width, db.height)
  Bar:SetPoint("CENTER", UIParent, "CENTER", db.posX, db.posY)
  Bar:SetMinMaxValues(0, math.max(1, UnitPowerMax("player", 3)))
  Bar:SetValue(0)

  -- Numeric value centered on the bar
  local text = Bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  text:SetPoint("CENTER", Bar, "CENTER", 0, 0)
  text:SetTextColor(1, 1, 1, 1)
  Bar.text = text

  -- Combo point counter (child of Bar — auto-hides with Bar).
  local cpText = Bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  cpText:SetPoint("CENTER", Bar, "CENTER", db.cpPosX, db.cpPosY)
  cpText:SetTextColor(1, 1, 1, 1)
  cpText:SetText("0")
  Bar.cpText = cpText

  -- Combo point overflow buffer indicator (e.g. Berserk banking CPs above
  -- the cap). Hidden until the overflow buff (CP_BUFFER_SPELL_ID) has
  -- stacks; always hidden on clients without it (Forever).
  local cpBufferText = Bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  cpBufferText:SetPoint("CENTER", Bar, "CENTER", db.cpBufferPosX, db.cpBufferPosY)
  cpBufferText:SetTextColor(1, 0.85, 0.2, 1)
  cpBufferText:Hide()
  Bar.cpBufferText = cpBufferText

  -- Applies the shared Appearance-tab font/typeface to these three plain,
  -- addon-owned FontStrings — unlike the AuraButton-driven rows below, this
  -- is fully live-updatable (no create-time-only restriction), so it's also
  -- called again from UpdateBar whenever the Appearance font changes.
  self:ApplyGlobalFont()

  -- Target debuff icons (Rake/Rip/Moonfire) — one AuraContainer per fixed
  -- slot, each locked to a single spellID (DEBUFF_SPELL_IDS, hardcoded) via
  -- candidateFilters.includeSpellIDs. Created here (out of combat during
  -- ADDON_LOADED) and retried from OnCombatEnded if this ever runs
  -- mid-combat.
  self:CreateDebuffAuraContainers()

  Bar.bg = bg
  self:ApplyBarAppearance()

  -- NOTE: Never touch Blizzard's own EssentialCooldownViewer/
  -- BuffIconCooldownViewer frames (SetPoint/Show/Hide/Edit Mode settings,
  -- etc.) — doing so reliably tainted their secret aura data and crashed
  -- the client. The AuraContainers above are entirely addon-owned frames,
  -- fed via public, non-protected APIs instead.
  self:CreateBuffAuraContainers()
  self:CreateCooldownBuffAuraContainer()
  self:CreatePreviewFrames()

  self:RepositionDebuffContainers()
  self:RepositionBuffContainers()
  self:RepositionCooldownBuffContainer()
  self:RepositionPreviewFrames()
  self:UpdatePreviewFrames()

  Bar:Hide()
  bg:Hide()
end

-------------------------------------------------------------------------------
-- Aura icon buttons (shared by debuff slots and the player-buff row)
-------------------------------------------------------------------------------

-- Builds the Pandemic Glow region (either style) on any parent frame —
-- shared by InitializeAuraButton (real, secret-Shown-managed AuraButtons)
-- and the Config Mode Rake preview frame (plain, addon-owned, always-shown
-- while previewing). See the two branches below for the per-style detail.
local function CreatePandemicGlow(parent, iconSize, db)
  local pandemicGlow
  if db.pandemicStyle == "custom" then
    -- Plain outset border, modeled on ThreatPlates' own aura border
    -- (Widgets/AurasWidget.lua CreateAuraFrameIconMode): a BackdropTemplate
    -- frame outset a few px past the icon on all sides with a solid-color
    -- edge — no baked-in texture padding to fight, unlike a decorative
    -- border asset. WHITE8X8 is a plain opaque square, so the edge color
    -- comes entirely from SetBackdropBorderColor.
    -- Flush with the icon (no outset) — settled on this after testing wider
    -- values left a visible gap between border and icon edge.
    pandemicGlow = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pandemicGlow:SetAllPoints(parent)
    pandemicGlow:SetBackdrop({
      edgeFile = "Interface\\Buttons\\WHITE8X8",
      edgeSize = 1.5,
    })
    local pc = db.pandemicColor
    if pc then
      pandemicGlow:SetBackdropBorderColor(pc[1], pc[2], pc[3], pc[4] or 1)
    end
  else
    -- Blizzard's own "Assisted Combat" single-button highlight
    -- (ActionBarButtonAssistedCombatHighlightTemplate, see
    -- ActionButtonComponentTemplate.xml) uses an animated marching-ants
    -- flipbook atlas instead of a static border texture — their 45px frame
    -- holds a 66px (1.4667x) centered texture, but that ratio is
    -- calibrated for an action button whose icon is already inset within a
    -- larger button frame. Our icons fill the whole button (no inset), so
    -- the same ratio left a visible gap — 1.7x hugs the icon edge
    -- (including its rounded corners) instead. Tinted green (0,1,0,1)
    -- instead of db.pandemicColor for this first pass.
    pandemicGlow = parent:CreateTexture(nil, "OVERLAY")
    pandemicGlow:SetAtlas("rotationhelper_ants_flipbook")
    pandemicGlow:SetSize(iconSize * 1.7, iconSize * 1.7)
    pandemicGlow:SetPoint("CENTER", parent, "CENTER")
    pandemicGlow:SetVertexColor(0, 1, 0, 1)

    local pandemicGlowAnim = pandemicGlow:CreateAnimationGroup()
    pandemicGlowAnim:SetLooping("REPEAT")
    local pandemicGlowFlipBook = pandemicGlowAnim:CreateAnimation("FlipBook")
    pandemicGlowFlipBook:SetDuration(1)
    pandemicGlowFlipBook:SetOrder(0)
    pandemicGlowFlipBook:SetFlipBookRows(6)
    pandemicGlowFlipBook:SetFlipBookColumns(5)
    pandemicGlowFlipBook:SetFlipBookFrames(30)
    pandemicGlowFlipBook:SetFlipBookFrameWidth(0)
    pandemicGlowFlipBook:SetFlipBookFrameHeight(0)
    pandemicGlowAnim:Play()
  end
  return pandemicGlow
end

-- Configures one AuraButton's visuals: icon, cooldown swipe + countdown
-- number, stack count, and tooltip. Runs exactly once per physical button
-- (Blizzard's frame-pool provider calls this at creation, never again on
-- reuse), inside Blizzard's own securecallfunction wrapper — so every
-- Create*/Set* call here is safe even though AuraButton carries
-- AccessRestrictionFlags = DenyTaintedAccessWhenAurasAreSecret.
--
-- Icon size and font (typeface + size-relative-to-icon) come from the
-- shared Appearance-tab settings (db.appearanceIconSize/Font/FontScale),
-- read fresh here rather than passed in, since every row now uses the same
-- values. Only textColor still varies per row (Debuffs/Buffs/Cooldown
-- Buffs each keep their own color). This only covers brand-new buttons;
-- ReapplyLiveAuraButtonSettings below re-runs the same Set* calls on
-- already-created ones whenever these settings change out of combat.
--
-- CreateIconFrame (Config Mode preview icons) mirrors several of these
-- Set* calls on its own plain frames — TexCoord crop, SetDrawBling,
-- Stacks/stackText parented to Cooldown for the same z-order reason. The
-- two are separate implementations (secure AuraButton vs. plain Frame)
-- kept manually in sync; a change to one's visuals usually belongs on both.
local function InitializeAuraButton(auraButton, textColor, stacksX, stacksY)
  local db = Addon.db.profile
  local iconSize = db.appearanceIconSize

  auraButton.Icon = auraButton:CreateTexture(nil, "ARTWORK")
  auraButton.Icon:SetAllPoints(auraButton)
  -- Crops out the thin default border baked into the spell icon's own art
  -- (same crop CreateIconFrame already uses for its preview icons) —
  -- without it, that border shows through whenever the cooldown swipe
  -- doesn't happen to cover the very edge.
  auraButton.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  auraButton:SetIcon(auraButton.Icon)

  auraButton.Cooldown = CreateFrame("Cooldown", nil, auraButton, "CooldownFrameTemplate")
  auraButton.Cooldown:SetAllPoints(auraButton)
  auraButton.Cooldown:SetHideCountdownNumbers(false)
  -- Blizzard's stock "bling" flash plays on the swipe finishing/resetting —
  -- a debuff refreshed inside its pandemic window does exactly that, so
  -- without this it looked like a leftover thin white/gray border right
  -- where the (now-hidden) Pandemic Glow ring just was.
  auraButton.Cooldown:SetDrawBling(false)
  auraButton:SetDurationCooldown(auraButton.Cooldown)

  -- Parented to Cooldown (like the duration/countdown text below), not
  -- auraButton directly — Cooldown renders on an elevated internal frame
  -- level so its own text always draws above the icon; a plain OVERLAY
  -- fontstring parented straight to auraButton was landing behind it.
  auraButton.Stacks = auraButton.Cooldown:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  auraButton.Stacks:SetPoint("BOTTOMRIGHT", stacksX or 2, stacksY or -2)
  auraButton:SetApplicationCount(auraButton.Stacks)

  -- Pandemic (DoT refresh window) glow. AddPandemicRegion only ever drives
  -- the region's Shown state itself (AddSecretAspect(Shown) — confirmed in
  -- Blizzard_CustomAuraButton.lua); color is never marked secret, so plain
  -- addon code is free to set/re-set it any time, in or out of combat.
  -- AddPandemicRegion accepts any Region (Frame or Texture both qualify),
  -- so either style works. Style is creation-time only — like
  -- InitializeAuraButton itself, this runs once per pooled button, so
  -- switching db.pandemicStyle only takes effect for buttons created after
  -- the change (existing ones need a /reload).
  local pandemicGlow = CreatePandemicGlow(auraButton, iconSize, db)
  auraButton.PandemicGlow = pandemicGlow
  auraButton.PandemicGlowStyle = db.pandemicStyle
  auraButton:AddPandemicRegion(pandemicGlow)

  -- Same AuraButton tooltip gotcha ThreatPlates hit: SetMouseMotionEnabled
  -- alone isn't enough, SetTooltipAnchorPoint must be called at least once
  -- or ShowTooltip() gets a nil anchor and nothing ever appears.
  auraButton:SetTooltipAnchorPoint("ANCHOR_RIGHT")
  auraButton:SetMouseMotionEnabled(true)
  auraButton:SetHideTooltipInCombat(false)

  PixelUtil.SetSize(auraButton, iconSize, iconSize)

  local fontPath = GetAppearanceFontPath(db.appearanceFont)
  local fontSize = math.max(6, math.floor(iconSize * (db.appearanceFontScale or 0.5)))

  local fs = auraButton.Cooldown:GetCountdownFontString()
  if fs then
    fs:SetFont(fontPath, fontSize, "")
    if textColor then
      fs:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)
    end
  end
  auraButton.Stacks:SetFont(fontPath, fontSize, "")
end

-- Re-runs InitializeAuraButton's icon-size/font/color Set* calls on every
-- already-created AuraButton across all 3 aura rows (Debuffs/Proccs/
-- Cooldowns), so Appearance/color changes take effect immediately instead
-- of needing /reload. Confirmed safe by ThreatPlates' own live testing:
-- these are plain Set* calls, not aura-data reads, and AuraButton's
-- AccessRestrictionFlags = DenyTaintedAccessWhenAurasAreSecret only blocks
-- them while genuinely in combat/secret-aura territory — out of combat
-- (the InCombatLockdown guard here) they're safe from plain addon code.
-- Only ever called out of combat; OnCombatEnded retries it once combat
-- ends in case a change happened mid-fight. GetAuraGroupFrame/
-- GetAuraGroupFrameCount are real (non-Forbidden) AuraContainer methods,
-- so every already-pooled button, active or not, is reachable this way.
function Addon:ReapplyLiveAuraButtonSettings()
  if not HasAuraContainers or not Bar then return end
  if InCombatLockdown() then return end

  local db = self.db.profile
  local iconSize = db.appearanceIconSize
  local fontPath = GetAppearanceFontPath(db.appearanceFont)
  local fontSize = math.max(6, math.floor(iconSize * (db.appearanceFontScale or 0.5)))

  local function ReapplyContainer(container, textColor, stacksX, stacksY)
    for i = 1, container:GetAuraGroupFrameCount("main") do
      local auraButton = container:GetAuraGroupFrame("main", i)
      if auraButton then
        PixelUtil.SetSize(auraButton, iconSize, iconSize)
        local fs = auraButton.Cooldown and auraButton.Cooldown:GetCountdownFontString()
        if fs then
          fs:SetFont(fontPath, fontSize, "")
          if textColor then
            fs:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)
          end
        end
        if auraButton.Stacks then
          auraButton.Stacks:SetFont(fontPath, fontSize, "")
          if stacksX then
            auraButton.Stacks:ClearAllPoints()
            auraButton.Stacks:SetPoint("BOTTOMRIGHT", stacksX, stacksY or -2)
          end
        end
        if auraButton.PandemicGlow then
          if auraButton.PandemicGlowStyle == "custom" then
            -- Fixed pixel outset regardless of icon size (matches
            -- ThreatPlates' own border), so only color follows live.
            local pc = db.pandemicColor
            if pc then
              auraButton.PandemicGlow:SetBackdropBorderColor(pc[1], pc[2], pc[3], pc[4] or 1)
            end
          else
            -- Color is hardcoded green at creation (InitializeAuraButton)
            -- for this flipbook style, not wired to db.pandemicColor yet,
            -- so only size needs re-applying live.
            auraButton.PandemicGlow:SetSize(iconSize * 1.7, iconSize * 1.7)
          end
        end
      end
    end
  end

  if Bar.debuffContainers then
    for _, container in ipairs(Bar.debuffContainers) do
      ReapplyContainer(container, db.debuffNormalColor)
    end
  end
  if Bar.buffContainers then
    for _, container in ipairs(Bar.buffContainers) do
      ReapplyContainer(container, db.buffNormalColor, db.buffStacksPosX, db.buffStacksPosY)
    end
  end
  if Bar.cooldownBuffContainer then
    ReapplyContainer(Bar.cooldownBuffContainer, db.cooldownBuffNormalColor)
  end
end

-- Re-applies the shared Appearance-tab font (typeface + icon-relative size),
-- plus each row's countdown-text color, to the plain, non-AuraButton Config
-- Mode preview icons, which CreateIconFrame only styles once at creation
-- time. Unlike ReapplyLiveAuraButtonSettings this needs no combat guard:
-- these are plain frames, never secret aura buttons.
function Addon:ReapplyLiveIconFrameFonts()
  if not Bar then return end

  local db = self.db.profile
  local fontPath = GetAppearanceFontPath(db.appearanceFont)
  local size = db.appearanceIconSize
  local fontSize = math.max(6, math.floor(size * (db.appearanceFontScale or 0.5)))

  local function ApplyFont(frame, textColor)
    local countdownFS = frame.countdownFS or (frame.cooldown and frame.cooldown:GetCountdownFontString())
    if countdownFS then
      countdownFS:SetFont(fontPath, fontSize, "")
      if textColor then
        countdownFS:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)
      end
    end
    if frame.stackText then
      frame.stackText:SetFont(fontPath, fontSize, "")
    end
  end

  if Bar.previewDebuff then
    for _, frame in ipairs(Bar.previewDebuff) do
      ApplyFont(frame, db.debuffNormalColor)
    end
  end
  if Bar.previewPlayerBuff then
    for _, frame in ipairs(Bar.previewPlayerBuff) do
      ApplyFont(frame, db.buffNormalColor)
    end
  end
  if Bar.previewCooldownBuff then
    for _, frame in ipairs(Bar.previewCooldownBuff) do
      ApplyFont(frame, db.cooldownBuffNormalColor)
    end
  end
end

-------------------------------------------------------------------------------
-- Target debuff icons (AuraContainer, unit = target)
-------------------------------------------------------------------------------

-- Creates the 3 fixed-slot AuraContainers, one per tracked debuff spellID.
-- Each is single-purpose (maxFrameCount 1, one spellID via
-- candidateFilters.includeSpellIDs) rather than one shared multi-group
-- container, since these slots need fixed screen positions (slot i always
-- shows DEBUFF_SPELL_IDS[i]), not a sorted flow grid.
--
-- AuraContainers cannot be created during combat — guarded here and retried
-- from OnCombatEnded.
function Addon:CreateDebuffAuraContainers()
  if not HasAuraContainers then return end
  if InCombatLockdown() then return end
  if Bar.debuffContainers and #Bar.debuffContainers > 0 then return end

  local db = self.db.profile
  Bar.debuffContainers = {}
  for i = 1, NUM_DEBUFF_SLOTS do
    local container = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    container:AddAuraGroup("main", "HARMFUL", {
      initializeFrame = function(auraButton)
        InitializeAuraButton(auraButton, db.debuffNormalColor)
      end,
      sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Default,
      sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal,
    })
    -- Required even for a single-icon group — without an explicit flow
    -- layout anchor/growth direction, the container never lays out (and
    -- thus never shows) its AuraButton at all. Same "LEFT" + Right/Down
    -- values as the player-buff/cooldown-buff containers below, which are
    -- confirmed working live.
    container:SetFlowLayoutAnchorPoint("LEFT")
    container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    container:SetEnabled(false)
    Bar.debuffContainers[i] = container
  end
end

-- Pushes today's DEBUFF_SPELL_IDS / Cat Form + combat / target state into each
-- debuff slot container. Safe to call live, including mid-combat — these
-- are the same container-level filter/unit setters ThreatPlates calls from
-- plain addon code on every target change (only frame *creation* above is
-- combat-gated).
function Addon:UpdateDebuffContainerFilters()
  if not HasAuraContainers or not Bar.debuffContainers then return end

  local db = self.db.profile
  -- Config Mode owns this screen space instead — avoids the real container
  -- and the static preview icon double-rendering at the same position.
  if Addon.previewModeActive then
    for _, container in ipairs(Bar.debuffContainers) do
      container:SetEnabled(false)
    end
    return
  end

  local showRow = ShouldShowInCombat()
  for i = 1, NUM_DEBUFF_SLOTS do
    local container = Bar.debuffContainers[i]
    if container then
      if showRow and self:IsSlotUsed("debuff", i) then
        container:SetUnit("target")
        container:SetAuraGroupFilterString("main", "HARMFUL|PLAYER")
        container:SetAuraGroupCandidateFilters("main", { includeSpellIDs = DEBUFF_SPELL_SETS[i] })
        container:SetAuraGroupMaxFrameCount("main", 1)
        container:SetAuraGroupLayout("main", { elementWidth = db.appearanceIconSize, elementHeight = db.appearanceIconSize })
        container:SetFlowLayoutMaximumLineSize(db.appearanceIconSize)
        container:SetEnabled(true)
      else
        container:SetEnabled(false)
      end
    end
  end
end

-- Each slot is independently positioned (debuffOffsets[i] = {x, y}, relative
-- to the energy bar's own center) instead of a shared base + computed
-- spacing — the user can freely arrange all 3 debuff icons anywhere.
function Addon:RepositionDebuffContainers()
  if not Bar or not Bar.debuffContainers then return end

  local db = self.db.profile
  for i, container in ipairs(Bar.debuffContainers) do
    local o = db.debuffOffsets[i] or { x = 0, y = 0 }
    container:ClearAllPoints()
    container:SetPoint("CENTER", Bar, "CENTER", o.x, o.y)
  end
end

-------------------------------------------------------------------------------
-- Player buff row (AuraContainer, unit = player)
-------------------------------------------------------------------------------

-- Creates the 3 fixed-slot AuraContainers, one per tracked buff spellID —
-- same architecture as CreateDebuffAuraContainers (single-purpose,
-- maxFrameCount 1, one spellID via candidateFilters.includeSpellIDs),
-- individually positioned instead of a shared flow-layout row.
function Addon:CreateBuffAuraContainers()
  if not HasAuraContainers then return end
  if InCombatLockdown() then return end
  if Bar.buffContainers and #Bar.buffContainers > 0 then return end

  local db = self.db.profile
  Bar.buffContainers = {}
  for i = 1, NUM_PLAYER_BUFF_SLOTS do
    local container = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    container:AddAuraGroup("main", "HELPFUL", {
      initializeFrame = function(auraButton)
        InitializeAuraButton(auraButton, db.buffNormalColor, db.buffStacksPosX, db.buffStacksPosY)
      end,
      sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Default,
      sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal,
    })
    container:SetFlowLayoutAnchorPoint("LEFT")
    container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    container:SetEnabled(false)
    Bar.buffContainers[i] = container
  end
end

-- Pushes today's PLAYER_BUFF_SPELL_IDS / Cat Form + combat state into each buff
-- slot container. Safe to call live (same reasoning as UpdateDebuffContainerFilters).
function Addon:UpdateBuffContainerFilters()
  if not HasAuraContainers or not Bar.buffContainers then return end

  local db = self.db.profile
  if Addon.previewModeActive then
    for _, container in ipairs(Bar.buffContainers) do
      container:SetEnabled(false)
    end
    return
  end

  local showRow = ShouldShowInCombat()
  for i = 1, NUM_PLAYER_BUFF_SLOTS do
    local container = Bar.buffContainers[i]
    if container then
      if showRow and self:IsSlotUsed("buff", i) then
        container:SetUnit("player")
        container:SetAuraGroupFilterString("main", "HELPFUL|PLAYER")
        container:SetAuraGroupCandidateFilters("main", { includeSpellIDs = PLAYER_BUFF_SPELL_SETS[i] })
        container:SetAuraGroupMaxFrameCount("main", 1)
        container:SetAuraGroupLayout("main", { elementWidth = db.appearanceIconSize, elementHeight = db.appearanceIconSize })
        container:SetFlowLayoutMaximumLineSize(db.appearanceIconSize)
        container:SetEnabled(true)
      else
        container:SetEnabled(false)
      end
    end
  end
end

-- Each slot is independently positioned (buffOffsets[i] = {x, y}, relative
-- to the energy bar's own center) — same freeform-per-slot model as
-- RepositionDebuffContainers.
function Addon:RepositionBuffContainers()
  if not Bar or not Bar.buffContainers then return end

  local db = self.db.profile
  for i, container in ipairs(Bar.buffContainers) do
    local o = db.buffOffsets[i] or { x = 0, y = 0 }
    container:ClearAllPoints()
    container:SetPoint("CENTER", Bar, "CENTER", o.x, o.y)
  end
end

-------------------------------------------------------------------------------
-- Cooldown-buff row (AuraContainer, unit = player, sorted by remaining time)
-------------------------------------------------------------------------------

-- Separate from the general player-buff container above: Tiger's Fury/
-- Berserk/Incarnation by default, sorted by AuraContainerSortMethod.
-- Expiration (soonest-expiring first) instead of default/insertion order —
-- the sort criterion is why this needs its own container rather than just
-- more slots on the existing one (a single AddAuraGroup only has one sort
-- method for everything in it).
-- Vertically stacked (anchor "TOP", growth Down) instead of a horizontal
-- row: MaximumLineSize is pinned to exactly one icon's width in
-- UpdateCooldownBuffContainerFilters below, so the flow layout wraps to a
-- new line after every single icon — the standard trick for forcing a
-- single-column layout out of a row/wrap-based flow layout, since
-- SetFlowLayoutGrowthDirection's primary axis is always horizontal.
function Addon:CreateCooldownBuffAuraContainer()
  if not HasAuraContainers then return end
  if InCombatLockdown() then return end
  if Bar.cooldownBuffContainer then return end

  local db = self.db.profile
  local container = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
  container:AddAuraGroup("main", "HELPFUL", {
    initializeFrame = function(auraButton)
      InitializeAuraButton(auraButton, db.cooldownBuffNormalColor)
    end,
    sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Expiration,
    sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal,
  })
  container:SetFlowLayoutAnchorPoint("TOP")
  container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
  container:SetEnabled(false)
  Bar.cooldownBuffContainer = container
end

-- Pushes today's COOLDOWN_BUFF_SPELL_IDS / Cat Form + combat state into the container.
-- Safe to call live (same reasoning as UpdateBuffContainerFilters).
function Addon:UpdateCooldownBuffContainerFilters()
  if not HasAuraContainers or not Bar.cooldownBuffContainer then return end

  local db = self.db.profile
  local container = Bar.cooldownBuffContainer
  -- Config Mode owns this screen space instead — see UpdateDebuffContainerFilters.
  if Addon.previewModeActive then
    container:SetEnabled(false)
    return
  end

  local showRow = ShouldShowInCombat()
  if not showRow then
    container:SetEnabled(false)
    return
  end

  if next(COOLDOWN_BUFF_SPELL_SET) == nil then
    container:SetEnabled(false)
    return
  end

  container:SetUnit("player")
  container:SetAuraGroupFilterString("main", "HELPFUL|PLAYER")
  container:SetAuraGroupCandidateFilters("main", { includeSpellIDs = COOLDOWN_BUFF_SPELL_SET })
  container:SetAuraGroupMaxFrameCount("main", NUM_COOLDOWN_BUFF_SLOTS)
  container:SetAuraGroupLayout("main", {
    elementWidth = db.appearanceIconSize,
    elementHeight = db.appearanceIconSize,
    elementSpacing = db.cooldownBuffSpacing, -- unused (only 1 per line) but harmless
    lineSpacing = db.cooldownBuffSpacing,    -- vertical gap between stacked icons
  })
  -- No room for a 2nd icon on the same "line" — forces one icon per line.
  container:SetFlowLayoutMaximumLineSize(db.appearanceIconSize)
  container:SetEnabled(true)
end

function Addon:RepositionCooldownBuffContainer()
  if not Bar or not Bar.cooldownBuffContainer then return end

  local db = self.db.profile
  Bar.cooldownBuffContainer:ClearAllPoints()
  Bar.cooldownBuffContainer:SetPoint("TOP", Bar, "BOTTOM", db.cooldownBuffPosX or 0, db.cooldownBuffPosY or -80)
end

-------------------------------------------------------------------------------
-- Config Mode preview icon frames (plain, non-AuraButton)
-------------------------------------------------------------------------------

-- Creates a single icon: a texture plus a real Cooldown widget (visible
-- swipe + countdown number). Used only for Config Mode's preview icons —
-- the debuff/buff/cooldown-buff rows themselves use real AuraButtons
-- instead, this is purely their fake-data stand-in while positioning.
-- Own plain frame (not an AuraButton), so — unlike InitializeAuraButton —
-- its font styling isn't create-time-locked; kept consistent with it anyway
-- since this only ever runs once per preview icon too (created once at
-- startup, see CreatePreviewFrames).
function Addon:CreateIconFrame(parent, size)
  local db = self.db.profile
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(size, size)

  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(frame)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  frame.icon = icon

  local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
  cooldown:SetAllPoints(frame)
  cooldown:SetHideCountdownNumbers(false)
  -- Matches InitializeAuraButton's identical call — keeps the preview's
  -- cooldown flash behavior consistent with the real icons it's mimicking.
  cooldown:SetDrawBling(false)
  frame.cooldown = cooldown

  local fontPath = GetAppearanceFontPath(db.appearanceFont)
  local fontSize = math.max(6, math.floor(size * (db.appearanceFontScale or 0.5)))
  local countdownFS = cooldown:GetCountdownFontString()
  if countdownFS then
    countdownFS:SetFont(fontPath, fontSize, "")
  end
  frame.countdownFS = countdownFS

  -- Parented to cooldown, not frame — see InitializeAuraButton's identical
  -- Stacks change for why (Cooldown's elevated frame level keeps its own
  -- text above the icon; a plain child of frame was landing behind it).
  -- Only ever used for the Config Mode stack-count preview (Clearcasting) —
  -- named for what it shows, not where it came from.
  local stackText = cooldown:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  stackText:SetFont(fontPath, fontSize, "")
  stackText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
  stackText:Hide()
  frame.stackText = stackText

  frame:Hide()
  return frame
end

-------------------------------------------------------------------------------
-- Config Mode preview icons (debuff/player-buff/cooldown-buff rows)
-------------------------------------------------------------------------------

-- Own addon-owned frames, entirely separate from the real AuraContainers —
-- per ThreatPlates' own Midnight research, AuraContainer/AuraButton has no
-- demo/preview mechanism at all (it only ever shows real data for a real
-- SetUnit() token), so faking it means bypassing AuraContainer completely
-- and reusing the same plain Frame+Texture+Cooldown pattern instead. Created
-- once at startup from CreateEnergyBar, hidden until Config Mode is turned
-- on (not combat-gated — these are plain frames, not AuraContainers, so unlike
-- CreateDebuffAuraContainers this never needs to wait for combat to end).
function Addon:CreatePreviewFrames()
  if Bar.previewDebuff then return end

  local db = self.db.profile
  local size = db.appearanceIconSize
  Bar.previewDebuff = {}
  for i = 1, NUM_DEBUFF_SLOTS do
    Bar.previewDebuff[i] = self:CreateIconFrame(UIParent, size)
  end
  -- Rake (slot 1) always shows its Pandemic Glow in Config Mode — unlike a
  -- real AuraButton's Shown state, this one isn't secret, so it's just
  -- created once here and left permanently shown (UpdatePreviewFrames only
  -- ever hides the whole preview icon, never this specifically).
  Bar.previewDebuff[1].PandemicGlow = CreatePandemicGlow(Bar.previewDebuff[1], size, db)
  Bar.previewPlayerBuff = {}
  for i = 1, NUM_PLAYER_BUFF_SLOTS do
    Bar.previewPlayerBuff[i] = self:CreateIconFrame(UIParent, size)
  end
  Bar.previewCooldownBuff = {}
  for i = 1, NUM_COOLDOWN_BUFF_SLOTS do
    Bar.previewCooldownBuff[i] = self:CreateIconFrame(UIParent, size)
  end
end

-- Rebuilds the Rake preview's Pandemic Glow from scratch — unlike a real
-- AuraButton, this one was never handed to AddPandemicRegion/isn't
-- secret-managed, so (unlike the real-button style, which needs /reload)
-- switching db.pandemicStyle can just tear down and recreate it live. Only
-- needed for a style change (different widget type entirely); color/size
-- tweaks use the lighter ReapplyPandemicPreviewGlowSettings below instead.
function Addon:ReapplyPandemicPreviewGlow()
  if not Bar or not Bar.previewDebuff or not Bar.previewDebuff[1] then return end

  local db = self.db.profile
  local frame = Bar.previewDebuff[1]
  if frame.PandemicGlow then
    frame.PandemicGlow:Hide()
    frame.PandemicGlow:SetParent(nil)
  end
  frame.PandemicGlow = CreatePandemicGlow(frame, db.appearanceIconSize, db)
end

-- Updates the existing Rake preview glow in place (color for Simple Border,
-- size for WoW Border) — mirrors ReapplyLiveAuraButtonSettings' per-style
-- handling for real buttons. Safe to call on every UpdateBar; unlike
-- ReapplyPandemicPreviewGlow it never tears the widget down, so it won't
-- restart the WoW-style flipbook animation on unrelated setting changes.
function Addon:ReapplyPandemicPreviewGlowSettings()
  if not Bar or not Bar.previewDebuff or not Bar.previewDebuff[1] then return end

  local frame = Bar.previewDebuff[1]
  local glow = frame.PandemicGlow
  if not glow then return end

  local db = self.db.profile
  if db.pandemicStyle == "custom" then
    local pc = db.pandemicColor
    if pc then
      glow:SetBackdropBorderColor(pc[1], pc[2], pc[3], pc[4] or 1)
    end
  else
    local size = db.appearanceIconSize
    glow:SetSize(size * 1.7, size * 1.7)
  end
end

-- Positions the preview frames at exactly the same coordinates as the real
-- debuff/buff slot containers / cooldown-buff column, using the identical
-- math as the real Reposition* functions, so what the user arranges in
-- Config Mode matches the real layout exactly (including the cooldown-buff
-- column being vertical, not a horizontal row).
function Addon:RepositionPreviewFrames()
  if not Bar or not Bar.previewDebuff then return end

  local db = self.db.profile
  local size = db.appearanceIconSize

  for i, frame in ipairs(Bar.previewDebuff) do
    local o = db.debuffOffsets[i] or { x = 0, y = 0 }
    frame:SetSize(size, size)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", Bar, "CENTER", o.x, o.y)
  end

  for i, frame in ipairs(Bar.previewPlayerBuff) do
    local o = db.buffOffsets[i] or { x = 0, y = 0 }
    frame:SetSize(size, size)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", Bar, "CENTER", o.x, o.y)
  end

  -- Vertical stack, top-down — matches CreateCooldownBuffAuraContainer's
  -- SetFlowLayoutAnchorPoint("TOP") + pinned MaximumLineSize.
  local cdStep = size + (db.cooldownBuffSpacing or 8)
  for i, frame in ipairs(Bar.previewCooldownBuff) do
    frame:SetSize(size, size)
    frame:ClearAllPoints()
    frame:SetPoint("TOP", Bar, "BOTTOM", db.cooldownBuffPosX or 0, (db.cooldownBuffPosY or -80) - (i - 1) * cdStep)
  end
end

-- Feeds each preview frame the real spell's icon art (a plain, non-secret
-- texture lookup — safe regardless of combat/aura state) plus a dummy
-- Cooldown (random 1-15s per icon, set via plain Cooldown:SetCooldown —
-- never SetCooldownFromDurationObject/secret aura data). Shows/hides the
-- whole set based on Addon.previewModeActive. This runs on every OnShapeshift/
-- UpdateBar call and every 0.5s from the Config Mode ticker (see
-- SetPreviewMode), so each frame only re-rolls/restarts its countdown once the
-- previous one has actually run out — otherwise it'd get reset to full on
-- every call and never reach 0.
function Addon:UpdatePreviewFrames()
  if not Bar or not Bar.previewDebuff then return end

  local show = Addon.previewModeActive

  local db = self.db.profile

  -- spellIDs = list of per-slot ID lists (see SPELL_SETS); the first ID of a
  -- slot supplies the icon art, later ones are just further ranks of it.
  local function FeedRow(frames, spellIDs, stackCounts)
    for i, frame in ipairs(frames) do
      if show then
        local spellID = spellIDs[i] and spellIDs[i][1]
        if spellID and spellID > 0 then
          frame.icon:SetTexture(C_Spell.GetSpellTexture(spellID))
          if not frame.previewExpire or GetTime() >= frame.previewExpire then
            local duration = math.random(1, 15)
            frame.previewExpire = GetTime() + duration
            frame.cooldown:SetCooldown(GetTime(), duration)
          end
          local stacks = stackCounts and stackCounts[i]
          if stacks and frame.stackText then
            frame.stackText:ClearAllPoints()
            frame.stackText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", db.buffStacksPosX or 2, db.buffStacksPosY or -2)
            frame.stackText:SetText(stacks)
            frame.stackText:Show()
          elseif frame.stackText then
            frame.stackText:Hide()
          end
          frame:Show()
        else
          frame:Hide()
        end
      else
        frame.previewExpire = nil
        frame:Hide()
      end
    end
  end

  FeedRow(Bar.previewDebuff, DEBUFF_SPELL_IDS)
  -- Clearcasting (slot 1) previews a 2-stack so the Stacks X/Y Offset
  -- option (Proccs tab) can be tuned without needing a real proc up. Not on
  -- Forever: its Clearcasting (Omen of Clarity) never stacks.
  FeedRow(Bar.previewPlayerBuff, PLAYER_BUFF_SPELL_IDS, not Addon.IS_FOREVER and {2} or nil)
  FeedRow(Bar.previewCooldownBuff, COOLDOWN_BUFF_SPELL_IDS)
end

-------------------------------------------------------------------------------
-- Helper functions
-------------------------------------------------------------------------------

-- Applies the shared Icons-tab font/typeface to the 3 plain FontStrings
-- the addon fully owns (Bar.text/cpText/cpBufferText) — unlike the
-- AuraButton countdown texts, these have no create-time-only
-- restriction, so this is genuinely live: called once at creation and again
-- whenever appearanceFont changes. Point sizes stay their own independent
-- fields (cpFontSize/cpBufferFontSize) — only the typeface is shared here,
-- not the icon-relative sizing InitializeAuraButton/CreateIconFrame use.
function Addon:ApplyGlobalFont()
  if not Bar then return end

  local db = self.db.profile
  local fontPath = GetAppearanceFontPath(db.appearanceFont)

  if Bar.text then
    Bar.text:SetFont(fontPath, db.barFontSize or 12, "")
  end
  if Bar.cpText then
    Bar.cpText:SetFont(fontPath, db.cpFontSize, "")
  end
  if Bar.cpBufferText then
    Bar.cpBufferText:SetFont(fontPath, db.cpBufferFontSize, "")
  end
end

-- Applies the LibSharedMedia bar-fill texture and the decorative border
-- (texture/thickness/inset/color) to the plain, addon-owned Bar/Bar.bg
-- frames — neither is an AuraButton, so this is always safe to call live,
-- no combat gating needed. The border lives on Bar.bg (already sized 4px
-- larger than Bar) via SetBackdrop's edgeFile, not on Bar itself, so it
-- frames the bar from the outside without interfering with the status
-- bar's own fill texture.
function Addon:ApplyBarAppearance()
  if not Bar or not Bar.bg then return end

  local db = self.db.profile
  local barTexturePath = LSM and LSM:Fetch("statusbar", db.barTexture, true)
  Bar:SetStatusBarTexture(barTexturePath or FALLBACK_BAR_TEXTURE_PATH)

  local bc = db.barColor
  Bar:SetStatusBarColor(bc[1], bc[2], bc[3], bc[4] or 1)

  if Bar.bg.SetBackdrop then
    -- Clearing first, then setting fresh, rather than just re-calling
    -- SetBackdrop with updated edgeSize/insets in place: confirmed live
    -- that an in-place re-call left edgeSize/color stuck at their
    -- create-time values until /reload — BackdropTemplateMixin appears to
    -- cache/reuse the border regions' layout keyed off the backdrop table
    -- rather than fully recomputing them on every SetBackdrop call. A nil
    -- reset forces it to tear down and rebuild from scratch every time.
    Bar.bg:SetBackdrop(nil)

    local borderPath = (LSM and LSM:Fetch("border", db.barBorderTexture, true)) or FALLBACK_BORDER_PATH
    Bar.bg:SetBackdrop({
      edgeFile = borderPath,
      edgeSize = db.barBorderSize,
      insets = {
        left = db.barBorderInset, right = db.barBorderInset,
        top = db.barBorderInset, bottom = db.barBorderInset,
      },
    })
    local c = db.barBorderColor
    Bar.bg:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
    -- The freshly (re)created backdrop's edge regions occasionally settle
    -- back to full alpha a frame after SetBackdrop returns (the RGB
    -- portion sticks immediately, only alpha snaps back) — reapplying
    -- once more next frame wins that race instead of leaving the border
    -- stuck opaque.
    C_Timer.After(0, function()
      if Bar and Bar.bg and Bar.bg.SetBackdropBorderColor then
        Bar.bg:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
      end
    end)
  end
end

-- Updates position, size, and values of the bar from the database.
function Addon:UpdateBar()
  if not Bar then
    return
  end

  local db = self.db.profile

  Bar.bg:ClearAllPoints()
  Bar.bg:SetSize(db.width + 4, db.height + 4)
  Bar.bg:SetPoint("CENTER", UIParent, "CENTER", db.posX, db.posY)

  Bar:ClearAllPoints()
  Bar:SetSize(db.width, db.height)
  Bar:SetPoint("CENTER", UIParent, "CENTER", db.posX, db.posY)

  self:ApplyBarAppearance()
  self:RepositionDebuffContainers()
  self:RepositionBuffContainers()
  self:RepositionCooldownBuffContainer()
  self:RepositionPreviewFrames()
  self:UpdateDebuffContainerFilters()
  self:UpdateBuffContainerFilters()
  self:UpdateCooldownBuffContainerFilters()
  self:UpdatePreviewFrames()
  self:ReapplyLiveAuraButtonSettings()
  self:ReapplyLiveIconFrameFonts()
  -- Keeps the Rake preview's Pandemic Glow (icon size, WoW-style ring size)
  -- in sync with any setting that goes through UpdateBar.
  self:ReapplyPandemicPreviewGlowSettings()

  -- Reposition the combo point text.
  if Bar.cpText then
    Bar.cpText:ClearAllPoints()
    Bar.cpText:SetPoint("CENTER", Bar, "CENTER", db.cpPosX, db.cpPosY)
  end

  -- Reposition the combo point overflow buffer indicator.
  if Bar.cpBufferText then
    Bar.cpBufferText:ClearAllPoints()
    Bar.cpBufferText:SetPoint("CENTER", Bar, "CENTER", db.cpBufferPosX, db.cpBufferPosY)
  end

  self:ApplyGlobalFont()

  local current = UnitPower("player", 3)
  local max = math.max(1, UnitPowerMax("player", 3))
  Bar:SetMinMaxValues(0, max)
  Bar:SetValue(current)
  if Bar.text then
    Bar.text:SetText(current)
  end
end

-- Colors the combo point counter via a step ColorCurve, expressed in
-- *percent of max* (breakpoint / max) so it can be driven by UnitPowerPercent
-- below. Same 0 / 1-3 / 4 / 5+ tiers as the old plain-compare version.
--
-- LuaColorCurveObject:Evaluate(x) takes the secret combo-point count as an
-- explicit Lua argument, and is only SecretArguments="AllowedWhenUntainted"
-- (LuaColorCurveObjectAPIDocumentation.lua) — confirmed live: errors
-- ("Secret values are only allowed during untainted execution for this
-- argument") the instant it's called while in combat, which is the one time
-- this bar is ever shown. UnitPowerPercent(unit, powerType, unmodified,
-- curve) (UnitDocumentation.lua) instead reads the (possibly secret) power
-- value AND evaluates the curve entirely C-side — the secret number never
-- crosses into Lua as an argument, so the AllowedWhenUntainted restriction
-- never triggers. Same pattern ThreatPlates uses for health
-- (UnitHealthPercent(unit, true, curve), Elements/StatusText.lua) instead of
-- calling a health color curve's :Evaluate() directly.
--
-- Used on both clients (see RefreshComboPoints) - it evaluates the color
-- from UnitPower("player", 4) via a C-side sink regardless of which API cp
-- itself came from, since that's what's secret-safe. A prior attempt at a
-- plain-Lua color threshold on Forever's cp (from GetComboPoints) crashed
-- live ("attempt to compare ... secret number value"): GetComboPoints is
-- just as secret as UnitPower when called from this addon's own tainted
-- execution. (An earlier /run print() test had seen a plain number and
-- wrongly suggested otherwise - that was reading from an untainted
-- console context, not comparable to code running inside the addon.)
local ComboPointColorCurve

local function BuildComboPointColorCurve()
  local db = Addon.db.profile
  local max = UnitPowerMax("player", 4)
  local curve = ComboPointColorCurve or C_CurveUtil.CreateColorCurve()
  curve:SetType(Enum.LuaCurveType.Step)
  curve:ClearPoints()
  curve:AddPoint(0 / max, CreateColor(db.cpColor0[1], db.cpColor0[2], db.cpColor0[3], db.cpColor0[4]))
  curve:AddPoint(1 / max, CreateColor(db.cpColor1[1], db.cpColor1[2], db.cpColor1[3], db.cpColor1[4]))
  curve:AddPoint(4 / max, CreateColor(db.cpColor4[1], db.cpColor4[2], db.cpColor4[3], db.cpColor4[4]))
  curve:AddPoint(5 / max, CreateColor(db.cpColor5[1], db.cpColor5[2], db.cpColor5[3], db.cpColor5[4]))
  ComboPointColorCurve = curve
end

-- Updates the combo point display (value + color).
--
-- Forever: UnitPower("player", 4) does not reset on PLAYER_TARGET_CHANGED -
-- confirmed live via a (since removed) debug probe (a FontString fed
-- directly from UnitPower, bypassing RefreshComboPoints entirely) staying stuck across
-- real target switches in combat. GetComboPoints("player", "target") reads
-- the new target's count correctly, so Forever reads combo points from it;
-- Retail keeps UnitPower (shared across targets by design since patch
-- 6.0.2, see ThreatPlates' ComboPointsWidget.lua).
local function RefreshComboPoints()
  if not Bar or not Bar:IsShown() then return end
  if not Bar.cpText then return end

  -- Only the retrieval differs per client - both values are just as secret
  -- in combat when read from this addon's own tainted execution (see
  -- BuildComboPointColorCurve), so the handling below stays identical
  -- either way: no Lua comparison on cp, only secret-safe C-side sinks
  -- (SetText, and the UnitPowerPercent/ComboPointColorCurve color
  -- evaluation, which reads UnitPower internally regardless of which value
  -- cp holds - OnTargetChanged covers the one moment the two diverge on
  -- Forever).
  local cp
  if Addon.IS_FOREVER then
    cp = (GetComboPoints and GetComboPoints("player", "target")) or 0
  else
    cp = UnitPower("player", 4)
  end

  if not ComboPointColorCurve then BuildComboPointColorCurve() end
  Bar.cpText:SetTextColor(UnitPowerPercent("player", 4, false, ComboPointColorCurve):GetRGBA())
  Bar.cpText:SetText(cp) -- SetText is a C-side sink, accepts a secret or plain value directly
end

-- Thin method wrapper so Options.lua (a separate file/chunk, no access to
-- this file's locals) can trigger a combo-point color refresh after the
-- user changes a cpColorN setting. Rebuilds the color curve first so the
-- new colors take effect immediately - used on both clients, see
-- RefreshComboPoints.
function Addon:RefreshComboPoints()
  BuildComboPointColorCurve()
  RefreshComboPoints()
end

-- Updates the combo-point overflow buffer indicator (Überquellende Macht —
-- CP_BUFFER_SPELL_ID, hardcoded, banks combo points above the 5-point cap
-- into a stacking buff).
local function RefreshComboPointBuffer()
  if not Bar or not Bar:IsShown() then return end
  if not Bar.cpBufferText then return end

  -- No overflow buffer on this client (Forever).
  if not CP_BUFFER_SPELL_ID then
    Bar.cpBufferText:Hide()
    return
  end

  -- Config Mode: force-show a dummy value so the text can be positioned/
  -- sized without needing a live Overflow Buffer stack (mirrors the dummy
  -- icons UpdatePreviewFrames feeds the debuff/buff rows).
  if Addon.previewModeActive then
    Bar.cpBufferText:SetText("+3")
    Bar.cpBufferText:Show()
    return
  end

  local aura = C_UnitAuras.GetPlayerAuraBySpellID(CP_BUFFER_SPELL_ID)
  local applications = aura and aura.applications
  -- Some auras mark applications/duration/expirationTime as "secret" values
  -- (anti-cheat protection); comparing/using them outside Blizzard's own
  -- code throws. Bail out rather than risk it.
  if applications and issecretvalue and issecretvalue(applications) then
    Bar.cpBufferText:Hide()
    return
  end
  if applications and applications > 0 then
    Bar.cpBufferText:SetText("+" .. applications)
    Bar.cpBufferText:Show()
  else
    Bar.cpBufferText:Hide()
  end
end

-- Updates only the displayed energy value (no layout rebuild).
local function RefreshValue()
  if not Bar or not Bar:IsShown() then
    return
  end

  local current = UnitPower("player", 3)
  local max = math.max(1, UnitPowerMax("player", 3))
  Bar:SetMinMaxValues(0, max)
  Bar:SetValue(current)
  if Bar.text then
    Bar.text:SetText(current)
  end
end

-------------------------------------------------------------------------------
-- Event handlers
-------------------------------------------------------------------------------

-- Retries AuraContainer creation (blocked mid-combat) and reconciles both
-- containers' filters/unit/enabled state. Called once from OnEnable and
-- again on PLAYER_REGEN_ENABLED in case OnEnable itself ran in combat.
function Addon:OnCombatEnded()
  self.inCombat = false
  if not Bar then return end

  if not Bar.debuffContainers or #Bar.debuffContainers == 0 then
    self:CreateDebuffAuraContainers()
    self:RepositionDebuffContainers()
  end
  if not Bar.buffContainers or #Bar.buffContainers == 0 then
    self:CreateBuffAuraContainers()
    self:RepositionBuffContainers()
  end
  if not Bar.cooldownBuffContainer then
    self:CreateCooldownBuffAuraContainer()
    self:RepositionCooldownBuffContainer()
  end

  self:UpdateDebuffContainerFilters()
  self:UpdateBuffContainerFilters()
  self:UpdateCooldownBuffContainerFilters()
  self:UpdatePreviewFrames()
  -- Catches up on any Appearance/color change made while still in combat —
  -- ReapplyLiveAuraButtonSettings no-ops on its own InCombatLockdown guard
  -- until now.
  self:ReapplyLiveAuraButtonSettings()
  -- Bar/rows are combat-gated (see OnShapeshift) — hide everything the
  -- instant combat ends.
  self:OnShapeshift()
end

-- PLAYER_REGEN_DISABLED itself is the "combat started" signal. Don't rely on
-- InCombatLockdown() alone inside this handler: with the polling ticker gone
-- nothing re-checks it later, and the Bar stayed hidden in real combat while
-- the icon rows (which don't depend on it) showed up. Remembered here and
-- cleared in OnCombatEnded; OnShapeshift still also honors
-- InCombatLockdown() for a /reload mid-combat.
function Addon:OnCombatStarted()
  self.inCombat = true
  self:OnShapeshift()
end

function Addon:OnShapeshift()
  if not Bar then
    return
  end

  -- Config Mode force-shows the Bar regardless of shapeshift form or combat
  -- state — the whole point is positioning everything without needing to
  -- actually be in Cat Form or in combat.
  if ShouldShowInCombat() or Addon.previewModeActive then
    Bar:Show()
    Bar.bg:Show()
    RefreshValue()
    RefreshComboPoints()
    RefreshComboPointBuffer()
  else
    Bar:Hide()
    Bar.bg:Hide()
    if Bar.cpBufferText then
      Bar.cpBufferText:Hide()
    end
  end

  -- All three gate themselves on Cat Form + combat (ShouldShowInCombat) and
  -- Config Mode internally.
  self:UpdateDebuffContainerFilters()
  self:UpdateBuffContainerFilters()
  self:UpdateCooldownBuffContainerFilters()
  self:UpdatePreviewFrames()
end

function Addon:OnTargetChanged()
  self:UpdateDebuffContainerFilters()
  -- No power event is guaranteed to fire on a target switch, so the combo
  -- point display has to be re-read here explicitly on every client. On
  -- Forever this re-read reads GetComboPoints("player", "target")
  -- (RefreshComboPoints), which reflects the new target immediately - no
  -- race, no delay needed (see RefreshComboPoints for why UnitPower doesn't
  -- work here). Retail combo points are shared across targets since patch
  -- 6.0.2, so nothing to reset there either; this call just keeps the
  -- display in sync in case of a missed event.
  RefreshComboPoints()

  -- RefreshComboPoints' color still comes from UnitPower's percent-of-max
  -- (the only secret-safe curve-evaluation sink available - see
  -- RefreshComboPoints/BuildComboPointColorCurve; there's no equivalent for
  -- GetComboPoints' value, and Lua can't compare/branch on a secret number
  -- to pick a color by hand). This only actually diverges from
  -- GetComboPoints right after a target switch: Vanilla rules only ever let
  -- one target hold combo points at a time, so whenever the real count is
  -- > 0, UnitPower's value (and thus its color) necessarily agrees with
  -- GetComboPoints' - there's no other target it could be counting.
  -- Immediately after switching, though, UnitPower still holds the old
  -- target's color while GetComboPoints (and the text) already reads the
  -- new target's real "0". Force the "0" color directly from the plain,
  -- addon-owned db color table - a fresh target is always at 0 by
  -- Vanilla-rules design, so this needs no secret read at all. Overwritten
  -- again, correctly, by the next real combo-point-building event.
  if Addon.IS_FOREVER and Bar and Bar.cpText then
    local c = Addon.db.profile.cpColor0
    Bar.cpText:SetTextColor(c[1], c[2], c[3], c[4])
  end
end

-- Other addons that register LibSharedMedia entries (custom statusbar/
-- border/font media, e.g. SharedMedia) do so at their own ADDON_LOADED,
-- which can run after this addon's (load order depends on .toc name/
-- dependencies) — so the very first ApplyBarAppearance/ApplyGlobalFont
-- call in CreateEnergyBar can silently fall back to the default texture/
-- font if the user's saved LSM key wasn't registered yet at that point.
-- PLAYER_ENTERING_WORLD fires once every addon has fully loaded, so
-- re-applying here picks up the real saved choice instead of the
-- fallback sticking until the user reopens Options.
function Addon:OnPlayerEnteringWorld()
  self:RefreshMedia()
end

-- Re-applies every LSM-dependent visual (bar texture/border, fonts). Also
-- driven by LibSharedMedia_Registered for media that shows up later still.
function Addon:RefreshMedia()
  self:ApplyBarAppearance()
  self:ApplyGlobalFont()
  self:ReapplyLiveAuraButtonSettings()
  self:ReapplyLiveIconFrameFonts()
end

function Addon:OnUnitAura(event, unit)
  if unit ~= "player" then return end
  RefreshComboPointBuffer()
end

function Addon:OnPowerUpdate(event, unit, powerType)
  if unit ~= "player" then return end
  if powerType == "ENERGY" then
    RefreshValue()
  elseif powerType == "COMBO_POINTS" then
    RefreshComboPoints()
  end
end

function Addon:OnMaxPower(event, unit, powerType)
  if unit ~= "player" or powerType ~= "ENERGY" then
    return
  end
  if not Bar then
    return
  end

  local max = math.max(1, UnitPowerMax("player", 3))
  Bar:SetMinMaxValues(0, max)
  RefreshValue()
end


-- Addon Compartment icon click handler (see .toc's AddonCompartmentFunc).
-- Must be a plain global, not a method — Blizzard calls it directly by
-- name, not through the addon object. Opening the config dialog pops open
-- Blizzard's Settings frame, which is blocked in combat (protected/tainted
-- like most frame-showing UI actions); guard here instead of letting it
-- error, same as every other config-affecting action in this addon already
-- being combat-gated.
function BloodInTheWater_OnAddonCompartmentClick(addonName, buttonName)
  if InCombatLockdown() then
    print("|cff00ff00[BiTW]|r Can't open options while in combat.")
    return
  end
  Addon:OpenConfig()
end

-- Shared helpers for the debug commands below (/bitwdebug, /bitwauras).
-- Everything here is diagnostics for the WoW Forever port (see CLAUDE.md,
-- "Debugging") and can be trimmed once Forever support is confirmed.
local function DbgStr(v)
  if IsSecret(v) then return "<secret>" end
  return tostring(v)
end

local function DbgLine(status, label, detail)
  local tag = status == "ok" and "|cff00ff00OK|r"
    or status == "fail" and "|cffff4040FAIL|r"
    or "|cffffff00INFO|r"
  print(string.format("|cff00ff00[BiTW]|r %s %s%s", tag, label, detail ~= nil and (" - " .. DbgStr(detail)) or ""))
end

local function DbgCheck(label, ok, detail) DbgLine(ok and "ok" or "fail", label, detail) end
local function DbgInfo(label, detail) DbgLine("info", label, detail) end
local function DbgHeader(title)
  print("|cff00ff00[BiTW]|r |cffffff00== " .. title .. " ==|r")
end

-- Cat Form is spell 768 on Forever. Lists every stance-bar form with its
-- spell ID, confirming GetShapeshiftFormID() == CAT_FORM_ID (the addon's
-- actual, sole detection method - see "Combat gating" in CLAUDE.md) sees it.
--
-- Used to cross-check against C_UnitAuras.GetPlayerAuraBySpellID(768) (the
-- Cat Form buff aura) too, but that method isn't used anywhere in the
-- addon's real logic and turned out unreliable in combat (returned nil live
-- while genuinely in Cat Form, confirmed OK out of combat and via a full
-- C_UnitAuras.GetAuraDataByIndex scan even in combat - /bitwauras) - dropped
-- as pure noise, not a real signal.
local function ReportForms()
  local formID = GetShapeshiftFormID()
  local activeIndex = GetShapeshiftForm()
  DbgInfo("GetShapeshiftFormID()", tostring(formID) .. " (CAT_FORM_ID=" .. CAT_FORM_ID .. "), GetShapeshiftForm()=" .. tostring(activeIndex))

  local catIndex
  for i = 1, GetNumShapeshiftForms() do
    local _, isActive, _, spellID = GetShapeshiftFormInfo(i)
    if spellID == 768 then catIndex = i end
    DbgInfo("  form " .. i, "spellID=" .. tostring(spellID) .. " active=" .. tostring(isActive))
  end
  DbgCheck("Cat Form (768) on the stance bar", catIndex ~= nil, catIndex and ("index " .. catIndex))
end

-- Aura ID watcher (slash command /bitwauras, toggles on/off). Prints the
-- spell ID + name of every aura on the player (HELPFUL) and the target
-- (HARMFUL, own only) the first time it shows up — meant for finding the
-- per-rank aura IDs of Rake/Rip/Tiger's Fury/Berserk on WoW Forever, where
-- each rank has its own spell ID. Auras whose name matches one of the base
-- spells below get a "<-- tracked" tag. Every aura *instance* prints once, so
-- refreshing/re-applying a lower rank prints again. spellId/name can be
-- secret values in combat — printed as <secret> instead of being touched.
local WATCH_BASE_SPELL_IDS = {1822, 1079, 5217, 417141} -- Rake, Rip, Tiger's Fury, Berserk
local WATCH_UNITS = {
  player = "HELPFUL",
  target = "HARMFUL|PLAYER",
}
local auraWatchFrame
local auraWatchSeen = { player = {}, target = {} }
local auraWatchNames

local function WatchPrint(msg)
  print("|cff00ff00[BiTW]|r " .. msg)
end

local function ScanWatchedAuras(unit)
  local seen = auraWatchSeen[unit]
  local filter = WATCH_UNITS[unit]
  for i = 1, 255 do
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
    if not ok then
      WatchPrint(string.format("%s %s: aura data inaccessible (secret + tainted) at index %d, stopping scan.", unit, filter, i))
      break
    end
    if not aura then break end

    local instanceID = aura.auraInstanceID
    if instanceID ~= nil and not IsSecret(instanceID) and not seen[instanceID] then
      seen[instanceID] = true
      local spellId, name = aura.spellId, aura.name
      local idText = IsSecret(spellId) and "<secret>" or tostring(spellId)
      local nameText = IsSecret(name) and "<secret>" or tostring(name)
      local tag = (not IsSecret(name) and auraWatchNames[name]) and "  <-- tracked" or ""
      WatchPrint(string.format("%s %s: id=%s name=%s%s", unit, filter, idText, nameText, tag))
    end
  end
end

local function OnAuraWatchEvent(_, event, unit)
  if event == "PLAYER_TARGET_CHANGED" then
    wipe(auraWatchSeen.target)
    if UnitExists("target") then ScanWatchedAuras("target") end
  elseif WATCH_UNITS[unit] then
    ScanWatchedAuras(unit)
  end
end

function Addon:ToggleAuraWatch()
  if not auraWatchFrame then
    auraWatchFrame = CreateFrame("Frame")
    auraWatchFrame:SetScript("OnEvent", OnAuraWatchEvent)
  end

  if auraWatchFrame:IsEventRegistered("UNIT_AURA") then
    auraWatchFrame:UnregisterAllEvents()
    WatchPrint("Aura watch OFF.")
    return
  end

  auraWatchNames = {}
  for _, spellID in ipairs(WATCH_BASE_SPELL_IDS) do
    local name = C_Spell.GetSpellName(spellID)
    if name then auraWatchNames[name] = true end
  end
  wipe(auraWatchSeen.player)
  wipe(auraWatchSeen.target)

  auraWatchFrame:RegisterUnitEvent("UNIT_AURA", "player", "target")
  auraWatchFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

  WatchPrint(string.format("Aura watch ON. project=%s expansionLevel=%s build=%s formID=%s",
    tostring(WOW_PROJECT_ID),
    tostring(GetClassicExpansionLevel and GetClassicExpansionLevel()),
    tostring(select(4, GetBuildInfo())),
    tostring(GetShapeshiftFormID())))
  ReportForms()

  ScanWatchedAuras("player")
  if UnitExists("target") then ScanWatchedAuras("target") end
end

-- Debug dump for the target-debuff AuraContainer pipeline (slash command
-- /bitwdebug). Prints exactly the state UpdateDebuffContainerFilters
-- branches on, so a "no icon" report can be diagnosed without guessing:
-- unused slot (empty spell ID list), not in Cat Form, no target selected, or the
-- container/AddAuraGroup itself never having been created — plus the combat/
-- Config Mode gate and whether each slot's container is enabled. Deliberately
-- no per-aura "is it on the target" lookup: GetUnitAuraBySpellID returned nil
-- for auras that were visibly shown in combat (tested in-game), so it can't
-- be trusted there.
function Addon:DebugDumpDebuffs()
  local prefix = "|cff00ff00[BiTW]|r "
  print(prefix .. "HasAuraContainers=" .. tostring(HasAuraContainers))
  print(prefix .. "InCat=" .. tostring(GetShapeshiftFormID() == CAT_FORM_ID)
    .. " UnitExists(target)=" .. tostring(UnitExists("target"))
    .. " InCombatLockdown=" .. tostring(InCombatLockdown())
    .. " inCombat(flag)=" .. tostring(self.inCombat)
    .. " ShouldShowInCombat=" .. tostring(ShouldShowInCombat())
    .. " ConfigMode=" .. tostring(self.previewModeActive))
  if not Bar then
    print(prefix .. "Bar not created yet.")
    return
  end
  if not Bar.debuffContainers then
    print(prefix .. "Bar.debuffContainers not created yet (out-of-combat creation may not have run).")
    return
  end

  for i = 1, NUM_DEBUFF_SLOTS do
    local container = Bar.debuffContainers[i]
    local spellID = SpellIdsText(DEBUFF_SPELL_IDS[i])
    local frameCount = container and container.GetAuraGroupFrameCount and container:GetAuraGroupFrameCount("main")
    local enabled = container and container.IsEnabled and tostring(container:IsEnabled()) or "n/a"
    print(string.format(
      "%sSlot %d: spellIDs=%s container=%s enabled=%s poolFrameCount=%s",
      prefix, i, tostring(spellID), tostring(container ~= nil), enabled, tostring(frameCount)
    ))
  end
end

-------------------------------------------------------------------------------
-- /bitwdebug: WoW Forever compatibility check
-------------------------------------------------------------------------------

-- Static section 1: which client is this (the raw signals ThreatPlates' own
-- IS_FOREVER detection is built from).
local function ReportClient()
  DbgHeader("Client")
  local version, build, _, interface = GetBuildInfo()
  local expansionLevel = GetClassicExpansionLevel and GetClassicExpansionLevel()
  DbgInfo("WOW_PROJECT_ID", tostring(WOW_PROJECT_ID) .. " (MAINLINE=" .. tostring(WOW_PROJECT_MAINLINE) .. ", CLASSIC=" .. tostring(WOW_PROJECT_CLASSIC) .. ")")
  DbgInfo("GetClassicExpansionLevel()", expansionLevel)
  DbgInfo("GetBuildInfo()", string.format("version=%s build=%s interface=%s", tostring(version), tostring(build), tostring(interface)))
  DbgInfo("Addon.IS_FOREVER (ThreatPlates formula) - spell set in use", tostring(Addon.IS_FOREVER) .. " - " .. (Addon.IS_FOREVER and "FOREVER" or "RETAIL"))
  DbgInfo("Class / combat lockdown", tostring(select(2, UnitClass("player"))) .. " / " .. tostring(InCombatLockdown()))
end

-- Static section 2: every API/global the addon relies on.
local function ReportApis()
  DbgHeader("API availability")
  local checks = {
    {"HasAuraContainers (CustomAuraContainerTemplate)", HasAuraContainers},
    {"AuraContainerSortMethod / SortDirection", AuraContainerSortMethod ~= nil and AuraContainerSortDirection ~= nil},
    {"AnchorUtil.FlowDirection", AnchorUtil ~= nil and AnchorUtil.FlowDirection ~= nil},
    {"PixelUtil.SetSize", PixelUtil ~= nil and PixelUtil.SetSize ~= nil},
    {"issecretvalue", issecretvalue ~= nil},
    {"C_CurveUtil.CreateColorCurve / Enum.LuaCurveType", C_CurveUtil ~= nil and C_CurveUtil.CreateColorCurve ~= nil and Enum.LuaCurveType ~= nil},
    {"C_UnitAuras.GetAuraDataByIndex", C_UnitAuras ~= nil and C_UnitAuras.GetAuraDataByIndex ~= nil},
    {"C_UnitAuras.GetPlayerAuraBySpellID", C_UnitAuras ~= nil and C_UnitAuras.GetPlayerAuraBySpellID ~= nil},
    {"C_Spell.GetSpellName / GetSpellTexture", C_Spell ~= nil and C_Spell.GetSpellName ~= nil and C_Spell.GetSpellTexture ~= nil},
    {"C_Spell.DoesSpellExist", C_Spell ~= nil and C_Spell.DoesSpellExist ~= nil},
    {"C_Timer.After", C_Timer ~= nil and C_Timer.After ~= nil},
    {"C_Texture.GetAtlasInfo", C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil},
    {"BackdropTemplate mixin (SetBackdrop)", BackdropTemplateMixin ~= nil},
    {"LibSharedMedia-3.0", LSM ~= nil},
    {"AceConfigDialog-3.0", LibStub("AceConfigDialog-3.0", true) ~= nil},
  }
  for _, c in ipairs(checks) do
    DbgCheck(c[1], c[2] and true or false)
  end
  DbgInfo("GetComboPoints (legacy per-target API)", GetComboPoints ~= nil)
end

-- Static section 3: cat form detection, see ReportForms above.
local function ReportCatForm()
  DbgHeader("Cat Form")
  ReportForms()
end

-- Static section 4: energy + combo points. RefreshComboPoints reads the
-- count from UnitPower("player", 4) on Retail and from
-- GetComboPoints("player", "target") on Forever (see CLAUDE.md, WoW Forever
-- "Implemented") - both are printed below. Values that are secret here
-- show as <secret>.
local function ReportResources()
  DbgHeader("Energy / combo points")
  local powerType, token = UnitPowerType("player")
  DbgInfo("UnitPowerType(player)", tostring(powerType) .. " / " .. tostring(token) .. " (energy expected in Cat Form: 3 / ENERGY)")
  DbgInfo("Enum.PowerType.Energy / ComboPoints",
    tostring(Enum and Enum.PowerType and Enum.PowerType.Energy) .. " / " .. tostring(Enum and Enum.PowerType and Enum.PowerType.ComboPoints))
  DbgInfo("UnitPower / Max (energy, type 3)", DbgStr(UnitPower("player", 3)) .. " / " .. DbgStr(UnitPowerMax("player", 3)))
  DbgInfo("UnitPower / Max (combo points, type 4)", DbgStr(UnitPower("player", 4)) .. " / " .. DbgStr(UnitPowerMax("player", 4)))
  if GetComboPoints then
    if UnitExists("target") then
      DbgInfo("GetComboPoints(player, target)", GetComboPoints("player", "target"))
    else
      DbgInfo("GetComboPoints(player, target)", "no target")
    end
  end
end

-- Static section 5: can every event the addon uses be registered at all?
-- (Says nothing about whether it actually fires - see "/bitwdebug live".)
local DEBUG_EVENTS = {
  "UPDATE_SHAPESHIFT_FORM", "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
  "UNIT_COMBO_POINTS", "UNIT_AURA", "PLAYER_TARGET_CHANGED",
  "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD",
}
local function ReportEventRegistration()
  DbgHeader("Event registration")
  local frame = CreateFrame("Frame")
  for _, event in ipairs(DEBUG_EVENTS) do
    local ok, err = pcall(frame.RegisterEvent, frame, event)
    DbgCheck(event, ok, not ok and err or nil)
  end
  frame:UnregisterAllEvents()
end

-- Static section 6: which spell IDs exist on this client. Retail IDs are
-- expected to be partly missing on Forever, that's what proves the per-client
-- spell tables are needed. Aura IDs of the individual ranks: /bitwauras.
local DEBUG_SPELL_GROUPS = {
  { "Retail IDs (currently hardcoded)", {
    {"Rake debuff", 155722}, {"Rip", 1079}, {"Moonfire", 8921}, {"Clearcasting", 135700},
    {"Predatory Swiftness", 69369}, {"Tiger's Fury", 5217}, {"Berserk", 106951},
    {"Incarnation", 102543}, {"Overflow buffer", 405189},
  }},
  { "Forever IDs (checked against Wowhead Forever - 'known' shows which ranks this character has)", {
    {"Cat Form", 768}, {"Berserk", 417141}, {"Clearcasting", 16870},
    {"Rake rank 1", 1822}, {"Rake rank 2", 1823}, {"Rake rank 3", 1824}, {"Rake rank 4", 9904},
    {"Rip rank 1", 1079}, {"Rip rank 2", 9492}, {"Rip rank 3", 9493},
    {"Rip rank 4", 9752}, {"Rip rank 5", 9894}, {"Rip rank 6", 9896},
    {"Tiger's Fury (no ranks)", 5217},
  }},
}
local function ReportSpells()
  for _, group in ipairs(DEBUG_SPELL_GROUPS) do
    DbgHeader("Spells: " .. group[1])
    for _, entry in ipairs(group[2]) do
      local label, spellID = entry[1], entry[2]
      local name = C_Spell.GetSpellName(spellID)
      local exists = C_Spell.DoesSpellExist and C_Spell.DoesSpellExist(spellID)
      if exists == nil then exists = name ~= nil end
      local known = IsPlayerSpell and IsPlayerSpell(spellID)
      DbgLine(exists and "ok" or "fail", string.format("%s (%d)", label, spellID),
        exists and string.format("name=%s texture=%s known=%s", tostring(name),
          tostring(C_Spell.GetSpellTexture(spellID) ~= nil), tostring(known)) or "spell does not exist")
    end
  end
end

-- Static section 7: bundled/optional visual assets that might not exist on Forever.
local function ReportAssets()
  DbgHeader("Assets")
  local atlasOk = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("rotationhelper_ants_flipbook") ~= nil
  DbgCheck("Atlas rotationhelper_ants_flipbook (Pandemic 'WoW Border' style)", atlasOk)
  if LSM then
    DbgCheck("LSM font 'Cabin'", LSM:Fetch("font", "Cabin", true) ~= nil)
    DbgCheck("LSM statusbar 'Smooth'", LSM:Fetch("statusbar", "Smooth", true) ~= nil)
    DbgCheck("LSM border 'Blizzard Tooltip'", LSM:Fetch("border", "Blizzard Tooltip", true) ~= nil)
  end
end

-- Static section 8: AuraContainer state per row. The frame pool stays empty
-- until an aura actually matches, so "frames=0" is normal without the
-- debuff/buff up. Pandemic can only be judged visually on Forever (a
-- Vanilla ruleset may not flag pandemic windows at all).
local function ReportContainer(label, container)
  if not container then
    DbgCheck(label, false, "container not created (combat? HasAuraContainers false?)")
    return
  end
  local count = container.GetAuraGroupFrameCount and container:GetAuraGroupFrameCount("main")
  DbgInfo(label, string.format("frames=%s enabled=%s", tostring(count), tostring(container.IsEnabled and container:IsEnabled())))
  local button = count and count > 0 and container:GetAuraGroupFrame("main", 1)
  if button then
    DbgCheck("  AuraButton:AddPandemicRegion", type(button.AddPandemicRegion) == "function")
    DbgInfo("  Pandemic glow style / created", tostring(button.PandemicGlowStyle) .. " / " .. tostring(button.PandemicGlow ~= nil))
  end
end

local function ReportContainers()
  DbgHeader("AuraContainers")
  if not Bar then
    DbgCheck("Bar", false, "not created")
    return
  end
  for i = 1, NUM_DEBUFF_SLOTS do
    ReportContainer("Debuff slot " .. i .. " (ids " .. SpellIdsText(DEBUFF_SPELL_IDS[i]) .. ")", Bar.debuffContainers and Bar.debuffContainers[i])
  end
  for i = 1, NUM_PLAYER_BUFF_SLOTS do
    ReportContainer("Buff slot " .. i .. " (ids " .. SpellIdsText(PLAYER_BUFF_SPELL_IDS[i]) .. ")", Bar.buffContainers and Bar.buffContainers[i])
  end
  ReportContainer("Cooldown-buff column", Bar.cooldownBuffContainer)
  DbgInfo("Target / combat", "UnitExists(target)=" .. tostring(UnitExists("target")) .. " InCombatLockdown=" .. tostring(InCombatLockdown()))
  DbgInfo("Hint", "Pandemic glow: check visually on a Rake/Rip in its last ~30% - Vanilla rules may not have a pandemic window")
end

-- Live section: counts which events really fire (and with which power type)
-- during a time window, so the power/combo-point/shapeshift event wiring can
-- be verified. Do the things to test while it runs: gain/spend energy, build
-- combo points, shift forms, change target, enter/leave combat.
local DEBUG_LIVE_EVENTS = {
  UPDATE_SHAPESHIFT_FORM = false,
  UNIT_POWER_FREQUENT = {"player"},
  UNIT_POWER_UPDATE = {"player"},
  UNIT_MAXPOWER = {"player"},
  UNIT_COMBO_POINTS = {"player"},
  UNIT_AURA = {"player", "target"},
  PLAYER_TARGET_CHANGED = false,
  PLAYER_REGEN_DISABLED = false,
  PLAYER_REGEN_ENABLED = false,
}
local debugLiveFrame

local function StartLiveEventCheck(seconds)
  if debugLiveFrame and debugLiveFrame.running then
    DbgInfo("Live event check", "already running")
    return
  end
  debugLiveFrame = debugLiveFrame or CreateFrame("Frame")
  local counts = {}
  debugLiveFrame:SetScript("OnEvent", function(_, event, unit, powerType)
    local key = event
    if type(unit) == "string" and not IsSecret(unit) then key = key .. "(" .. unit .. ")" end
    if type(powerType) == "string" and not IsSecret(powerType) then key = key .. ":" .. powerType end
    counts[key] = (counts[key] or 0) + 1
  end)

  DbgHeader("Live event check")
  for event, units in pairs(DEBUG_LIVE_EVENTS) do
    local ok, err
    if units then
      ok, err = pcall(debugLiveFrame.RegisterUnitEvent, debugLiveFrame, event, unpack(units))
    else
      ok, err = pcall(debugLiveFrame.RegisterEvent, debugLiveFrame, event)
    end
    if not ok then DbgCheck("register " .. event, false, err) end
  end
  debugLiveFrame.running = true
  DbgInfo("Listening for " .. seconds .. "s", "gain/spend energy, build combo points, shift forms, change target, enter/leave combat")

  C_Timer.After(seconds, function()
    debugLiveFrame:UnregisterAllEvents()
    debugLiveFrame.running = false
    DbgHeader("Live event check: result")
    local keys = {}
    for key in pairs(counts) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do DbgInfo(key, counts[key] .. "x") end
    if #keys == 0 then DbgInfo("No events fired", "nothing happened in the window, or no event fires at all") end
    for event in pairs(DEBUG_LIVE_EVENTS) do
      local seen = false
      for _, key in ipairs(keys) do
        if key == event or key:find("^" .. event .. "[%(:]") then seen = true break end
      end
      if not seen then DbgInfo(event, "0x - did not fire in this window") end
    end
  end)
end

-- Entry point: /bitwdebug            full static report
--              /bitwdebug live [s]   event counter for s seconds (default 20)
function Addon:DebugCheck(input)
  local arg1, arg2 = (input or ""):match("^%s*(%S*)%s*(%S*)")
  if arg1 == "live" then
    StartLiveEventCheck(tonumber(arg2) or 20)
    return
  end

  ReportClient()
  ReportApis()
  ReportCatForm()
  ReportResources()
  ReportEventRegistration()
  ReportSpells()
  ReportAssets()
  ReportContainers()
  DbgHeader("Debuff container dump")
  self:DebugDumpDebuffs()
  DbgInfo("Next steps", "/bitwdebug live 20 (event wiring), /bitwauras (aura IDs per rank)")
end
