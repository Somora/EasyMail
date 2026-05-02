EasyMail = EasyMail or {}

local addon = EasyMail

addon.name = "EasyMail"
addon.version = "1.0.6"
addon.modules = {}
addon.defaults = {
    debug = false,
    recentRecipients = {},
    maxRecentRecipients = 30,
    characters = {},
    lastMailedRecipient = nil,
    sendTools = {
        showTarget = true,
        showLastMailed = true,
        showAlts = true,
        showRecents = true,
        showFriends = true,
        showGuild = true,
        showQuickAttach = true,
        showRecipientNotes = true,
        showProfessionNotes = true,
        autoWireSubject = true,
        defaultRecipient = nil,
        favoriteRecipients = {},
        recipientNotes = {},
        queueViewerPosition = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
        },
    },
    openAll = {
        takeMoney = true,
        takeItems = true,
        allowCOD = false,
        skipGM = true,
        stopOnBagsFull = true,
        leaveFreeSlots = 0,
        mailTypes = {
            nonAH = true,
            ahSold = true,
            ahCancelled = true,
            ahWon = true,
            ahOther = true,
        },
    },
}

local frame = CreateFrame("Frame")
addon.frame = frame
addon.activeMenu = nil
addon.menuCloseIgnoreUntil = 0

local function isFrameOrChild(frameToCheck, candidate)
    if not frameToCheck or not candidate then
        return false
    end

    local current = candidate
    while current do
        if current == frameToCheck then
            return true
        end
        current = current.GetParent and current:GetParent() or nil
    end

    return false
end

local function isCursorOverFrame(frameToCheck)
    if not frameToCheck or not frameToCheck.IsShown or not frameToCheck:IsShown() then
        return false
    end

    local left = frameToCheck.GetLeft and frameToCheck:GetLeft() or nil
    local right = frameToCheck.GetRight and frameToCheck:GetRight() or nil
    local top = frameToCheck.GetTop and frameToCheck:GetTop() or nil
    local bottom = frameToCheck.GetBottom and frameToCheck:GetBottom() or nil
    if not left or not right or not top or not bottom then
        return false
    end

    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    return cursorX >= left and cursorX <= right and cursorY >= bottom and cursorY <= top
end

local function copyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = target[key] or {}
            copyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function trimRealmName(realmName)
    if not realmName then
        return nil
    end

    return realmName:gsub("%s+", "")
end

local function serializeValue(value)
    local valueType = type(value)
    if valueType == "string" then
        return string.format("%q", value)
    end
    if valueType == "number" or valueType == "boolean" then
        return tostring(value)
    end
    if valueType ~= "table" then
        return "nil"
    end

    local keys = {}
    for key in pairs(value) do
        table.insert(keys, key)
    end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)

    local parts = {}
    for _, key in ipairs(keys) do
        local keyText
        if type(key) == "string" and key:match("^[%a_][%w_]*$") then
            keyText = key
        else
            keyText = "[" .. serializeValue(key) .. "]"
        end
        table.insert(parts, keyText .. "=" .. serializeValue(value[key]))
    end

    return "{" .. table.concat(parts, ",") .. "}"
end

local function resetTable(target, defaults)
    for key in pairs(target) do
        target[key] = nil
    end
    copyDefaults(target, defaults)
end

function addon:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99EasyMail|r: " .. tostring(message))
end

function addon:IsDebugEnabled()
    return EasyMailDB and EasyMailDB.debug
end

function addon:Debug(message)
    if self:IsDebugEnabled() then
        self:Print(message)
    end
end

function addon:RegisterModule(name, module)
    self.modules[name] = module
end

function addon:GetOpenAllSettings()
    EasyMailDB.openAll = EasyMailDB.openAll or {}
    copyDefaults(EasyMailDB.openAll, self.defaults.openAll)
    return EasyMailDB.openAll
end

