local addon = EasyMail
local module = {}

module.maxSuggestions = 8
module.isUiReady = false
module.dropdown = nil
module.buttons = {}
module.pendingRecipient = nil
module.lastMatches = {}
module.originalOnTabPressed = nil

local events = CreateFrame("Frame")

local function startsWith(text, prefix)
    return strsub(text, 1, strlen(prefix)) == prefix
end

local function getRecipientEditBox()
    return SendMailNameEditBox
end

function module:GetMatches(searchText)
    local normalized = strlower(strtrim(searchText or ""))
    local matches = {}

    if normalized == "" then
        return matches
    end

    for _, name in ipairs(addon:GetRecentRecipients()) do
        if startsWith(strlower(name), normalized) then
            table.insert(matches, name)
            if #matches >= self.maxSuggestions then
                break
            end
        end
    end

    return matches
end

function module:HideSuggestions()
    if self.dropdown then
        self.dropdown:Hide()
    end

    self.lastMatches = {}
end

function module:SelectRecipient(name)
    local editBox = getRecipientEditBox()
    if not editBox then
        return
    end

    editBox:SetText(name)
    editBox:HighlightText(0, 0)
    self:HideSuggestions()
end

function module:RefreshSuggestions()
    if not self.dropdown then
        return
    end

    local editBox = getRecipientEditBox()
    if not editBox or not editBox:HasFocus() then
        self:HideSuggestions()
        return
    end

    self.lastMatches = self:GetMatches(editBox:GetText())

    if #self.lastMatches == 0 then
        self:HideSuggestions()
        return
    end

    for index, button in ipairs(self.buttons) do
        local match = self.lastMatches[index]
        if match then
            button:SetText(match)
            button.matchValue = match
            button:Show()
        else
            button.matchValue = nil
            button:Hide()
        end
    end

    self.dropdown:SetHeight((#self.lastMatches * 20) + 10)
    self.dropdown:Show()
end

function module:HandleTabCompletion()
    if not self.lastMatches or #self.lastMatches == 0 then
        return
    end

    self:SelectRecipient(self.lastMatches[1])
end

function module:CreateSuggestionButton(parent, index)
    local button = CreateFrame("Button", nil, parent, "OptionsListButtonTemplate")
    button:SetHeight(18)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -5 - ((index - 1) * 20))
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, -5 - ((index - 1) * 20))
    button:SetText("")
    button:SetScript("OnClick", function(selfButton)
        if selfButton.matchValue then
            module:SelectRecipient(selfButton.matchValue)
        end
    end)
    button:Hide()
    return button
end

function module:RememberCurrentRecipient()
    local editBox = getRecipientEditBox()
    if not editBox then
        return
    end

    self.pendingRecipient = addon:NormalizeRecipient(editBox:GetText())
end

function module:CommitPendingRecipient()
    if self.pendingRecipient then
        addon:AddRecentRecipient(self.pendingRecipient)
        self.pendingRecipient = nil
    end
end

function module:EnsureUi()
    if self.isUiReady or not SendMailFrame or not SendMailNameEditBox then
        return
    end

    local dropdown = CreateFrame("Frame", nil, SendMailFrame, "BackdropTemplate")
    dropdown:SetPoint("TOPLEFT", SendMailNameEditBox, "BOTTOMLEFT", 0, -2)
    dropdown:SetPoint("TOPRIGHT", SendMailNameEditBox, "BOTTOMRIGHT", 0, -2)
    dropdown:SetHeight(10)
    dropdown:SetFrameStrata("DIALOG")
    dropdown:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    dropdown:SetBackdropColor(0, 0, 0, 0.95)
    dropdown:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    dropdown:Hide()

    for index = 1, self.maxSuggestions do
        self.buttons[index] = self:CreateSuggestionButton(dropdown, index)
    end

    SendMailNameEditBox:HookScript("OnTextChanged", function(_, userInput)
        if userInput then
            module:RefreshSuggestions()
        end
    end)

    SendMailNameEditBox:HookScript("OnEditFocusLost", function()
        C_Timer.After(0.05, function()
            module:HideSuggestions()
        end)
    end)

    SendMailNameEditBox:HookScript("OnEditFocusGained", function()
        module:RefreshSuggestions()
    end)

    self.originalOnTabPressed = SendMailNameEditBox:GetScript("OnTabPressed")
    SendMailNameEditBox:SetScript("OnTabPressed", function(editBox, ...)
        if #module.lastMatches > 0 then
            module:HandleTabCompletion()
            return
        end

        if module.originalOnTabPressed then
            module.originalOnTabPressed(editBox, ...)
        end
    end)

    if SendMailMailButton then
        SendMailMailButton:HookScript("OnClick", function()
            module:RememberCurrentRecipient()
        end)
    end

    self.dropdown = dropdown
    self.isUiReady = true
end

function module:OnInitialize()
    self:EnsureUi()

    events:RegisterEvent("MAIL_SHOW")
    events:RegisterEvent("MAIL_SEND_SUCCESS")
    events:RegisterEvent("MAIL_FAILED")
    events:SetScript("OnEvent", function(_, event)
        if event == "MAIL_SHOW" then
            module:EnsureUi()
        elseif event == "MAIL_SEND_SUCCESS" then
            module:CommitPendingRecipient()
            module:HideSuggestions()
        elseif event == "MAIL_FAILED" then
            module.pendingRecipient = nil
        end
    end)
end

addon:RegisterModule("SendMail", module)
