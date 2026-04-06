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
local bagHookApplied = false
local attachContainerItem
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
local QUICK_ATTACH_TYPES = {
    {
        key = "tradeGoods",
        text = "Attach Trade Goods",
        match = function(classID)
            return classID == 7
        end,
    },
    {
        key = "consumables",
        text = "Attach Consumables",
        match = function(classID)
            return classID == 0
        end,
    },
    {
        key = "gems",
        text = "Attach Gems",
        match = function(classID)
            return classID == 3
        end,
    },
    {
        key = "recipes",
        text = "Attach Recipes",
        match = function(classID)
            return classID == 9
        end,
    },
    {
        key = "stackables",
        text = "Attach Stackables",
        match = function(_, _, maxStack)
            return (maxStack or 1) > 1
        end,
    },
}

local function getContainerNumSlotsCompat(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag)
    end

    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function getContainerItemLinkCompat(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bag, slot)
    end

    return GetContainerItemLink and GetContainerItemLink(bag, slot) or nil
end

local function getContainerItemInfoCompat(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        return C_Container.GetContainerItemInfo(bag, slot)
    end

    local texture, itemCount, locked = GetContainerItemInfo and GetContainerItemInfo(bag, slot)
    if not texture then
        return nil
    end

    return {
        iconFileID = texture,
        stackCount = itemCount,
        isLocked = locked,
    }
end

local function getUsedAttachmentSlots()
    local used = 0
    local maxSlots = ATTACHMENTS_MAX_SEND or 12
    for index = 1, maxSlots do
        local itemName = GetSendMailItem and GetSendMailItem(index)
        if itemName then
            used = used + 1
        end
    end
    return used, maxSlots
end

local function getQuickAttachCount(definition)
    local count = 0
    for bag = BACKPACK_CONTAINER or 0, NUM_BAG_SLOTS or 4 do
        local numSlots = getContainerNumSlotsCompat(bag) or 0
        for slot = 1, numSlots do
            local itemInfo = getContainerItemInfoCompat(bag, slot)
            local itemLink = getContainerItemLinkCompat(bag, slot)
            if itemInfo and itemLink and not itemInfo.isLocked then
                local _, _, _, _, _, _, _, maxStack, _, _, _, classID, subclassID = GetItemInfo(itemLink)
                if definition.match(classID, subclassID, maxStack, itemLink, itemInfo.stackCount or 1) then
                    count = count + 1
                end
            end
        end
    end
    return count
end

local function quickAttachByDefinition(definition)
    if not SendMailFrame or not SendMailFrame:IsShown() then
        return 0, 0
    end

    local usedSlots, maxSlots = getUsedAttachmentSlots()
    local freeSlots = math.max(0, maxSlots - usedSlots)
    if freeSlots <= 0 then
        return 0, 0
    end

    local attached = 0
    local matched = 0

    for bag = BACKPACK_CONTAINER or 0, NUM_BAG_SLOTS or 4 do
        local numSlots = getContainerNumSlotsCompat(bag) or 0
        for slot = 1, numSlots do
            if attached >= freeSlots then
                return attached, matched
            end

            local itemInfo = getContainerItemInfoCompat(bag, slot)
            local itemLink = getContainerItemLinkCompat(bag, slot)
            if itemInfo and itemLink and not itemInfo.isLocked then
                local _, _, _, _, _, _, _, maxStack, _, _, _, classID, subclassID = GetItemInfo(itemLink)
                if definition.match(classID, subclassID, maxStack, itemLink, itemInfo.stackCount or 1) then
                    matched = matched + 1
                    if attachContainerItem(bag, slot) then
                        attached = attached + 1
                    end
                end
            end
        end
    end

    return attached, matched
end

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

local function getContainerLocation(button)
    if not button then
        return nil, nil
    end

    local bag = button.GetBagID and button:GetBagID() or button.bagID or button:GetParent() and button:GetParent().bagID
    local slot = button.GetID and button:GetID() or button.slotIndex or button.slot

    if bag == nil or slot == nil then
        return nil, nil
    end

    return bag, slot
end

attachContainerItem = function(bag, slot)
    if bag == nil or slot == nil or not SendMailFrame or not SendMailFrame:IsShown() then
        return false
    end

    if CursorHasItem() then
        return false
    end

    if C_Container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bag, slot)
    else
        PickupContainerItem(bag, slot)
    end

    if not CursorHasItem() then
        return false
    end

    ClickSendMailItemButton()
    return true
end

local function getCurrentRecipient()
    local editBox = getRecipientEditBox()
    if not editBox then
        return nil
    end

    return addon:NormalizeRecipient(editBox:GetText())
end

local function getTargetRecipient()
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
        table.insert(menu, {
            text = "Quick Attach",
            isTitle = true,
        })

        for _, definition in ipairs(QUICK_ATTACH_TYPES) do
            local matchCount = getQuickAttachCount(definition)
            table.insert(menu, {
                text = definition.text .. " (" .. matchCount .. ")",
                disabled = matchCount == 0,
                func = function()
                    local attached, matched = quickAttachByDefinition(definition)
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
    if not SendMailFrame or not SendMailNameEditBox then
        return
    end

    if not self.isUiReady then
        local button = addon:CreateButton(SendMailFrame, "EM", 26, 20, "LEFT", SendMailNameEditBox, "RIGHT", 4, 0)
        button:SetScript("OnClick", function()
            module:ShowMenu()
        end)
        button:SetScript("OnEnter", function(selfButton)
            GameTooltip:SetOwner(selfButton, "ANCHOR_TOP")
            GameTooltip:AddLine("EasyMail")
            GameTooltip:AddLine("Quick fill with alts, last mailed, friends, guild, or recent recipients.", 1, 1, 1, true)
            GameTooltip:AddLine("Alt-click a bag item to attach it instantly.", 1, 1, 1, true)
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

    if not bagHookApplied and ContainerFrameItemButton_OnModifiedClick then
        hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(selfButton, mouseButton)
            if mouseButton ~= "LeftButton" or not IsAltKeyDown() or not SendMailFrame or not SendMailFrame:IsShown() then
                return
            end

            local bag, slot = getContainerLocation(selfButton)
            attachContainerItem(bag, slot)
        end)
        bagHookApplied = true
    end

    module:UpdateWireSubject()
end

function module:OnInitialize()
    self:EnsureMenu()

    events:RegisterEvent("MAIL_SHOW")
    events:RegisterEvent("MAIL_SEND_SUCCESS")
    events:RegisterEvent("MAIL_FAILED")
    events:RegisterEvent("FRIENDLIST_UPDATE")
    events:RegisterEvent("GUILD_ROSTER_UPDATE")
    events:SetScript("OnEvent", function(_, event)
        if event == "MAIL_SHOW" then
            addon:RegisterCurrentCharacter()
            module:EnsureUi()
        elseif event == "MAIL_SEND_SUCCESS" then
            module:CommitPendingRecipient()
            module.lastAutoSubject = nil
        elseif event == "MAIL_FAILED" then
            module.pendingRecipient = nil
        end
    end)
end

addon:RegisterModule("SendTools", module)

