function addon:GetSendToolsSettings()
    EasyMailDB.sendTools = EasyMailDB.sendTools or {}
    copyDefaults(EasyMailDB.sendTools, self.defaults.sendTools)
    return EasyMailDB.sendTools
end

function addon:NormalizeRecipient(name)
    if not name then
        return nil
    end

    name = strtrim(name)
    if name == "" then
        return nil
    end

    local playerName, realmName = strsplit("-", name, 2)
    if not playerName or playerName == "" then
        return nil
    end

    playerName = playerName:sub(1, 1):upper() .. playerName:sub(2):lower()

    if realmName and realmName ~= "" then
        realmName = trimRealmName(realmName)
        return playerName .. "-" .. realmName
    end

    return playerName
end

function addon:GetPlayerFullName()
    local playerName = UnitName("player")
    local realmName = trimRealmName(GetRealmName())
    return self:NormalizeRecipient(playerName .. "-" .. realmName)
end

function addon:GetCurrentRealmName()
    return trimRealmName(GetRealmName())
end

function addon:RegisterCurrentCharacter()
    EasyMailDB.characters = EasyMailDB.characters or {}

    local fullName = self:GetPlayerFullName()
    if not fullName then
        return
    end

    local _, classTag = UnitClass("player")
    local faction = UnitFactionGroup("player")

    EasyMailDB.characters[fullName] = {
        name = UnitName("player"),
        realm = trimRealmName(GetRealmName()),
        fullName = fullName,
        classTag = classTag,
        faction = faction,
        level = UnitLevel("player"),
        updatedAt = time(),
    }
end

function addon:GetAlternateCharacters()
    local current = self:GetPlayerFullName()
    local faction = UnitFactionGroup("player")
    local characters = {}

    for _, info in pairs(EasyMailDB and EasyMailDB.characters or {}) do
        if info.fullName and info.fullName ~= current and info.faction == faction then
            table.insert(characters, info)
        end
    end

    table.sort(characters, function(left, right)
        if left.realm == right.realm then
            return left.name < right.name
        end

        return left.realm < right.realm
    end)

    return characters
end

function addon:SetLastMailedRecipient(name)
    local normalized = self:NormalizeRecipient(name)
    EasyMailDB.lastMailedRecipient = normalized
end

function addon:GetLastMailedRecipient()
    return self:NormalizeRecipient(EasyMailDB and EasyMailDB.lastMailedRecipient)
end

function addon:GetFavoriteRecipients()
    local settings = self:GetSendToolsSettings()
    local results = {}
    local current = self:GetPlayerFullName()
    local seen = {}

    for _, name in ipairs(settings.favoriteRecipients or {}) do
        local normalized = self:NormalizeRecipient(name)
        if normalized and normalized ~= current and not seen[normalized] then
            table.insert(results, {
                name = normalized,
            })
            seen[normalized] = true
        end
    end

    table.sort(results, function(left, right)
        return left.name < right.name
    end)

    return results
end

function addon:IsFavoriteRecipient(name)
    local normalized = self:NormalizeRecipient(name)
    if not normalized then
        return false
    end

    local settings = self:GetSendToolsSettings()
    for _, entry in ipairs(settings.favoriteRecipients or {}) do
        if self:NormalizeRecipient(entry) == normalized then
            return true
        end
    end

    return false
end

function addon:ToggleFavoriteRecipient(name)
    local normalized = self:NormalizeRecipient(name)
    if not normalized then
        return false
    end

    local settings = self:GetSendToolsSettings()
    settings.favoriteRecipients = settings.favoriteRecipients or {}

    for index, entry in ipairs(settings.favoriteRecipients) do
        if self:NormalizeRecipient(entry) == normalized then
            table.remove(settings.favoriteRecipients, index)
            return false
        end
    end

    table.insert(settings.favoriteRecipients, normalized)
    table.sort(settings.favoriteRecipients)
    return true
end

