local addon = EasyMail
local module = {}

module.isUiReady = false
module.menuButton = nil
module.menuFrame = nil
module.pendingRecipient = nil
module.sendButtonHooked = false
module.moneyFieldsHooked = false
module.lastAutoSubject = nil

local events = CreateFrame("Frame")
local getCurrentRecipient
local getTargetRecipient

local function getMassSendModule()
    return addon.modules and addon.modules.MassSend or nil
end
local function getQuickAttachModule()
    return addon.modules and addon.modules.QuickAttach or nil
end
local NOTE_PRESETS = {
    "Bank Alt",
    "Auction Alt",
    "Guild Crafter",
    "Main Alt",
    "Mats",
    "Consumables",
}

local PROFESSION_NOTE_PRESETS = {
    "Alchemy",
    "Blacksmithing",
    "Enchanting",
    "Engineering",
    "Herbalism",
    "Inscription",
    "Jewelcrafting",
    "Leatherworking",
    "Mining",
    "Skinning",
    "Tailoring",
}
local function getRecipientEditBox()
    return SendMailNameEditBox
end

local function getSubjectEditBox()
    return SendMailSubjectEditBox
end

local function getOutgoingMoneyAmount()
    local gold = tonumber(SendMailMoneyGold and SendMailMoneyGold:GetText() or "") or 0
    local silver = tonumber(SendMailMoneySilver and SendMailMoneySilver:GetText() or "") or 0
    local copper = tonumber(SendMailMoneyCopper and SendMailMoneyCopper:GetText() or "") or 0
    return (gold * 10000) + (silver * 100) + copper
end

local function formatWireMoney(amount)
    amount = tonumber(amount) or 0
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    local copper = amount % 100
    local parts = {}

    if gold > 0 then
        table.insert(parts, gold .. "g")
    end
    if silver > 0 then
        table.insert(parts, silver .. "s")
    end
    if copper > 0 or #parts == 0 then
        table.insert(parts, copper .. "c")
    end

    return table.concat(parts, " ")
end

getCurrentRecipient = function()
    local editBox = getRecipientEditBox()
    if not editBox then
        return nil
    end

    return addon:NormalizeRecipient(editBox:GetText())
end

getTargetRecipient = function()
    if UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
        local name, realm = UnitName("target")
        if realm and realm ~= "" then
            return addon:NormalizeRecipient(name .. "-" .. realm)
        end
        return addon:NormalizeRecipient(name)
    end

    return nil
end

local function appendRecipientNote(label, recipientName)
    local note = addon:GetRecipientNote(recipientName)
    if note and note ~= "" then
        return label .. " - " .. note
    end
    return label
end

local function buildCharacterLabel(info)
    local label = info.fullName or info.name
    if info.level and info.level > 0 then
        label = label .. " (" .. info.level .. ")"
    end
    return appendRecipientNote(label, info.fullName or info.name)
end

local function buildPersonLabel(info)
    local label = info.name
    if info.level and info.level > 0 then
        label = label .. " (" .. info.level .. ")"
    end
    return appendRecipientNote(label, info.name)
end

local function countConnected(entries)
    local count = 0
    for _, entry in ipairs(entries) do
        if entry.connected then
            count = count + 1
        end
    end
    return count
end

local function sortRecipientsForMenu(entries)
    local copy = {}
    for _, entry in ipairs(entries or {}) do
        table.insert(copy, entry)
    end

    table.sort(copy, function(left, right)
        if (left.connected and true or false) ~= (right.connected and true or false) then
            return left.connected and not right.connected
        end
        return (left.name or "") < (right.name or "")
    end)

    return copy
end

local function buildFriendLabel(info)
    local status = info.connected and "[On]" or "[Off]"
    local pinned = addon:IsFavoriteRecipient(info.name) and "[Pin] " or ""
    local label = pinned .. status .. " " .. buildPersonLabel(info)
    if info.area and info.area ~= "" and info.connected then
        label = label .. " - " .. info.area
    end
    return label
