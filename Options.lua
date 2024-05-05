-- Get Addon's name and Blizzard's Addon Stub
local AddonName, addon = ...

-- Local handle to the Engine
local x = addon.engine

function x:InitOptions()
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
                            name = "Excluded spells for " .. self.playerSpecName .. " " .. self.playerClassLocalized,
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

        if self.db.profile.excludedSpellIds[self.playerClass] and self.db.profile.excludedSpellIds[self.playerClass][self.playerSpecId] then
            for spellId, _ in pairs(self.db.profile.excludedSpellIds[self.playerClass][self.playerSpecId]) do
                exclusions[spellId] = GetSpellInfo(tonumber(spellId))
            end
        end

        options["args"]["exclusions"]["args"]["excludedNewSpells"]["values"] = exclusions

        return options
    end

    LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName .. "_options", GetOptions)
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddonName .. "_options", AddonName)

    local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName .. "_profiles", profiles)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddonName .. "_profiles", "Profiles", AddonName)
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


function x:IsSpellIdExcluded(info, spellId)
    if not self.db.profile.excludedSpellIds[self.playerClass] or not self.db.profile.excludedSpellIds[self.playerClass][self.playerSpecId] then
        return false
    end

    return self.db.profile.excludedSpellIds[self.playerClass][self.playerSpecId][tostring(spellId)]
end


function x:SetSpellIdExcluded(info, spellId, isExcluded)
    if not self.db.profile.excludedSpellIds[self.playerClass] then
        self.db.profile.excludedSpellIds[self.playerClass] = {}
    end

    if not self.db.profile.excludedSpellIds[self.playerClass][self.playerSpecId] then
        self.db.profile.excludedSpellIds[self.playerClass][self.playerSpecId] = {}
    end

    if isExcluded then
        self.db.profile.excludedSpellIds[self.playerClass][self.playerSpecId][tostring(spellId)] = true
    else
        self.db.profile.excludedSpellIds[self.playerClass][self.playerSpecId][tostring(spellId)] = nil
    end

    self:updateEverything()
end