function addon:GetDefaultRecipient()
    local settings = self:GetSendToolsSettings()
    return self:NormalizeRecipient(settings.defaultRecipient)
end

function addon:SetDefaultRecipient(name)
    local settings = self:GetSendToolsSettings()
    settings.defaultRecipient = self:NormalizeRecipient(name)
end

function addon:ClearDefaultRecipient()
    local settings = self:GetSendToolsSettings()
    settings.defaultRecipient = nil
end

function addon:GetRecipientNote(name)
    local normalized = self:NormalizeRecipient(name)
    if not normalized then
        return nil
    end

    local settings = self:GetSendToolsSettings()
    local notes = settings.recipientNotes or {}
    return notes[normalized]
end

function addon:SetRecipientNote(name, note)
    local normalized = self:NormalizeRecipient(name)
    if not normalized then
        return
    end

    local settings = self:GetSendToolsSettings()
    settings.recipientNotes = settings.recipientNotes or {}

    if note and strtrim(note) ~= "" then
        settings.recipientNotes[normalized] = strtrim(note)
    else
        settings.recipientNotes[normalized] = nil
    end
end

function addon:AddRecentRecipient(name)
    local normalized = self:NormalizeRecipient(name)
    if not normalized then
        return
    end

    EasyMailDB.recentRecipients = EasyMailDB.recentRecipients or {}

    for index = #EasyMailDB.recentRecipients, 1, -1 do
        local entry = EasyMailDB.recentRecipients[index]
        local entryName = type(entry) == "table" and entry.name or entry
        if entryName == normalized then
            table.remove(EasyMailDB.recentRecipients, index)
        end
    end

    table.insert(EasyMailDB.recentRecipients, 1, {
        name = normalized,
        lastUsed = time(),
        realm = select(2, strsplit("-", normalized, 2)),
        isAlt = EasyMailDB.characters and EasyMailDB.characters[normalized] ~= nil,
    })

    self:SetLastMailedRecipient(normalized)

    local maxEntries = EasyMailDB.maxRecentRecipients or self.defaults.maxRecentRecipients or 30
    while #EasyMailDB.recentRecipients > maxEntries do
        table.remove(EasyMailDB.recentRecipients)
    end
end

function addon:GetRecentRecipients(options)
    local results = {}
    local current = self:GetPlayerFullName()
    local seen = {}
    options = options or {}

    for _, entry in ipairs(EasyMailDB and EasyMailDB.recentRecipients or {}) do
        local info = type(entry) == "table" and entry or { name = entry, lastUsed = 0 }
        if info.name and info.name ~= current and not seen[info.name] then
            if not options.excludeAlts or not (EasyMailDB.characters and EasyMailDB.characters[info.name]) then
                table.insert(results, info)
                seen[info.name] = true
            end
        end
    end

    return results
end

function addon:GetFriendRecipients()
    local results = {}
    local seen = {}
    local current = self:GetPlayerFullName()

    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        local count = C_FriendList.GetNumFriends() or 0
        for index = 1, count do
            local info = C_FriendList.GetFriendInfoByIndex(index)
            local name = info and info.name and self:NormalizeRecipient(info.name)
            if name and name ~= current and not seen[name] then
                table.insert(results, {
                    name = name,
                    level = info.level,
                    className = info.className,
                    area = info.area,
                    connected = info.connected,
                })
                seen[name] = true
            end
        end
    elseif GetNumFriends and GetFriendInfo then
        local count = GetNumFriends() or 0
        for index = 1, count do
            local name, level, className, area, connected = GetFriendInfo(index)
            name = self:NormalizeRecipient(name)
            if name and name ~= current and not seen[name] then
                table.insert(results, {
                    name = name,
                    level = level,
                    className = className,
                    area = area,
                    connected = connected,
                })
                seen[name] = true
            end
        end
    end

    table.sort(results, function(left, right)
        return left.name < right.name
    end)

    return results
