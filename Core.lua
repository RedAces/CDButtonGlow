-- Get Addon's name and Blizzard's Addon Stub
local AddonName, addon = ...

-- https://wowpedia.fandom.com/wiki/Ace3_for_Dummies
addon.engine = LibStub("AceAddon-3.0"):NewAddon(AddonName, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

-- Local handle to the Engine
local x = addon.engine

-- Local handle to Libs
local LCG = LibStub("LibCustomGlow-1.0")

function x:OnInitialize()
    local dbDefaults = {
        profile = {
            cooldownMinimum = 30,
            glowType = "pixel",
            excludedSpellIds = {}
        }
    }
    self.db = LibStub("AceDB-3.0"):New("RAButtonGlowDB", dbDefaults, true)

    -- https://www.wowace.com/projects/ace3/pages/ace-config-3-0-options-tables
    local function GetOptions()
        local options = {
            name = AddonName,
            handler = x,
            type = "group",
            args = {
                cooldownMinimum = {
                    type = "range",
                    name = "Cooldown Minimum",
                    desc = "Only glow buttons of spells with a cooldown of at least x seconds.",
                    min = 0,
                    max = 300,
                    step = 1,
                    bigStep = 30,
                    get = "GetCooldownMinimum",
                    set = "SetCooldownMinimum",
                },
                glowType = {
                    type = "select",
                    name = "Type of action bar glow",
                    desc = "Which type of glow do you want?",
                    values = {
                        autocast = "Auto Cast Shine",
                        pixel = "Pixel Glow",
                        procc = "Proc Glow",
                        blizz = "Action Button Glow"
                    },
                    get = "GetGlowType",
                    set = "SetGlowType",
                },
                exclusions = {
                    type = "group",
                    name = "Excluded spells",
                    args = {
                        excludedNewSpells = {
                            type = "multiselect",
                            name = "Excluded spells",
                            desc = "For which spells do you want the buttons to NOT light up?",
                            get = "IsSpellIdExcluded",
                            set = "SetSpellIdExcluded"
                        }
                    }
                }
            },
        }

        local exclusions = {}
        for spellId, _ in pairs(self.buttonSpellIds) do
            exclusions[tostring(spellId)] = GetSpellInfo(spellId)
        end

        options["args"]["exclusions"]["args"]["excludedNewSpells"]["values"] = exclusions

        -- TODO add already excluded spells to it

        return options
    end

    LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName .. "_options", GetOptions)
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddonName .. "_options", AddonName)

    local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName .. "_profiles", profiles)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddonName .. "_profiles", "Profiles", AddonName)

    self:RegisterChatCommand('rabg', 'SlashCommand')

    self.debug = false
    self.activeGlows = {}
    self.isDragonRiding = false
end


function x:OnEnable()
    if not self.tooltip then
        self.tooltip = CreateFrame("GameTooltip", "RAButtonGlowScanTooltip", UIParent, "GameTooltipTemplate")
        self.tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end

    self:updateEverything()

    self:RegisterEvent("ACTIONBAR_HIDEGRID", "updateEverythingDelayed")
    self:RegisterEvent("PLAYER_TALENT_UPDATE", "updateEverythingDelayed")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "updateEverythingDelayed")
    self:RegisterEvent("SPELLS_CHANGED", "updateEverythingDelayed")

    self:RegisterEvent("UNIT_POWER_BAR_SHOW", "onPowerBarChange")
    self:RegisterEvent("UNIT_POWER_BAR_HIDE", "onPowerBarChange")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "onPlayerEnteringWorld")
end


