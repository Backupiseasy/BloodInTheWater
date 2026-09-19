-------------------------------------------------------------------------------
-- Blood in the Water — Options (AceConfig + AceConfigDialog)
-------------------------------------------------------------------------------
-- Split out of BloodInTheWater.lua for size/maintainability once the options
-- table alone passed ~1000 lines. This file is its own chunk (separate Lua
-- locals from BloodInTheWater.lua), so it re-fetches the addon object via
-- AceAddon-3.0's registry instead of sharing a local, and re-declares LSM —
-- both cheap, idempotent LibStub lookups. previewModeActive lives on Addon
-- itself (not a file-local) for the same cross-file-visibility reason; see
-- BloodInTheWater.lua's own comment on that field. Loaded after
-- BloodInTheWater.lua (see .toc) so LibStub("AceAddon-3.0"):GetAddon(...)
-- below finds it already registered.

local Addon = LibStub("AceAddon-3.0"):GetAddon("BloodInTheWater")
local LSM = LibStub("LibSharedMedia-3.0", true)

-- Invisible row-end spacer: placed as the last arg in a row to soak up
-- whatever width is left, guaranteeing the next arg wraps to a fresh line
-- instead of relying on the preceding widths summing to exactly "full".
local function GetSpacerEntry(pos)
  return {
    name = "",
    order = pos,
    type = "description",
    width = "full",
  }
end