end

function addon:GetGuildRecipients()
    local results = {}
    local seen = {}
    local current = self:GetPlayerFullName()

    if not IsInGuild or not IsInGuild() then
        return results
    end

    if GuildRoster then
        GuildRoster()
    end

    local count = GetNumGuildMembers and GetNumGuildMembers() or 0
    for index = 1, count do
        local fullName, _, _, level, _, zone, publicNote, officerNote, isOnline, status, className = GetGuildRosterInfo(index)
        local normalized = self:NormalizeRecipient(fullName)
        if normalized and normalized ~= current and not seen[normalized] then
            table.insert(results, {
                name = normalized,
                level = level,
                className = className,
                area = zone,
                publicNote = publicNote,
                officerNote = officerNote,
                connected = isOnline,
                status = status,
            })
            seen[normalized] = true
        end
    end

    table.sort(results, function(left, right)
        return left.name < right.name
    end)

    return results
end

function addon:CreateButton(parent, label, width, height, anchorPoint, relativeTo, relativePoint, offsetX, offsetY)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 96, height or 22)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    button:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
    button:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
    button:SetPoint(anchorPoint, relativeTo, relativePoint, offsetX or 0, offsetY or 0)

    button.text = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.text:SetJustifyH("CENTER")
    button.text:SetText(label or "")

    button:SetScript("OnEnable", function(selfButton)
        selfButton:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
        selfButton.text:SetFontObject(GameFontNormal)
    end)
    button:SetScript("OnDisable", function(selfButton)
        selfButton:SetBackdropColor(0.12, 0.12, 0.12, 0.75)
        selfButton.text:SetFontObject(GameFontDisable)
    end)
    button:SetScript("OnMouseDown", function(selfButton)
        if selfButton:IsEnabled() then
            selfButton.text:SetPoint("CENTER", selfButton, "CENTER", 1, -1)
        end
    end)
    button:SetScript("OnMouseUp", function(selfButton)
        selfButton.text:SetPoint("CENTER", selfButton, "CENTER", 0, 0)
    end)
    button:SetScript("OnEnter", function(selfButton)
        if selfButton:IsEnabled() then
            selfButton:SetBackdropBorderColor(0.9, 0.75, 0.2, 1)
            selfButton.text:SetFontObject(GameFontHighlight)
        end
    end)
    button:SetScript("OnLeave", function(selfButton)
        selfButton:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
        selfButton.text:SetFontObject(selfButton:IsEnabled() and GameFontNormal or GameFontDisable)
        selfButton.text:SetPoint("CENTER", selfButton, "CENTER", 0, 0)
    end)

    button.SetText = function(selfButton, text)
        selfButton.text:SetText(text or "")
    end

    button.GetText = function(selfButton)
        return selfButton.text:GetText()
    end

    button:SetText(label or "")
    return button
end

function addon:HideContextMenu()
    if self.activeMenu then
        self.activeMenu:Hide()
        self.activeMenu = nil
    end
end

function addon:CreateContextMenu(name)
    local menu = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    menu:SetBackdropColor(0.05, 0.05, 0.05, 0.98)
    menu:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    menu.buttons = {}
    menu:Hide()

    menu:SetScript("OnHide", function(selfMenu)
        if addon.activeMenu == selfMenu then
            addon.activeMenu = nil
        end
    end)

    return menu
end