function x:checkCooldowns()
    for spellId, buttons in pairs(self.buttonSpellIds) do
        if not self:IsSpellIdExcluded({}, spellId) then
            local start, duration = GetSpellCooldown(spellId)
            local now = GetTime()

            local isOnCooldown = start and start > 0
            local isOnGcd = isOnCooldown and duration and (start + duration - now) <= 1.5

            -- TODO was ist mit charges?

            for _, button in pairs(buttons) do
                if isOnCooldown and not isOnGcd and self.activeGlows[button:GetName()] then
                    -- only hide the glow if its on cooldown but not on GCD
                    if self.debug then
                        self:Print(
                            GetSpellLink(spellId),
                            'is now on CD and',
                            button:GetName(),
                            'should stop glowing.'
                        )
                    end
                    self:HideGlow(button, true)
                end

                if not isOnCooldown and not self.activeGlows[button:GetName()] then
                    if self.debug then
                        self:Print(
                            GetSpellLink(spellId),
                            'isnt on CD anymore and',
                            button:GetName(),
                            'should start glowing.'
                        )
                    end
                    self:ShowGlow(button)
                end
            end
        end
    end
end


function x:analyseButton(button)
    if not button then
        return
    end

    if not button:IsVisible() then
        return
    end

    local slot = button:CalculateAction()
    if slot and HasAction(slot) then
        local spellId = 0
        local actionType, id, subType = GetActionInfo(slot)
        if actionType == "macro" and subType == "spell" then
            spellId = id
        elseif actionType == "spell" then
            spellId = id
        end

        if spellId and spellId ~= 0 then
            -- 2nd parameter is "IsPetSpell"
            if not IsSpellKnown(spellId) and not IsSpellKnown(spellId, true) then
                return
            end

            local cooldown = self:ParseSpellCooldown(spellId)
            if cooldown ~= nil and cooldown >= self:GetCooldownMinimum() then
                self.buttonSpellIds[spellId] = self.buttonSpellIds[spellId] or {}
                table.insert(self.buttonSpellIds[spellId], button)
            end
        end
    end
end


function x:updateEverything(arg1)
    if self.checkCooldownsTimer then
        self:CancelTimer(self.checkCooldownsTimer)
        self.checkCooldownsTimer = nil
    end

    self:HideAllActiveGlows(true)

    self.buttonSpellIds = {}
    self.spellCooldowns = {}

    if _G.Bartender4 then
        for i = 1, 120 do
            self:analyseButton(_G["BT4Button"..i])
        end
    elseif _G.ElvUI then
        for barNum = 1, 10 do
            for buttonNum = 1, 12 do
                self:analyseButton(_G["ElvUI_Bar" .. barNum .. "Button" .. buttonNum])
            end
        end
    elseif _G.Dominos then
        for i = 1, 168 do
            self:analyseButton(_G["DominosActionButton" .. i])
        end
    else
        local actionBars = {
            "Action",
            "MultiBarBottomLeft",
            "MultiBarBottomRight",
            "MultiBarRight",
            "MultiBarLeft",
            "MultiBar5",
            "MultiBar6",
            "MultiBar7"
        }
        for _, barName in pairs(actionBars) do
            for i = 1, 12 do
                self:analyseButton(_G[barName .. "Button" .. i])
            end
        end
    end

    -- https://www.wowace.com/projects/ace3/pages/api/ace-timer-3-0
    self.checkCooldownsTimer = self:ScheduleRepeatingTimer("checkCooldowns", 0.1)
end

function x:updateEverythingDelayed(eventName)
    if self.debug then
        self:Print("Updating everything in 0.25 sec because of", eventName, "...")
    end

    self:ScheduleTimer("updateEverything", 0.25)
end


function x:ParseSpellCooldown(spellId)
    if not self.spellCooldowns[spellId] then
        self.tooltip:ClearLines()
        self.tooltip:SetSpellByID(spellId)

        for line = 1, self.tooltip:NumLines() do
            local tooltipTextObject = _G[self.tooltip:GetName() .. "TextRight" .. line]
            local cooldownText = tooltipTextObject:GetText()

            if cooldownText then
                local matches = cooldownText:match('([0-9.]+) min cooldown')
                if matches then
                    self.spellCooldowns[spellId] = tonumber(matches) * 60
                    return self.spellCooldowns[spellId]
                end

                matches = cooldownText:match('([0-9.]+) sec cooldown')
                if matches then
                    self.spellCooldowns[spellId] = tonumber(matches)
                    return self.spellCooldowns[spellId]
                end

                matches = cooldownText:match('([0-9.]+) min recharge')
                if matches then
                    self.spellCooldowns[spellId] = tonumber(matches) * 60
                    return self.spellCooldowns[spellId]
                end

                matches = cooldownText:match('([0-9.]+) sec recharge')
                if matches then
                    self.spellCooldowns[spellId] = tonumber(matches)
                    return self.spellCooldowns[spellId]
                end
            end
        end
    end

    return self.spellCooldowns[spellId]
