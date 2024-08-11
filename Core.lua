-- Get Addon's name and Blizzard's Addon Stub
local AddonName, addon = ...

-- https://wowpedia.fandom.com/wiki/Ace3_for_Dummies
addon.engine = LibStub('AceAddon-3.0'):NewAddon(AddonName, 'AceConsole-3.0', 'AceEvent-3.0', 'AceTimer-3.0')

-- Local handle to the Engine
local x = addon.engine

-- Local handle to Libs
local LCG = LibStub('LibCustomGlow-1.0')

function x:OnInitialize()
    local dbDefaults = {
        profile = {
            cooldownMinimum = 30,
            glowType = 'pixel',
            excludedSpellIds = {}
        }
    }
    self.db = LibStub('AceDB-3.0'):New('CDButtonGlowDB', dbDefaults, true)

    self:InitOptions()

    self.activeGlows = {}
    self.debug = false
    self.isDragonRiding = false
    self.spellCooldowns = {}
end


function x:OnEnable()
    if not self.tooltip then
        self.tooltip = CreateFrame('GameTooltip', 'CDButtonGlowScanTooltip', UIParent, 'GameTooltipTemplate')
        self.tooltip:SetOwner(WorldFrame, 'ANCHOR_NONE')
    end

    self:updateEverything()

    self:RegisterEvent('ACTIONBAR_HIDEGRID', 'updateEverythingDelayed')
    self:RegisterEvent('PLAYER_TALENT_UPDATE', 'updateEverythingDelayed')
    self:RegisterEvent('PLAYER_SPECIALIZATION_CHANGED', 'updateEverythingDelayed')
    self:RegisterEvent('SPELLS_CHANGED', 'updateEverythingDelayed')

    self:RegisterEvent('UNIT_POWER_BAR_SHOW', 'onPowerBarChange')
    self:RegisterEvent('UNIT_POWER_BAR_HIDE', 'onPowerBarChange')

    self:RegisterEvent('PLAYER_ENTERING_WORLD', 'onPlayerEnteringWorld')
end