function addon:PopulateContextMenu(menu, anchor, items)
    self:HideContextMenu()

    local width = 240
    local visibleIndex = 0

    for _, button in ipairs(menu.buttons) do
        button:Hide()
    end

    for _, item in ipairs(items) do
        visibleIndex = visibleIndex + 1
        local button = menu.buttons[visibleIndex]
        if not button then
            button = CreateFrame("Button", nil, menu)
            button:SetHeight(20)
            button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            button.text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            button.text:SetPoint("LEFT", button, "LEFT", 8, 0)
            button.text:SetJustifyH("LEFT")
            button.text:SetWidth(width - 16)
            menu.buttons[visibleIndex] = button
        end

        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -6 - ((visibleIndex - 1) * 20))
        button:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -6, -6 - ((visibleIndex - 1) * 20))
        button.item = item

        local prefix = ""
        if item.isTitle then
            button.text:SetFontObject(GameFontNormalSmall)
        elseif item.checked ~= nil then
            button.text:SetFontObject(GameFontHighlightSmall)
            prefix = item.checked and "[x] " or "[ ] "
        else
            button.text:SetFontObject(GameFontHighlightSmall)
        end

        button.text:SetText(prefix .. (item.text or ""))

        if item.disabled then
            button.text:SetTextColor(0.5, 0.5, 0.5)
        elseif item.isTitle then
            button.text:SetTextColor(1, 0.82, 0)
        else
            button.text:SetTextColor(1, 1, 1)
        end

        button:SetEnabled(not item.disabled and not item.isTitle)
        button:SetScript("OnClick", function(selfButton)
            if selfButton.item and selfButton.item.func and not selfButton.item.disabled and not selfButton.item.isTitle then
                selfButton.item.func()
            end
            if not (selfButton.item and selfButton.item.keepShownOnClick) then
                addon:HideContextMenu()
            end
        end)
        button:Show()
    end

    local height = (visibleIndex * 20) + 12
    menu:SetSize(width, math.max(height, 24))
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    menu.anchor = anchor
    menu:Show()
    self.activeMenu = menu
    self.menuCloseIgnoreUntil = GetTime() + 0.1
end

function addon:ToggleContextMenu(menu, anchor, items)
    if menu and menu:IsShown() then
        self:HideContextMenu()
        return false
    end

    self:PopulateContextMenu(menu, anchor, items)
    return true
end

function addon:ResetSettings()
    local sendTools = EasyMailDB.sendTools or {}
    local defaultRecipient = sendTools.defaultRecipient
    local favoriteRecipients = sendTools.favoriteRecipients
    local recipientNotes = sendTools.recipientNotes

    EasyMailDB.openAll = {}
    EasyMailDB.sendTools = {}
    copyDefaults(EasyMailDB.openAll, self.defaults.openAll)
    copyDefaults(EasyMailDB.sendTools, self.defaults.sendTools)

    EasyMailDB.sendTools.defaultRecipient = defaultRecipient
    EasyMailDB.sendTools.favoriteRecipients = favoriteRecipients or {}
    EasyMailDB.sendTools.recipientNotes = recipientNotes or {}
end

function addon:ResetRecipients()
    EasyMailDB.recentRecipients = {}
    EasyMailDB.lastMailedRecipient = nil
    EasyMailDB.characters = {}
    EasyMailDB.sendTools = EasyMailDB.sendTools or {}
    EasyMailDB.sendTools.defaultRecipient = nil
    EasyMailDB.sendTools.favoriteRecipients = {}
    EasyMailDB.sendTools.recipientNotes = {}
    copyDefaults(EasyMailDB.sendTools, self.defaults.sendTools)
    self:RegisterCurrentCharacter()
end

function addon:ResetAllData()
    resetTable(EasyMailDB, self.defaults)
    self:RegisterCurrentCharacter()
    self:GetOpenAllSettings()
    self:GetSendToolsSettings()
end

function addon:GetExportText()
    return "EasyMailDB=" .. serializeValue(EasyMailDB or {})
end