end


function x:ShowButtonSpells()
    for spellId, buttons in pairs(self.buttonSpellIds) do
        for _, button in pairs(buttons) do
            self:Print(
                GetSpellLink(spellId),
                ': ',
                button:GetName(),
                ' ',
                self.spellCooldowns[spellId] or 'no',
                ' CD'
            )
        end
    end
end


function x:SlashCommand(msg)
    if msg == 'update' then
        self:updateEverything()
    elseif msg == 'show' then
        self:ShowButtonSpells()
    elseif msg == 'debug' then
        self.debug = not self.debug
    end
end


function x:GetCooldownMinimum(info)
    return self.db.profile.cooldownMinimum
end


function x:SetCooldownMinimum(info, value)
    self.db.profile.cooldownMinimum = value
    self:updateEverything()
end


function x:GetGlowType(info)
    return self.db.profile.glowType
end


function x:SetGlowType(info, value)
    self:HideAllActiveGlows(false)

    self.db.profile.glowType = value

    for _, button in pairs(self.activeGlows) do
        self:ShowGlow(button)
    end
end


function x:ShowGlow(button)
    local glowType = self:GetGlowType()
    if glowType == "pixel" then
        LCG.PixelGlow_Start(
            button,
            nil,
            nil,
            nil,
            nil,
            nil,
            nil,
            nil,
            nil,
            AddonName .. '_glow'
        )
    elseif glowType == "procc" then
        LCG.ProcGlow_Start(button)
    elseif glowType == "autocast" then
        LCG.AutoCastGlow_Start(
            button,
            nil,
            nil,
            nil,
            nil,
            nil,
            nil,
            AddonName .. '_glow'
        )
    elseif glowType == "blizz" then
        LCG.ButtonGlow_Start(button)
    end

    self.activeGlows[button:GetName()] = button
end


function x:HideGlow(button, removeFromActiveGlows)
    local glowType = self:GetGlowType()
    if glowType == "pixel" then
        LCG.PixelGlow_Stop(
            button,
            AddonName .. '_glow'
        )
    elseif glowType == "procc" then
        LCG.ProcGlow_Stop(button)
    elseif glowType == "autocast" then
        LCG.AutoCastGlow_Stop(
            button,
            AddonName .. '_glow'
        )
    elseif glowType == "blizz" then
        LCG.ButtonGlow_Stop(button)
    end

    if removeFromActiveGlows then
        self.activeGlows[button:GetName()] = nil
    end
end


function x:HideAllActiveGlows(removeFromActiveGlows)
    for _, button in pairs(self.activeGlows) do
        self:HideGlow(button, removeFromActiveGlows)
    end
end


function x:onPowerBarChange(eventName)
    local isDragonRiding = UnitPowerBarID("player") == 631

    if self.isDragonRiding ~= isDragonRiding then
        self.isDragonRiding = isDragonRiding

        if self.debug then
            if self.isDragonRiding then
                self:Print("Player is now dragon riding.")
            else
                self:Print("Player is not dragon riding.")
            end
        end

        self:updateEverythingDelayed(eventName)
    end
end


function x:onPlayerEnteringWorld()
    self.isDragonRiding = UnitPowerBarID("player") == 631
end


function x:IsSpellIdExcluded(info, spellId)
    return self.db.profile.excludedSpellIds[tostring(spellId)]
end


function x:SetSpellIdExcluded(info, spellId, isExcluded)
    self.db.profile.excludedSpellIds[tostring(spellId)] = isExcluded
    self:updateEverything()
end
