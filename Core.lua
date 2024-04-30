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

    self.spellsOnCooldown = {}
    self.spellsNotOnCooldown = {}
end


function x:OnEnable()
    if not self.tooltip then
        self.tooltip = CreateFrame("GameTooltip", "RAButtonGlowScanTooltip", UIParent, "GameTooltipTemplate")
        self.tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end

    self:updateEverything()

    self:RegisterEvent("UNIT_SPELLCAST_SENT", "OnSpellCastSent")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellCastSucceeded")

    self:ScheduleRepeatingTimer("checkCooldowns", 1) -- TODO revert back to 1
end


function x:checkCooldowns()
    self:Print(
        "Checking ",
        #self.spellsOnCooldown,
        " spells on cooldown..."
    )

    for spellId in pairs(self.spellsOnCooldown) do
        local start = GetSpellCooldown(spellId, BOOKTYPE_SPELL)

        -- TODO was ist mit charges?

        if start ~= nil or start == 0 then
            self:Print(
                GetSpellLink(spellId),
                '  isnt on CD anymore.'
            )

            for _, button in pairs(self.buttonSpellIds[spellId]) do
                _G["WeakAuras"].ShowOverlayGlow(button)
            end

            self.spellsOnCooldown[spellId] = nil
            self.spellsNotOnCooldown[spellId] = 1
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

                if self.spellsNotOnCooldown[spellId] == nil then
                    -- We're setting the spell "on cooldown" because then the checkCooldowns() will check it.
                    self.spellsOnCooldown[spellId] = 1
                    self.spellsNotOnCooldown[spellId] = nil
                end
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

    for spellId in pairs(self.spellsOnCooldown) do
        self:Print(
            GetSpellLink(spellId),
            ' is on cooldown.'
        )
    end

    for spellId in pairs(self.spellsNotOnCooldown) do
        self:Print(
            GetSpellLink(spellId),
            ' is not on cooldown.'
        )
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

function x:OnSpellCastSent(eventName, unit, target, castGUID, spellId)
    -- https://wowpedia.fandom.com/wiki/UNIT_SPELLCAST_SENT
    if unit == "player" then
        self.currentCastGUID = castGUID
    end
end


function x:OnSpellCastSucceeded(eventName, unitTarget, castGUID, spellId)
    -- https://wowpedia.fandom.com/wiki/UNIT_SPELLCAST_SUCCEEDED
    if self.currentCastGUID == castGUID then
        self.currentCastGUID = nil

        if self.buttonSpellIds[spellId] and self.spellCooldowns[spellId] and self.spellCooldowns[spellId] >= self:GetCooldownMinimum() then
            local currentCharges = GetSpellCharges(spellId)

            if currentCharges == 1 or currentCharges == nil then
                -- IDK why but Blood Boil has "currentCharges == 1" when none were available
                for _, button in pairs(self.buttonSpellIds[spellId]) do
                    self:Print(
                        button:GetName(),
                        GetSpellLink(spellId),
                        " should stop glowing."
                    )
                    _G["WeakAuras"].HideOverlayGlow(button)
                end

                self.spellsOnCooldown[spellId] = 1
                self.spellsNotOnCooldown[spellId] = nil
            else
                for _, button in pairs(self.buttonSpellIds[spellId]) do
                    self:Print(
                        button:GetName(),
                        GetSpellLink(spellId),
                        " should still be glowing, because it has ",
                        currentCharges - 1,
                        " charges."
                    )
                end
            end
        end
    end
end