function Addon:SetupOptions()
  -- Local reference to self for closures
  local self = self

  local options = {
    name = "Blood in the Water",
    handler = Addon,
    type = "group",
    childGroups = "tab",
    args = {

      previewMode = {
        name = function()
          return Addon.previewModeActive and "Disable Config Mode" or "Enable Config Mode"
        end,
        desc = "Shows every icon row (debuffs, player buffs, cooldown buffs, own cooldowns) at its real screen position with real spell art and a dummy countdown (random 1-15s for auras, fixed 60s for own cooldowns), regardless of combat/target/buff state — and force-shows the Bar outside Cat Form too. Real AuraContainers are suppressed while this is on to avoid double icons. Click again to turn it back off when done positioning things. Not saved — always off again after a UI reload/relog.",
        type = "execute",
        order = 0,
        width = "full",
        func = function()
          Addon.previewModeActive = not Addon.previewModeActive
          self:OnShapeshift()
        end
      },

      -- ── Appearance tab (shared font/icon-size for every text/icon in the addon) ──
      appearanceTab = {
        name = "Icons",
        type = "group",
        order = 3,
        args = {
          iconGroup = {
            name = "Appearance",
            desc = "Shared by every icon-based row: Debuffs, Proccs, Cooldowns.",
            type = "group",
            inline = true,
            order = 1,
            args = {
              appearanceIconSize = {
                name = "Size",
                desc = "Icon width/height, shared everywhere (pixels). Applies live to already-shown icons while out of combat; in combat it applies as soon as combat ends.",
                type = "range",
                min = 12,
                max = 64,
                step = 1,
                order = 1,
                width = "full",
                get = function()
                  return self.db.profile.appearanceIconSize
                end,
                set = function(_, val)
                  self.db.profile.appearanceIconSize = val
                  self:UpdateBar()
                end
              },
              appearanceFont = {
                name = "Typeface",
                desc = "One shared typeface for every text string in the addon (energy value, combo points, and every icon's countdown number). Individual per-row fonts are not configurable — this is the only Font setting. Requires LibSharedMedia. Applies live to already-shown icons while out of combat; in combat it applies as soon as combat ends.",
                type = "select",
                order = 2,
                width = 1.5,
                values = function()
                  local t = {}
                  if LSM then
                    for _, name in ipairs(LSM:List("font")) do
                      t[name] = name
                    end
                  end
                  return t
                end,
                get = function()
                  return self.db.profile.appearanceFont
                end,
                set = function(_, val)
                  self.db.profile.appearanceFont = val
                  self:UpdateBar()
                end
              },
              appearanceFontScale = {
                name = "Font Size",
                desc = "Countdown-number font size as a percentage of the Icon Size above, instead of its own absolute point size — e.g. 50% on a 32px icon gives a 16pt countdown number. Applies live to already-shown icons while out of combat; in combat it applies as soon as combat ends.",
                type = "range",
                min = 0.1,
                max = 1.0,
                step = 0.05,
                isPercent = true,
                order = 3,
                width = 1.5,
                get = function()
                  return self.db.profile.appearanceFontScale
                end,
                set = function(_, val)
                  self.db.profile.appearanceFontScale = val
                  self:UpdateBar()
                end
              },
              iconRowSpacer = GetSpacerEntry(4)
            }
          }
        }
      },

      -- ── Energy tab ──────────────────────────────────────────────────────
      energyTab = {
        name = "Energy Bar",
        type = "group",
        order = 1,
        args = {
          layoutGroup = {
            name = "Layout",
            type = "group",
            inline = true,
            order = 2,
            args = {
              sizeGroup = {
                name = "",
                type = "group",
                inline = true,
                order = 1,
                args = {
                  width = {
                    name = "Width",
                    desc = "Width of the energy bar (pixels)",
                    type = "range",
                    min = 50,
                    max = 800,
                    step = 1,
                    order = 1,
                    width = 1.5,
                    get = function()
                      return self.db.profile.width
                    end,
                    set = function(_, val)
                      self.db.profile.width = val
                      self:UpdateBar()
                    end
                  },
                  height = {
                    name = "Height",
                    desc = "Height of the energy bar (pixels)",
                    type = "range",
                    min = 10,
                    max = 100,
                    step = 1,
                    order = 2,
                    width = 1.5,
                    get = function()
                      return self.db.profile.height
                    end,
                    set = function(_, val)
                      self.db.profile.height = val
                      self:UpdateBar()
                    end
                  }
                }
              },
              posGroup = {
                name = "",
                type = "group",
                inline = true,
                order = 2,
                args = {
                  posX = {
                    name = "X Offset",
                    desc = "Horizontal offset from the center of the screen (pixels)",
                    type = "range",
                    min = -500,
                    max = 500,
                    step = 1,
                    order = 1,
                    width = 1.5,
                    get = function()
                      return self.db.profile.posX
                    end,
                    set = function(_, val)
                      self.db.profile.posX = val
                      self:UpdateBar()
                    end
                  },
                  posY = {
                    name = "Y Offset",
                    desc = "Vertical offset from the center of the screen (pixels)",
                    type = "range",
                    min = -400,
                    max = 400,
                    step = 1,
                    order = 2,
                    width = 1.5,
                    get = function()
                      return self.db.profile.posY
                    end,
                    set = function(_, val)
                      self.db.profile.posY = val
                      self:UpdateBar()
                    end
                  }
                }
              }
            }
          },
          appearanceGroup = {
            name = "Appearance",
            type = "group",
            inline = true,
            order = 1,
            args = {
              barTexture = {
                name = "Bar Texture",
                desc = "Fill texture of the energy bar (LibSharedMedia)",
                type = "select",
                order = 1,
                width = 1,
                values = function()
                  local t = {}
                  if LSM then
                    for _, name in ipairs(LSM:List("statusbar")) do
                      t[name] = name
                    end
                  end
                  return t
                end,
                get = function()
                  return self.db.profile.barTexture
                end,
                set = function(_, val)
                  self.db.profile.barTexture = val
                  self:UpdateBar()
                end
              },
              barColor = {
                name = "Bar Color",
                desc = "Fill color and opacity of the energy bar",
                type = "color",
                hasAlpha = true,
                order = 2,
                width = 1,
                get = function()
                  local c = self.db.profile.barColor
                  return c[1], c[2], c[3], c[4] or 1
                end,
                set = function(_, r, g, b, a)
                  local c = self.db.profile.barColor
                  c[1], c[2], c[3], c[4] = r, g, b, a
                  self:UpdateBar()
                end
              },
              barColorFiller = GetSpacerEntry(3),
              barBorderTexture = {
                name = "Border Texture",
                desc = "Border texture drawn around the energy bar (LibSharedMedia)",
                type = "select",
                order = 4,
                width = 1,
                values = function()
                  local t = {}
                  if LSM then
                    for _, name in ipairs(LSM:List("border")) do
                      t[name] = name
                    end
                  end
                  return t
                end,
                get = function()
                  return self.db.profile.barBorderTexture
                end,
                set = function(_, val)
                  self.db.profile.barBorderTexture = val
                  self:UpdateBar()
                end
              },
              barBorderColor = {
                name = "Border Color",
                desc = "Color and opacity of the border",
                type = "color",
                hasAlpha = true,
                order = 5,
                width = 1,
                get = function()
                  local c = self.db.profile.barBorderColor
                  return c[1], c[2], c[3], c[4] or 1
                end,
                set = function(_, r, g, b, a)
                  local c = self.db.profile.barBorderColor
                  c[1], c[2], c[3], c[4] = r, g, b, a
                  self:UpdateBar()
                end
              },
              barBorderSize = {
                name = "Border Thickness",
                desc = "Edge thickness of the border texture (pixels)",
                type = "range",
                min = 1,
                max = 32,
                step = 1,
                order = 6,
                width = 1,
                get = function()
                  return self.db.profile.barBorderSize
                end,
                set = function(_, val)
                  self.db.profile.barBorderSize = val
                  self:UpdateBar()
                end
              },
              barBorderInset = {
                name = "Border Position (Inset)",
                desc = "Offset of the border from the bar's own outer edge (pixels) — negative expands the border outward, positive pulls it inward",
                type = "range",
                min = -20,
                max = 20,
                step = 1,
                order = 7,
                width = 1,
                get = function()
                  return self.db.profile.barBorderInset
                end,
                set = function(_, val)
                  self.db.profile.barBorderInset = val
                  self:UpdateBar()
                end
              },
              borderRowSpacer = GetSpacerEntry(8),
              barFontSize = {
                name = "Font Size",
                desc = "Font size of the energy value number (points)",
                type = "range",
                min = 8,
                max = 72,
                step = 1,
                order = 9,
                width = "full",
                get = function()
                  return self.db.profile.barFontSize
                end,
                set = function(_, val)
                  self.db.profile.barFontSize = val
                  self:UpdateBar()
                end
              }
            }
          }
        }
      },

      -- ── Combo Points tab ──────────────────────────────────────────────
      cpTab = {
        name = "Combo Points",
        type = "group",
        order = 2,
        args = {
          appearanceGroup = {
            name = "Appearance",
            type = "group",
            inline = true,
            order = 1,
            args = {
              colorGroup = {
                name = "Color",
                type = "group",
                inline = true,
                order = 1,
                args = {
                  cpColor0 = {
                    name = "0 Points",
                    desc = "Color when no combo points are active",
                    type = "color",
                    hasAlpha = false,
                    order = 1,
                    get = function()
                      local c = self.db.profile.cpColor0
                      return c[1], c[2], c[3]
                    end,
                    set = function(_, r, g, b)
                      local c = self.db.profile.cpColor0
                      c[1], c[2], c[3] = r, g, b
                      self:RefreshComboPoints()
                    end
                  },
                  cpColor1 = {
                    name = "1-3 Points",
                    desc = "Color for 1 to 3 combo points",
                    type = "color",
                    hasAlpha = false,
                    order = 2,
                    get = function()
                      local c = self.db.profile.cpColor1
                      return c[1], c[2], c[3]
                    end,
                    set = function(_, r, g, b)
                      local c = self.db.profile.cpColor1
                      c[1], c[2], c[3] = r, g, b
                      self:RefreshComboPoints()
                    end
                  },
                  cpColor4 = {
                    name = "4 Points",
                    desc = "Color for 4 combo points",
                    type = "color",
                    hasAlpha = false,
                    order = 3,
                    get = function()
                      local c = self.db.profile.cpColor4
                      return c[1], c[2], c[3]
                    end,
                    set = function(_, r, g, b)
                      local c = self.db.profile.cpColor4
                      c[1], c[2], c[3] = r, g, b
                      self:RefreshComboPoints()
                    end
                  },
                  cpColor5 = {
                    name = "5 Points",
                    desc = "Color for 5 combo points",
                    type = "color",
                    hasAlpha = false,
                    order = 4,
                    get = function()
                      local c = self.db.profile.cpColor5
                      return c[1], c[2], c[3]
                    end,
                    set = function(_, r, g, b)
                      local c = self.db.profile.cpColor5
                      c[1], c[2], c[3] = r, g, b
                      self:RefreshComboPoints()
                    end
                  }
                }
              },
              fontSizeGroup = {
                name = "Font Size",
                type = "group",
                inline = true,
                order = 2,
                args = {
                  cpFontSize = {
                    name = "Combo Points",
                    desc = "Font size of the combo point counter (points)",
                    type = "range",
                    min = 8,
                    max = 72,
                    step = 1,
                    order = 1,
                    width = 1.5,
                    get = function()
                      return self.db.profile.cpFontSize
                    end,
                    set = function(_, val)
                      self.db.profile.cpFontSize = val
                      self:UpdateBar()
                    end
                  },
                  cpBufferFontSize = {
                    name = "Overflow Points",
                    desc = "Font size of the overflow buffer indicator (points)",
                    type = "range",
                    min = 8,
                    max = 72,
                    step = 1,
                    order = 2,
                    width = 1.5,
                    get = function()
                      return self.db.profile.cpBufferFontSize
                    end,
                    set = function(_, val)
                      self.db.profile.cpBufferFontSize = val
                      self:UpdateBar()
                    end
                  },
                  fontSizeRowSpacer = GetSpacerEntry(3)
                }
              }
            }
          },
          layoutGroup = {
            name = "Layout",
            type = "group",
            inline = true,
            order = 2,
            args = {
              cpGroup = {
                name = "",
                type = "group",
                inline = true,
                order = 1,
                args = {
                  cpLabel = {
                    name = "Combo Points:",
                    desc = "Offset from the energy bar center (pixels)",
                    type = "description",
                    order = 1,
                    width = 1,
                    fontSize = "medium"
                  },
                  cpPosX = {
                    name = "X Offset", type = "range", min = -500, max = 500, step = 1, order = 2, width = 1,
                    get = function() return self.db.profile.cpPosX end,
                    set = function(_, val) self.db.profile.cpPosX = val; self:UpdateBar() end
                  },
                  cpPosY = {
                    name = "Y Offset", type = "range", min = -300, max = 300, step = 1, order = 3, width = 1,
                    get = function() return self.db.profile.cpPosY end,
                    set = function(_, val) self.db.profile.cpPosY = val; self:UpdateBar() end
                  }
                }
              },
              bufferGroup = {
                name = "",
                type = "group",
                inline = true,
                order = 2,
                args = {
                  bufferLabel = {
                    name = "Overflow Buffer:",
                    desc = "Offset from the energy bar center (pixels)",
                    type = "description",
                    order = 1,
                    width = 1,
                    fontSize = "medium"
                  },
                  cpBufferPosX = {
                    name = "X Offset", type = "range", min = -500, max = 500, step = 1, order = 2, width = 1,
                    get = function() return self.db.profile.cpBufferPosX end,
                    set = function(_, val) self.db.profile.cpBufferPosX = val; self:UpdateBar() end
                  },
                  cpBufferPosY = {
                    name = "Y Offset", type = "range", min = -300, max = 300, step = 1, order = 3, width = 1,
                    get = function() return self.db.profile.cpBufferPosY end,
                    set = function(_, val) self.db.profile.cpBufferPosY = val; self:UpdateBar() end
                  }
                }
              }
            }
          }
        }
      },

      -- ── Debuffs tab (target debuff icons, AuraContainer) ────────────────
      debuffTab = {
        name = "Debuffs",
        type = "group",
        order = 4,
        args = {
          appearanceGroup = {
            name = "Appearance",
            type = "group",
            inline = true,
            order = 1,
            args = {
              durationLabel = {
                name = "Duration:",
                type = "description",
                order = 1,
                width = 1,
                fontSize = "medium"
              },
              debuffNormalColor = {
                name = "Color",
                desc = "Color of the countdown number on each debuff icon. Applies live to already-shown icons while out of combat; in combat it applies as soon as combat ends.",
                type = "color",
                hasAlpha = false,
                order = 2,
                width = 1,
                get = function()
                  local c = self.db.profile.debuffNormalColor
                  return c[1], c[2], c[3]
                end,
                set = function(_, r, g, b)
                  local c = self.db.profile.debuffNormalColor
                  c[1], c[2], c[3] = r, g, b
                  self:ReapplyLiveAuraButtonSettings()
                  self:ReapplyLiveIconFrameFonts()
                end
              },
              durationRowSpacer = GetSpacerEntry(3),
              pandemicLabel = {
                name = "Pandemic Glow:",
                desc = "Highlights a debuff icon while it's inside its pandemic (early-refresh) window.",
                type = "description",
                order = 4,
                width = 1,
                fontSize = "medium"
              },
              pandemicColor = {
                name = "Color",
                desc = "Glow color for the pandemic (early-refresh) window. Simple Border style only — WoW Border is a fixed green for now. Applies live to already-shown icons while out of combat; in combat it applies as soon as combat ends.",
                type = "color",
                hasAlpha = true,
                order = 5,
                width = 1,
                get = function()
                  local c = self.db.profile.pandemicColor
                  return c[1], c[2], c[3], c[4]
                end,
                set = function(_, r, g, b, a)
                  local c = self.db.profile.pandemicColor
                  c[1], c[2], c[3], c[4] = r, g, b, a
                  self:ReapplyLiveAuraButtonSettings()
                  self:ReapplyPandemicPreviewGlowSettings()
                end
              },
              pandemicStyle = {
                name = "Style",
                desc = "Simple Border: a plain outset border in the Color above. WoW Border: Blizzard's own animated Assisted-Combat highlight ring (fixed green for now). Creation-time only — already-pooled icons need /reload to switch.",
                type = "select",
                order = 6,
                width = 1,
                values = {
                  custom = "Simple Border",
                  wow = "WoW Border",
                },
                get = function()
                  return self.db.profile.pandemicStyle
                end,
                set = function(_, val)
                  self.db.profile.pandemicStyle = val
                  self:ReapplyPandemicPreviewGlow()
                end
              },
              pandemicRowSpacer = GetSpacerEntry(7)
            }
          },
          layoutGroup = {
            name = "Layout",
            type = "group",
            inline = true,
            order = 2,
            args = {
              slot1Group = {
                name = "",
                type = "group",
                inline = true,
                order = 1,
                args = {
                  slot1Label = {
                    name = "Rake:",
                    desc = "Offset relative to the energy bar's center (pixels)",
                    type = "description",
                    order = 1,
                    width = 1,
                    fontSize = "medium"
                  },
                  slot1X = {
                    name = "X Offset", type = "range", min = -500, max = 500, step = 1, order = 2, width = 1,
                    get = function() return self.db.profile.debuffOffsets[1].x end,
                    set = function(_, val) self.db.profile.debuffOffsets[1].x = val; self:UpdateBar() end
                  },
                  slot1Y = {
                    name = "Y Offset", type = "range", min = -500, max = 500, step = 1, order = 3, width = 1,
                    get = function() return self.db.profile.debuffOffsets[1].y end,
                    set = function(_, val) self.db.profile.debuffOffsets[1].y = val; self:UpdateBar() end
                  }
                }
              },
              slot2Group = {
                name = "",
                type = "group",
                inline = true,
                order = 2,
                args = {
                  slot2Label = {
                    name = "Rip:",
                    desc = "Offset relative to the energy bar's center (pixels)",
                    type = "description",
                    order = 1,
                    width = 1,
                    fontSize = "medium"
                  },
                  slot2X = {
                    name = "X Offset", type = "range", min = -500, max = 500, step = 1, order = 2, width = 1,
                    get = function() return self.db.profile.debuffOffsets[2].x end,
                    set = function(_, val) self.db.profile.debuffOffsets[2].x = val; self:UpdateBar() end
                  },
                  slot2Y = {
                    name = "Y Offset", type = "range", min = -500, max = 500, step = 1, order = 3, width = 1,
                    get = function() return self.db.profile.debuffOffsets[2].y end,
                    set = function(_, val) self.db.profile.debuffOffsets[2].y = val; self:UpdateBar() end
                  }
                }
              },
              slot3Group = {
                name = "",
                type = "group",
                inline = true,
                order = 3,
                args = {
                  slot3Label = {
                    name = "Moonfire:",
                    desc = "Offset relative to the energy bar's center (pixels)",
                    type = "description",
                    order = 1,
                    width = 1,
                    fontSize = "medium"
                  },
                  slot3X = {
                    name = "X Offset", type = "range", min = -500, max = 500, step = 1, order = 2, width = 1,
                    get = function() return self.db.profile.debuffOffsets[3].x end,
                    set = function(_, val) self.db.profile.debuffOffsets[3].x = val; self:UpdateBar() end
                  },
                  slot3Y = {
                    name = "Y Offset", type = "range", min = -500, max = 500, step = 1, order = 3, width = 1,
                    get = function() return self.db.profile.debuffOffsets[3].y end,
                    set = function(_, val) self.db.profile.debuffOffsets[3].y = val; self:UpdateBar() end
                  }
                }
              }
            }
          }
        }
      },

      -- ── Proccs tab (target debuffs' sibling — player buff icons, AuraContainer) ──
      rowBottomTab = {
        name = "Proccs",
        type = "group",
        order = 5,
        args = {
          appearanceGroup = {
            name = "Appearance",
            type = "group",
            inline = true,
            order = 1,
            args = {
              durationLabel = {
                name = "Duration:",
                type = "description",
                order = 1,
                width = 1,
                fontSize = "medium"
              },
              buffNormalColor = {
                name = "Color",
                desc = "Color of the countdown number on each buff icon. Applies live to already-shown icons while out of combat; in combat it applies as soon as combat ends.",
                type = "color",
                hasAlpha = false,
                order = 2,
                width = 1,
                get = function()
                  local c = self.db.profile.buffNormalColor
                  return c[1], c[2], c[3]
                end,
                set = function(_, r, g, b)
                  local c = self.db.profile.buffNormalColor
                  c[1], c[2], c[3] = r, g, b
                  self:ReapplyLiveAuraButtonSettings()
                  self:ReapplyLiveIconFrameFonts()
                end
              },
              durationRowSpacer = GetSpacerEntry(3)
            }
          },
          layoutGroup = {
            name = "Layout",
            type = "group",
            inline = true,
            order = 2,
            args = {
              slot1Group = {
                name = "",
                type = "group",
                inline = true,
                order = 1,
                args = {
                  slot1Label = {
                    name = "Clearcasting:",
                    desc = "Offset relative to the energy bar's center (pixels)",
                    type = "description",
                    order = 1,
                    width = 1,
                    fontSize = "medium"
                  },
                  slot1X = {
                    name = "X Offset", type = "range", min = -500, max = 500, step = 1, order = 2, width = 1,
                    get = function() return self.db.profile.buffOffsets[1].x end,
                    set = function(_, val) self.db.profile.buffOffsets[1].x = val; self:UpdateBar() end
                  },
                  slot1Y = {
                    name = "Y Offset", type = "range", min = -500, max = 500, step = 1, order = 3, width = 1,
                    get = function() return self.db.profile.buffOffsets[1].y end,
                    set = function(_, val) self.db.profile.buffOffsets[1].y = val; self:UpdateBar() end
                  }
                }
              },
              slot2Group = {
                name = "",
                type = "group",
                inline = true,
                order = 2,
                args = {
                  slot2Label = {
                    name = "Predatory Swiftness:",
                    desc = "Offset relative to the energy bar's center (pixels)",
                    type = "description",
                    order = 1,
                    width = 1,
                    fontSize = "medium"
                  },
                  slot2X = {
                    name = "X Offset", type = "range", min = -500, max = 500, step = 1, order = 2, width = 1,
                    get = function() return self.db.profile.buffOffsets[2].x end,
                    set = function(_, val) self.db.profile.buffOffsets[2].x = val; self:UpdateBar() end
                  },
                  slot2Y = {
                    name = "Y Offset", type = "range", min = -500, max = 500, step = 1, order = 3, width = 1,
                    get = function() return self.db.profile.buffOffsets[2].y end,
                    set = function(_, val) self.db.profile.buffOffsets[2].y = val; self:UpdateBar() end
                  }
                }
              },
              stacksGroup = {
                name = "",
                type = "group",
                inline = true,
                order = 3,
                args = {
                  stacksLabel = {
                    name = "Stacks:",
                    desc = "Stack-count text offset from the icon's bottom-right corner (pixels)",
                    type = "description",
                    order = 1,
                    width = 1,
                    fontSize = "medium"
                  },
                  stacksX = {
                    name = "X Offset", type = "range", min = -30, max = 30, step = 1, order = 2, width = 1,
                    get = function() return self.db.profile.buffStacksPosX end,
                    set = function(_, val) self.db.profile.buffStacksPosX = val; self:ReapplyLiveAuraButtonSettings() end
                  },
                  stacksY = {
                    name = "Y Offset", type = "range", min = -30, max = 30, step = 1, order = 3, width = 1,
                    get = function() return self.db.profile.buffStacksPosY end,
                    set = function(_, val) self.db.profile.buffStacksPosY = val; self:ReapplyLiveAuraButtonSettings() end
                  }
                }
              }
            }
          }
        }
      },

      -- ── Cooldowns tab (Tiger's Fury/Berserk/Incarnation, own sorted AuraContainer) ──
      cooldownBuffTab = {
        name = "Cooldowns",
        type = "group",
        order = 6,
        args = {
          infoGroup = {
            name = "Information",
            type = "group",
            inline = true,
            order = 1,
            args = {
              cooldownBuffDesc = {
                name = "Tracks Tiger's Fury, Berserk, and Incarnation.",
                type = "description",
                order = 1,
                fontSize = "medium"
              }
            }
          },
          appearanceGroup = {
            name = "Appearance",
            type = "group",
            inline = true,
            order = 2,
            args = {
              durationLabel = {
                name = "Duration:",
                type = "description",
                order = 1,
                width = 1,
                fontSize = "medium"
              },
              cooldownBuffNormalColor = {
                name = "Color",
                desc = "Color of the countdown number on each cooldown-buff icon. Applies live to already-shown icons while out of combat; in combat it applies as soon as combat ends.",
                type = "color",
                hasAlpha = false,
                order = 2,
                width = 1,
                get = function()
                  local c = self.db.profile.cooldownBuffNormalColor
                  return c[1], c[2], c[3]
                end,
                set = function(_, r, g, b)
                  local c = self.db.profile.cooldownBuffNormalColor
                  c[1], c[2], c[3] = r, g, b
                  self:ReapplyLiveAuraButtonSettings()
                  self:ReapplyLiveIconFrameFonts()
                end
              },
              durationRowSpacer = GetSpacerEntry(3)
            }
          },
          layoutGroup = {
            name = "Layout",
            type = "group",
            inline = true,
            order = 3,
            args = {
              cooldownBuffPosX = {
                name = "X Offset",
                desc = "Horizontal offset of the cooldown-buff icon column from the energy bar center (pixels)",
                type = "range",
                min = -1000,
                max = 1000,
                step = 1,
                order = 1,
                width = 1,
                get = function()
                  return self.db.profile.cooldownBuffPosX
                end,
                set = function(_, val)
                  self.db.profile.cooldownBuffPosX = val
                  self:UpdateBar()
                end
              },
              cooldownBuffPosY = {
                name = "Y Offset",
                desc = "Vertical distance below the energy bar bottom edge (pixels) — top of the vertical stack",
                type = "range",
                min = -600,
                max = 600,
                step = 1,
                order = 2,
                width = 1,
                get = function()
                  return self.db.profile.cooldownBuffPosY
                end,
                set = function(_, val)
                  self.db.profile.cooldownBuffPosY = val
                  self:UpdateBar()
                end
              },
              cooldownBuffSpacing = {
                name = "Spacing",
                desc = "Vertical spacing between stacked cooldown-buff icons (pixels) — stacked top-to-bottom, not a horizontal row",
                type = "range",
                min = 0,
                max = 25,
                step = 1,
                order = 3,
                width = 1,
                get = function()
                  return self.db.profile.cooldownBuffSpacing
                end,
                set = function(_, val)
                  self.db.profile.cooldownBuffSpacing = val
                  self:UpdateBar()
                end
              },
              layoutRowSpacer = GetSpacerEntry(4)
            }
          }
        }
      }

    }
  }

  -- Profiles tab: per-character by default (AceDB-3.0's own behavior), but
  -- without this nothing lets the user switch to a shared profile, copy one
  -- from another character, or reset to defaults — this is that UI.
  options.args.profilesTab = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
  options.args.profilesTab.order = 7

  LibStub("AceConfig-3.0"):RegisterOptionsTable("BloodInTheWater", options)
  LibStub("AceConfigDialog-3.0"):AddToBlizOptions("BloodInTheWater", "Blood in the Water")
  -- Wider than Ace3's ~700px default so 4-widget rows (e.g. Debuffs'
  -- Appearance group) fit on one line instead of wrapping.
  LibStub("AceConfigDialog-3.0"):SetDefaultSize("BloodInTheWater", 900, 600)
end

-- Opens the configuration dialog (slash command /bitw)
function Addon:OpenConfig()
  LibStub("AceConfigDialog-3.0"):Open("BloodInTheWater")
end
