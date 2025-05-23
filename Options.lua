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
            type = 'group',
            args = {
                explanation = {
                    type = 'description',
                    name = 'CD Button Glow lights up your action bar buttons if the spell behind it is ready. You can customize which spells are used and which glow you want.'
                },
                general = {
                    type = 'group',
                    name = 'General options',
                    order = 100,
                    args = {
                        cooldownMinimum = {
                            type = 'range',
                            name = 'Cooldown Minimum',
                            desc = 'Only glow buttons of spells with a cooldown of at least x seconds.',
                            min = 0,
                            max = 300,
                            step = 1,
                            bigStep = 30,
                            get = 'GetCooldownMinimum',
                            set = 'SetCooldownMinimum',
                        },
                        glowType = {
                            type = 'select',
                            name = 'Type of action bar glow',
                            desc = 'Which type of glow do you want?',
                            values = {
                                autocast = 'Auto Cast Shine',
                                pixel = 'Pixel Glow',
                                procc = 'Proc Glow',
                                blizz = 'Action Button Glow'
                            },
                            get = 'GetGlowType',
                            set = 'SetGlowType',
                        },
                        disableOutOfCombat = {
                            type = 'toggle',
                            name = 'Disable out of combat',
                            desc = 'Only enable the glows while in combat?',
                            get = 'DisableOutOfCombat',
                            set = 'SetDisableOutOfCombat',
                        },
                    }
                },
                exclusions = {
                    type = 'group',
                    name = 'Excluded spells',
                    order = 200,
                    args = {
                        explanation = {
                            type = 'description',
                            name = 'You can exclude spells from the action bar glow if you want. This is saved per specialization, so you can exclude a spell in one specc but let its button glow in another.',
                            order = 100
                        },
                        excludedNewSpells = {
                            type = 'multiselect',
                            name = 'Excluded spells for ' .. self.playerSpecName .. ' ' .. self.playerClassLocalized,
                            order = 200,
                            desc = 'For which spells do you want the buttons to NOT light up?',
                            get = 'IsSpellIdExcluded',
                            set = 'SetSpellIdExcluded'
                        }
                    }
                }
            }
        }

        local exclusions = {}
        for spellId, _ in pairs(self.buttonSpellIds) do
            exclusions[tostring(spellId)] = self:GetSpellName(spellId)
        end

        if self.db.profile.excludedSpellIds[self.playerClass] and self.db.profile.excludedSpellIds[self.playerClass][self.playerSpecId] then
            for spellId, _ in pairs(self.db.profile.excludedSpellIds[self.playerClass][self.playerSpecId]) do
                exclusions[spellId] = self:GetSpellName(tonumber(spellId))
            end
        end

        options['args']['exclusions']['args']['excludedNewSpells']['values'] = exclusions

        return options
    end

    LibStub('AceConfig-3.0'):RegisterOptionsTable(AddonName .. '_options', GetOptions)
    self.optionsFrame = LibStub('AceConfigDialog-3.0'):AddToBlizOptions(AddonName .. '_options', AddonName)

    local profiles = LibStub('AceDBOptions-3.0'):GetOptionsTable(self.db)
    LibStub('AceConfig-3.0'):RegisterOptionsTable(AddonName .. '_profiles', profiles)
    LibStub('AceConfigDialog-3.0'):AddToBlizOptions(AddonName .. '_profiles', 'Profiles', AddonName)

    self:RegisterChatCommand('cdbg', 'SlashCommand')
    self:RegisterChatCommand('cdbuttonglow', 'SlashCommand')

    AddonCompartmentFrame:RegisterAddon({
      text = AddonName,
      registerForAnyClick = true,
      notCheckable = true,
      func = function()
        Settings.OpenToCategory(self.optionsFrame.name)
      end
    })
end


function x:SlashCommand(msg)
    if not msg or msg == '' then
        Settings.OpenToCategory(self.optionsFrame.name)
        return
    end

    if msg == 'update' then
        self:UpdateEverything()
        return
    end

    if msg == 'show' then
        self:ShowButtonSpells()
        return
    end

    if msg == 'debug' then
        self.debug = not self.debug
        return
    end

    local command, args = msg:match('^([a-zA-Z0-9-]+) (.*)')
    if command == 'analyse-btn' or command == 'analyze-btn' then
        self:analyseButton(_G[args], true)
        return
    end

    self:Print('Unknown chat command "/cdbg ' .. msg .. '"')
end

function x:GetCooldownMinimum()
    return self.db.profile.cooldownMinimum
end


function x:SetCooldownMinimum(_, value)
    self.db.profile.cooldownMinimum = value
    self:UpdateEverything()
end


function x:GetGlowType()
    return self.db.profile.glowType
end


function x:DisableOutOfCombat()
    return self.db.profile.disableOutOfCombat
end


function x:SetDisableOutOfCombat(_, value)
    self.db.profile.disableOutOfCombat = value
    if self:DisableOutOfCombat() and not self.inCombat then
        self:HideAllActiveGlows(true)
    end
end


function x:SetGlowType(_, value)
    self:HideAllActiveGlows(false)

    self.db.profile.glowType = value

    for _, button in pairs(self.activeGlows) do
        self:ShowGlow(button)
    end
end


function x:IsSpellIdExcluded(_, spellId)
    if not self.db.profile.excludedSpellIds[self.playerClass] or not self.db.profile.excludedSpellIds[self.playerClass][self.playerSpecId] then
        return false
    end

    return self.db.profile.excludedSpellIds[self.playerClass][self.playerSpecId][tostring(spellId)]
end


function x:SetSpellIdExcluded(_, spellId, isExcluded)
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

    self:UpdateEverything()
end
