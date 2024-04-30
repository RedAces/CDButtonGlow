-- Get Addon's name and Blizzard's Addon Stub
local AddonName, addon = ...

-- See https://wowpedia.fandom.com/wiki/Ace3_for_Dummies
addon.engine = LibStub("AceAddon-3.0"):NewAddon(AddonName, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

-- Local Handle to the Engine
local x = addon.engine

function x:OnInitialize()
    local dbDefaults = {
        profile = {
            cooldownMinimum = 30
        }
    }
    self.db = LibStub("AceDB-3.0"):New("RAButtonGlowDB", dbDefaults, true)

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
        },
    }

    LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName .. "_options", options)
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddonName .. "_options", AddonName)

	local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName .. "_profiles", profiles)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddonName .. "_profiles", "Profiles", AddonName)

    self:RegisterChatCommand('rabg', 'SlashCommand')

    self.activeGlows = {}
end


function x:OnEnable()
    if not self.tooltip then
        self.tooltip = CreateFrame("GameTooltip", "RAButtonGlowScanTooltip", UIParent, "GameTooltipTemplate")
        self.tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end

    self:updateEverything()

    self:ScheduleRepeatingTimer("checkCooldowns", 1) -- TODO revert back to 1
end


function x:checkCooldowns()
    for spellId, buttons in pairs(self.buttonSpellIds) do
        local start = GetSpellCooldown(spellId, BOOKTYPE_SPELL)

        local isOnCooldown = start ~= nil and start > 0

        -- TODO was ist mit charges?

        for _, button in pairs(buttons) do
            if isOnCooldown and self.activeGlows[button:GetName()] ~= nil then
                self:Print(
                    GetSpellLink(spellId),
                    'is now on CD and',
                    button:GetName(),
                    'should stop glowing.'
                )
                _G["WeakAuras"].HideOverlayGlow(button)
                self.activeGlows[button:GetName()] = nil
            end

            if isOnCooldown == false and self.activeGlows[button:GetName()] == nil then
                self:Print(
                    GetSpellLink(spellId),
                    'isnt on CD anymore and',
                    button:GetName(),
                    'should start glowing.'
                )
                _G["WeakAuras"].ShowOverlayGlow(button)
                self.activeGlows[button:GetName()] = 1
            end
        end
    end
end


function x:analyseButton(button)
    local slot = button:CalculateAction()
    if slot and HasAction(slot) then
        local spellId = 0
        local actionType, id = GetActionInfo(slot)
        if actionType == "macro" then
            spellId = GetMacroSpell(id)
        elseif actionType == "spell" then
            spellId = id
        end

        if spellId and spellId ~= 0 then
            local cooldown = self:ParseSpellCooldown(spellId)
            if cooldown ~= nil and cooldown >= self:GetCooldownMinimum() then
                self.buttonSpellIds[spellId] = self.buttonSpellIds[spellId] or {}
                table.insert(self.buttonSpellIds[spellId], button)
            end
        end
    end
end


function x:updateEverything()
    self.buttonSpellIds = {}
    self.spellCooldowns = {}

    if _G.Bartender4 then
        for i = 1, 120 do
            local button = _G["BT4Button"..i]
            if button then
                self:analyseButton(button)
            end
        end
    elseif _G.ElvUI then
        for barNum = 1, 10 do
            for buttonNum = 1, 12 do
                local button = _G["ElvUI_Bar" .. barNum .. "Button" .. buttonNum]
                if button then
                    self:analyseButton(button)
                end
            end
        end
    elseif _G.Dominos then
        for i = 1, 168 do
            local button = _G["DominosActionButton" .. i]
            if button then
                self:analyseButton(button)
            end
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
                local button = _G[barName .. "Button" .. i]
                if button then
                    self:analyseButton(button)
                end
            end
        end
    end
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
        x:updateEverything()
    elseif msg == 'show' then
        x:ShowButtonSpells()
    end
end


function x:GetCooldownMinimum(info)
    return self.db.profile.cooldownMinimum
end


function x:SetCooldownMinimum(info, value)
    self.db.profile.cooldownMinimum = value
    self:updateEverything()
end