end

local function buildGuildLabel(info)
    local status = info.connected and "[On]" or "[Off]"
    local pinned = addon:IsFavoriteRecipient(info.name) and "[Pin] " or ""
    local label = pinned .. status .. " " .. buildPersonLabel(info)
    if info.area and info.area ~= "" and info.connected then
        label = label .. " - " .. info.area
    end
    return label
end

local function appendSection(menu, title, entries, emptyText, formatter, onSelect, limit)
    table.insert(menu, {
        text = title,
        isTitle = true,
    })

    if #entries == 0 then
        table.insert(menu, {
            text = emptyText,
            disabled = true,
        })
        return
    end

    local maxEntries = math.min(#entries, limit or #entries)
    for index = 1, maxEntries do
        local entry = entries[index]
        table.insert(menu, {
            text = formatter(entry),
            func = function()
                onSelect(entry)
            end,
        })
    end
end

function module:GetSettings()
    return addon:GetSendToolsSettings()
end

function module:SetRecipient(name)
    local editBox = getRecipientEditBox()
    if not editBox or not name then
        return
    end

    editBox:SetText(name)
    editBox:SetFocus()
    editBox:HighlightText(0, 0)
end

function module:ToggleSetting(key)
    local settings = self:GetSettings()
    settings[key] = not settings[key]
end

function module:UpdateWireSubject()
    local settings = self:GetSettings()
    if settings.autoWireSubject == false then
        self.lastAutoSubject = nil
        return
    end

    local subjectEditBox = getSubjectEditBox()
    if not subjectEditBox then
        return
    end

    local amount = getOutgoingMoneyAmount()
    local subject = strtrim(subjectEditBox:GetText() or "")

    if amount <= 0 then
        if self.lastAutoSubject and subject == self.lastAutoSubject then
            subjectEditBox:SetText("")
        end
        self.lastAutoSubject = nil
        return
    end

    local autoSubject = formatWireMoney(amount)
    if subject == "" or (self.lastAutoSubject and subject == self.lastAutoSubject) then
        subjectEditBox:SetText(autoSubject)
        self.lastAutoSubject = autoSubject
    end
end

function module:RememberPendingRecipient()
    local editBox = getRecipientEditBox()
    if not editBox then
        return
    end

    self.pendingRecipient = addon:NormalizeRecipient(editBox:GetText())
end

function module:CommitPendingRecipient()
    if self.pendingRecipient then
        addon:AddRecentRecipient(self.pendingRecipient)
        addon:SetLastMailedRecipient(self.pendingRecipient)
        self.pendingRecipient = nil
    end
end

function module:BuildMenu()
    local currentRecipient = getCurrentRecipient()
    local defaultRecipient = addon:GetDefaultRecipient()
    local currentNote = currentRecipient and addon:GetRecipientNote(currentRecipient) or nil
    local massSend = getMassSendModule()
    local queuedCount = massSend and massSend:GetQueueCount() or 0
    local menu = {
        {
            text = "EasyMail",
            isTitle = true,
        },
    }

    local settings = self:GetSettings()

    if defaultRecipient then
        table.insert(menu, {
            text = "Use Default: " .. appendRecipientNote(defaultRecipient, defaultRecipient),
            func = function()
                module:SetRecipient(defaultRecipient)
            end,
        })
    end

    if currentRecipient then
        table.insert(menu, {
            text = (addon:IsFavoriteRecipient(currentRecipient) and "Unpin" or "Pin") .. ": " .. currentRecipient,
            func = function()
                local isPinned = addon:ToggleFavoriteRecipient(currentRecipient)
                addon:Print((isPinned and "Pinned " or "Unpinned ") .. currentRecipient .. ".")
                addon:PopulateContextMenu(module.menuFrame, module.menuButton, module:BuildMenu())
            end,
        })

        table.insert(menu, {
            text = (defaultRecipient == currentRecipient and "Clear Default Recipient" or "Set as Default Recipient"),
            func = function()
                if defaultRecipient == currentRecipient then
                    addon:ClearDefaultRecipient()
                    addon:Print("Default recipient cleared.")
                else
                    addon:SetDefaultRecipient(currentRecipient)
                    addon:Print("Default recipient set to " .. currentRecipient .. ".")
                end
                addon:PopulateContextMenu(module.menuFrame, module.menuButton, module:BuildMenu())
            end,
        })

        if settings.showRecipientNotes ~= false then
            table.insert(menu, {
                text = "Recipient Note: " .. (currentNote or "None"),
                isTitle = true,
            })

            for _, note in ipairs(NOTE_PRESETS) do
                table.insert(menu, {
                    text = ((currentNote == note) and "[x] " or "[ ] ") .. note,
                    keepShownOnClick = true,
                    func = function()
                        if currentNote == note then
                            addon:SetRecipientNote(currentRecipient, nil)
                            addon:Print("Removed note from " .. currentRecipient .. ".")
                        else
                            addon:SetRecipientNote(currentRecipient, note)
                            addon:Print("Set note for " .. currentRecipient .. ": " .. note .. ".")
                        end
                        addon:PopulateContextMenu(module.menuFrame, module.menuButton, module:BuildMenu())
                    end,
                })
            end
        end

        if settings.showProfessionNotes ~= false then
            table.insert(menu, {
                text = "Profession Notes",
                isTitle = true,
            })

            for _, profession in ipairs(PROFESSION_NOTE_PRESETS) do
                table.insert(menu, {
                    text = ((currentNote == profession) and "[x] " or "[ ] ") .. profession,
                    keepShownOnClick = true,
                    func = function()
                        if currentNote == profession then
                            addon:SetRecipientNote(currentRecipient, nil)
                            addon:Print("Removed note from " .. currentRecipient .. ".")
                        else
                            addon:SetRecipientNote(currentRecipient, profession)
                            addon:Print("Set note for " .. currentRecipient .. ": " .. profession .. ".")
                        end
                        addon:PopulateContextMenu(module.menuFrame, module.menuButton, module:BuildMenu())
                    end,
                })
            end
        end

        table.insert(menu, {
            text = "Clear Recipient Note",
            disabled = not currentNote,
            func = function()
                addon:SetRecipientNote(currentRecipient, nil)
                addon:Print("Removed note from " .. currentRecipient .. ".")
                addon:PopulateContextMenu(module.menuFrame, module.menuButton, module:BuildMenu())
            end,
        })
    end

    local favorites = addon:GetFavoriteRecipients()
    if #favorites > 0 then
        appendSection(
            menu,
            "Pinned Recipients",
            favorites,
            "No pinned recipients yet",
            function(entry)
                return appendRecipientNote("[Pin] " .. entry.name, entry.name)
            end,
            function(entry)
                module:SetRecipient(entry.name)
            end,
            12
        )
    end

    if settings.showTarget then
        local targetRecipient = getTargetRecipient()
        if targetRecipient then
            table.insert(menu, {
                text = "Use Target: " .. appendRecipientNote(targetRecipient, targetRecipient),
                func = function()
                    module:SetRecipient(targetRecipient)
                end,
            })
        end
    end

    if settings.showLastMailed then
        local lastRecipient = addon:GetLastMailedRecipient()
        if lastRecipient then
            table.insert(menu, {
                text = "Last Mailed: " .. appendRecipientNote(lastRecipient, lastRecipient),
                func = function()
                    module:SetRecipient(lastRecipient)
                end,
            })
        end
    end

    if settings.showAlts then
        appendSection(
            menu,
            "Alternate Characters",
            addon:GetAlternateCharacters(),
            "No alts recorded yet",
            buildCharacterLabel,
            function(entry)
                module:SetRecipient(entry.fullName)
            end,
            12
        )
    end

    if settings.showRecents then
        appendSection(
            menu,
            "Recent Recipients",
            addon:GetRecentRecipients({ excludeAlts = true }),
            "No recent mail targets yet",
            function(entry)
                return appendRecipientNote(entry.name, entry.name)
            end,
            function(entry)
                module:SetRecipient(entry.name)
            end,
            12
        )
    end

    if settings.showFriends then
        local friends = sortRecipientsForMenu(addon:GetFriendRecipients())
        appendSection(
            menu,
            "Friends (" .. countConnected(friends) .. "/" .. #friends .. " online)",
            friends,
            "No friends found",
            buildFriendLabel,
            function(entry)
                module:SetRecipient(entry.name)
            end,
            12
        )
    end

    if settings.showGuild then
        local guild = sortRecipientsForMenu(addon:GetGuildRecipients())
        appendSection(
            menu,
            "Guild (" .. countConnected(guild) .. "/" .. #guild .. " online)",
            guild,
            "No guild members found",
            buildGuildLabel,
            function(entry)
                module:SetRecipient(entry.name)
            end,
            12
        )
    end

    if settings.showQuickAttach ~= false then
        local quickAttach = getQuickAttachModule()
        table.insert(menu, {
            text = "Quick Attach",
            isTitle = true,
        })

        for _, definition in ipairs(quickAttach and quickAttach:GetDefinitions() or {}) do
            local matchCount = quickAttach:GetMatchCount(definition)
            table.insert(menu, {
                text = definition.text .. " (" .. matchCount .. ")",
                disabled = matchCount == 0,
                func = function()
                    local attached, matched = quickAttach:AttachByDefinition(definition)
                    if attached > 0 then
                        addon:Print("Quick Attach: attached " .. attached .. " stack" .. (attached == 1 and "" or "s") .. " from " .. definition.text .. ".")
                    elseif matched > 0 then
                        addon:Print("Quick Attach: no free attachment slots left.")
                    else
                        addon:Print("Quick Attach: no matching items found for " .. definition.text .. ".")
                    end
                end,
            })
        end
    end

    table.insert(menu, {
        text = "Mass Send Queue: " .. queuedCount,
        isTitle = true,
    })
    table.insert(menu, {
        text = "View Queue",
        disabled = not massSend,
        func = function()
            if massSend then
                massSend:ToggleQueueViewer()
            end
        end,
    })
    table.insert(menu, {
        text = "Start Mass Send",
        disabled = queuedCount == 0 or not currentRecipient,
        func = function()
            if massSend then
                massSend:StartFromQueue()
            end
        end,
    })
    table.insert(menu, {
        text = "Clear Mass Queue",
        disabled = queuedCount == 0,
        func = function()
            if massSend then
                massSend:ClearQueue()
                addon:PopulateContextMenu(module.menuFrame, module.menuButton, module:BuildMenu())
            end
        end,
    })

    table.insert(menu, {
        text = "Source Settings",
        isTitle = true,
    })

    local toggles = {
        { key = "showTarget", text = "Show Target" },
        { key = "showLastMailed", text = "Show Last Mailed" },
        { key = "showAlts", text = "Show Alts" },
        { key = "showRecents", text = "Show Recents" },
        { key = "showFriends", text = "Show Friends" },
        { key = "showGuild", text = "Show Guild" },
        { key = "showQuickAttach", text = "Show Quick Attach" },
        { key = "showRecipientNotes", text = "Show Recipient Notes" },
        { key = "showProfessionNotes", text = "Show Profession Notes" },
        { key = "autoWireSubject", text = "Auto Wire Subject" },
    }

    for _, toggle in ipairs(toggles) do
        table.insert(menu, {
            text = toggle.text,
            checked = settings[toggle.key],
            keepShownOnClick = true,
            func = function()
                module:ToggleSetting(toggle.key)
                module:UpdateWireSubject()
                addon:PopulateContextMenu(module.menuFrame, module.menuButton, module:BuildMenu())
            end,
        })
    end

    return menu
end

function module:EnsureMenu()
    if self.menuFrame then
        return
    end

    self.menuFrame = addon:CreateContextMenu("EasyMailSendToolsMenu")
end

function module:ShowMenu()
    self:EnsureMenu()
    addon:ToggleContextMenu(self.menuFrame, self.menuButton, self:BuildMenu())
end

function module:EnsureUi()
    if not SendMailFrame or not SendMailNameEditBox or not SendMailSubjectEditBox then
        return
    end

    if not self.isUiReady then
        local button = addon:CreateButton(SendMailFrame, "EM", 26, 20, "LEFT", SendMailSubjectEditBox, "RIGHT", 4, 0)
        button:SetScript("OnClick", function()
            module:ShowMenu()
        end)
        button:SetScript("OnEnter", function(selfButton)
            GameTooltip:SetOwner(selfButton, "ANCHOR_TOP")
            GameTooltip:AddLine("EasyMail")
            GameTooltip:AddLine("Quick fill with alts, last mailed, friends, guild, or recent recipients.", 1, 1, 1, true)
            GameTooltip:AddLine("Alt-click a bag item to attach it instantly.", 1, 1, 1, true)
            GameTooltip:AddLine("If the current mail is full, extra Alt-clicked or right-clicked items go into the Mass Send queue.", 1, 1, 1, true)
            GameTooltip:AddLine("Gold mails can auto-fill the subject when blank.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        self.menuButton = button
        self.isUiReady = true
    end

    if SendMailMailButton and not self.sendButtonHooked then
        SendMailMailButton:HookScript("OnClick", function()
            module:RememberPendingRecipient()
            local massSend = getMassSendModule()
            if massSend then
                massSend:ArmFromCurrentMail()
            end
        end)
        self.sendButtonHooked = true
    end

    if not self.moneyFieldsHooked then
        local fields = { SendMailMoneyGold, SendMailMoneySilver, SendMailMoneyCopper }
        for _, field in ipairs(fields) do
            if field then
                field:HookScript("OnTextChanged", function()
                    module:UpdateWireSubject()
                end)
            end
        end
        self.moneyFieldsHooked = true
    end

    local quickAttach = getQuickAttachModule()
    if quickAttach then
        quickAttach:EnsureBagHook()
    end

    module:UpdateWireSubject()
end

function module:OnInitialize()
    self:EnsureMenu()

    events:RegisterEvent("MAIL_SHOW")
    events:RegisterEvent("MAIL_SEND_SUCCESS")
    events:RegisterEvent("MAIL_FAILED")
    events:RegisterEvent("MAIL_CLOSED")
    events:RegisterEvent("FRIENDLIST_UPDATE")
    events:RegisterEvent("GUILD_ROSTER_UPDATE")
    events:SetScript("OnEvent", function(_, event)
        if event == "MAIL_SHOW" then
            addon:RegisterCurrentCharacter()
            module:EnsureUi()
        elseif event == "MAIL_SEND_SUCCESS" then
            module:CommitPendingRecipient()
            module.lastAutoSubject = nil
            local massSend = getMassSendModule()
            if massSend and massSend:IsActive() then
                C_Timer.After(0.2, function()
                    massSend:ContinueAfterSuccess()
                end)
            end
        elseif event == "MAIL_FAILED" then
            module.pendingRecipient = nil
            local massSend = getMassSendModule()
            if massSend then
                massSend:HandleSendFailed()
            end
        elseif event == "MAIL_CLOSED" then
            local massSend = getMassSendModule()
            if massSend then
                massSend:HandleMailClosed()
            end
        end
    end)
end

addon:RegisterModule("SendTools", module)

