function x:checkCooldowns()
    for spellId, buttons in pairs(self.buttonSpellIds) do
        if not self:IsSpellIdExcluded({}, spellId) then
            local spellCdInfo = C_Spell.GetSpellCooldown(spellId)
            local start = spellCdInfo.startTime or 0
            local duration = spellCdInfo.duration or 0

            local now = GetTime()
            local isOnCooldown = start and start > 0
            local isOnGcd = isOnCooldown and duration and (start + duration - now) <= 1.5

            -- TODO Charges?

            for _, button in pairs(buttons) do
                if isOnCooldown and not isOnGcd and self.activeGlows[button:GetName()] then
                    -- only hide the glow if its on cooldown but not on GCD
                    if self.debug then
                        local spellLink = C_Spell.GetSpellLink(spellId)

                        self:Print(
                            spellLink,
                            'is now on CD and',
                            button:GetName(),
                            'should stop glowing.'
                        )
                    end
                    self:HideGlow(button, true)
                end

                if not isOnCooldown and not self.activeGlows[button:GetName()] then
                    if self.debug then
                        local spellLink = C_Spell.GetSpellLink(spellId)
                        self:Print(
                            spellLink,
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


function x:analyseButton(button, debug)
    if not button then
        return
    end

    if not button:IsVisible() then
        if debug then
            self:Print(button:GetName() .. ' is invisible.')
        end
        return
    end

    local slot = button:CalculateAction()
    if slot and HasAction(slot) then
        local spellId = 0
        local actionType, id, subType = GetActionInfo(slot)
        if actionType == 'macro' and subType == 'spell' then
            spellId = id
        elseif actionType == 'spell' then
            spellId = id
        end

        if spellId and spellId ~= 0 then
            if not IsPlayerSpell(spellId)
                    and not IsSpellKnown(spellId, true)
                    and not IsPlayerSpell(spellId)
                    and spellId ~= 212641 -- Bugfix Patch 10.2.7: Protection Paladin's Guardian of Ancient Kings
            then
                if debug then
                    self:Print(button:GetName() .. ' has UNKNOWN spell ' .. self:GetSpellName(spellId) .. ' (#' .. spellId .. ') on it.')
                end
                return
            end

            if debug then
                self:Print(button:GetName() .. ' has spell ' .. self:GetSpellName(spellId) .. ' (#' .. spellId .. ').')
            end

            local cooldown = self:ParseSpellCooldown(spellId)

            if debug then
                if cooldown then
                    if cooldown >= self:GetCooldownMinimum() then
                        self:Print(button:GetName() .. ': found cooldown of ' .. cooldown .. ' seconds, its longer than the configured minimum of ' .. self:GetCooldownMinimum() .. ' seconds.')
                    else
                        self:Print(button:GetName() .. ': found cooldown of ' .. cooldown .. ' seconds, its shorter than the configured minimum of ' .. self:GetCooldownMinimum() .. ' seconds.')
                    end
                else
                    self:Print(button:GetName() .. ': found NO cooldown.')
                end
            end

            if cooldown ~= nil and cooldown >= self:GetCooldownMinimum() then
                self.buttonSpellIds[spellId] = self.buttonSpellIds[spellId] or {}
                table.insert(self.buttonSpellIds[spellId], button)
            end
        else
            if debug then
                self:Print(button:GetName() .. ' has no spell on it.')
            end
        end
    else
        if debug then
            self:Print(button:GetName() .. ' has no action on it.')
        end
    end
end


function x:updateEverything()
    self.playerClassLocalized, self.playerClass = UnitClass('player')
    self.playerSpecId = GetSpecialization()
    _, self.playerSpecName = GetSpecializationInfo(self.playerSpecId)

    if self.checkCooldownsTimer then
        self:CancelTimer(self.checkCooldownsTimer)
        self.checkCooldownsTimer = nil
    end

    self:HideAllActiveGlows(true)

    self.buttonSpellIds = {}

    if _G.Bartender4 then
        for i = 1, 120 do
            self:analyseButton(_G['BT4Button'..i], false)
        end
    elseif _G.ElvUI then
        for barNum = 1, 10 do
            for buttonNum = 1, 12 do
                self:analyseButton(_G['ElvUI_Bar' .. barNum .. 'Button' .. buttonNum], false)
            end
        end
    elseif _G.Dominos then
        for i = 1, 168 do
            self:analyseButton(_G['DominosActionButton' .. i], false)
        end
    else
        local actionBars = {
            'Action',
            'MultiBarBottomLeft',
            'MultiBarBottomRight',
            'MultiBarRight',
            'MultiBarLeft',
            'MultiBar5',
            'MultiBar6',
            'MultiBar7'
        }
        for _, barName in pairs(actionBars) do
            for i = 1, 12 do
                self:analyseButton(_G[barName .. 'Button' .. i], false)
            end
        end
    end

    -- https://www.wowace.com/projects/ace3/pages/api/ace-timer-3-0
    self.checkCooldownsTimer = self:ScheduleRepeatingTimer('checkCooldowns', 0.1)
end

function x:updateEverythingDelayed(eventName)
    if self.debug then
        self:Print('Updating everything in 0.25 sec because of', eventName, '...')
    end

    self:ScheduleTimer('updateEverything', 0.25)
end


function x:ParseSpellCooldown(spellId)
    self.tooltip:ClearLines()
    self.tooltip:SetSpellByID(spellId)

    local numLines = self.tooltip:NumLines()
    if numLines == 0 then
        local spellLink = C_Spell.GetSpellLink(spellId)

        self:Print(
            'Tooltip has 0 lines for spell',
            spellLink
        )
        self.tooltip:Hide()
        self.tooltip = CreateFrame('GameTooltip', 'CDButtonGlowScanTooltip', UIParent, 'GameTooltipTemplate')
        self.tooltip:SetOwner(WorldFrame, 'ANCHOR_NONE')
        self.tooltip:SetSpellByID(spellId)
    end

    for line = 1, self.tooltip:NumLines() do
        local tooltipTextObject = _G[self.tooltip:GetName() .. 'TextRight' .. line]
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


function x:ShowButtonSpells()
    for spellId, buttons in pairs(self.buttonSpellIds) do
        for _, button in pairs(buttons) do
            local spellLink = C_Spell.GetSpellLink(spellId)

            self:Print(
                spellLink,
                ': ',
                button:GetName(),
                ' ',
                self.spellCooldowns[spellId] or 'no',
                ' CD'
            )
        end
    end
end


function x:ShowGlow(button)
    local glowType = self:GetGlowType()
    if glowType == 'pixel' then
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
    elseif glowType == 'procc' then
        LCG.ProcGlow_Start(button)
    elseif glowType == 'autocast' then
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
    elseif glowType == 'blizz' then
        LCG.ButtonGlow_Start(button)
    end

    self.activeGlows[button:GetName()] = button
end


function x:HideGlow(button, removeFromActiveGlows)
    local glowType = self:GetGlowType()
    if glowType == 'pixel' then
        LCG.PixelGlow_Stop(
            button,
            AddonName .. '_glow'
        )
    elseif glowType == 'procc' then
        LCG.ProcGlow_Stop(button)
    elseif glowType == 'autocast' then
        LCG.AutoCastGlow_Stop(
            button,
            AddonName .. '_glow'
        )
    elseif glowType == 'blizz' then
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
    local isDragonRiding = UnitPowerBarID('player') == 631

    if self.isDragonRiding ~= isDragonRiding then
        self.isDragonRiding = isDragonRiding

        if self.debug then
            if self.isDragonRiding then
                self:Print('Player is now dragon riding.')
            else
                self:Print('Player is not dragon riding.')
            end
        end

        self:updateEverythingDelayed(eventName)
    end
end


function x:onPlayerEnteringWorld()
    self.isDragonRiding = UnitPowerBarID('player') == 631
end


function x:GetSpellName(spellId)
    return C_Spell.GetSpellName(spellId)
end