function addon:ShowCopyDialog(title, text)
    if not self.copyDialog then
        local dialog = CreateFrame("Frame", "EasyMailCopyDialog", UIParent, "BackdropTemplate")
        dialog:SetSize(560, 260)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("DIALOG")
        dialog:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        dialog:SetBackdropColor(0.05, 0.05, 0.05, 0.98)
        dialog:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        dialog:EnableMouse(true)
        dialog:SetMovable(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

        dialog.title = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        dialog.title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -14)

        local closeButton = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
        closeButton:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -4, -4)

        local editBox = CreateFrame("EditBox", nil, dialog)
        editBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -46)
        editBox:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 16)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(true)
        editBox:SetFontObject(GameFontHighlightSmall)
        editBox:SetScript("OnEscapePressed", function()
            dialog:Hide()
        end)
        dialog.editBox = editBox

        self.copyDialog = dialog
    end

    self.copyDialog.title:SetText(title or "EasyMail Export")
    self.copyDialog.editBox:SetText(text or "")
    self.copyDialog.editBox:HighlightText()
    self.copyDialog:Show()
    self.copyDialog.editBox:SetFocus()
end

function addon:Initialize()
    EasyMailDB = EasyMailDB or {}
    copyDefaults(EasyMailDB, self.defaults)
    self:RegisterCurrentCharacter()
    self:GetOpenAllSettings()
    self:GetSendToolsSettings()

    for name, module in pairs(self.modules) do
        if type(module.OnInitialize) == "function" then
            self:Debug("Initializing module: " .. name)
            module:OnInitialize()
        end
    end

    self:Print("Loaded v" .. self.version .. ". Type /em for help.")
end

local function slashCommand(message)
    local command = strlower(strtrim(message or ""))

    if command == "" or command == "help" then
        addon:Print("Commands: /em recents, /em export, /em reset settings, /em reset recipients, /em reset all, /em debug")
        return
    end

    if command == "debug" then
        EasyMailDB.debug = not EasyMailDB.debug
        addon:Print("Debug mode " .. (EasyMailDB.debug and "enabled" or "disabled") .. ".")
        return
    end

    if command == "recents" then
        local recents = addon:GetRecentRecipients({ excludeAlts = false })
        if #recents == 0 then
            addon:Print("No recent recipients recorded yet.")
            return
        end

        local names = {}
        for index = 1, math.min(#recents, 5) do
            table.insert(names, recents[index].name)
        end
        addon:Print("Recent: " .. table.concat(names, ", "))
        return
    end

    if command == "export" then
        addon:ShowCopyDialog("EasyMail Export", addon:GetExportText())
        addon:Print("Export opened. Use Ctrl+C to copy the highlighted text.")
        return
    end

    if command == "reset settings" then
        addon:ResetSettings()
        addon:Print("Settings reset. Recipient data was kept.")
        return
    end

    if command == "reset recipients" then
        addon:ResetRecipients()
        addon:Print("Recipient data reset. Settings were kept.")
        return
    end

    if command == "reset all" then
        addon:ResetAllData()
        addon:Print("All EasyMail settings and recipient data reset.")
        return
    end

    addon:Print("Unknown command. Type /em help for commands.")
end

SLASH_EASYMAIL1 = "/easymail"
SLASH_EASYMAIL2 = "/em"
SlashCmdList.EASYMAIL = slashCommand

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("GLOBAL_MOUSE_DOWN")
frame:RegisterEvent("MAIL_CLOSED")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addon.name then
        addon:Initialize()
        return
    end

    if event == "MAIL_CLOSED" then
        addon:HideContextMenu()
        return
    end

    if event == "GLOBAL_MOUSE_DOWN" and addon.activeMenu and addon.activeMenu:IsShown() then
        if GetTime() < (addon.menuCloseIgnoreUntil or 0) then
            return
        end

        local focus = GetMouseFocus and GetMouseFocus() or nil
        if isFrameOrChild(addon.activeMenu, focus) or isFrameOrChild(addon.activeMenu.anchor, focus) then
            return
        end

        if isCursorOverFrame(addon.activeMenu) or isCursorOverFrame(addon.activeMenu.anchor) then
            return
        end

        addon:HideContextMenu()
    end
end)


















