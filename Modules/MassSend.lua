local addon = EasyMail
local module = {}

module.queue = {}
module.state = nil
module.viewer = nil
module.closeHooksApplied = false
module.sendAttemptToken = 0

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

local function getQueueKey(bag, slot)
    return tostring(bag) .. ":" .. tostring(slot)
end

local function getOutgoingMoneyAmount()
    local gold = tonumber(SendMailMoneyGold and SendMailMoneyGold:GetText() or "") or 0
    local silver = tonumber(SendMailMoneySilver and SendMailMoneySilver:GetText() or "") or 0
    local copper = tonumber(SendMailMoneyCopper and SendMailMoneyCopper:GetText() or "") or 0
    return (gold * 10000) + (silver * 100) + copper
end

local function getCurrentRecipient()
    return addon:NormalizeRecipient(SendMailNameEditBox and SendMailNameEditBox:GetText())
end

local function getCurrentSubject()
    return SendMailSubjectEditBox and (SendMailSubjectEditBox:GetText() or "") or ""
end

local function getCurrentBody()
    return SendMailBodyEditBox and (SendMailBodyEditBox:GetText() or "") or ""
end

local function getViewerPositionSettings()
    local settings = addon.GetSendToolsSettings and addon:GetSendToolsSettings() or nil
    settings.queueViewerPosition = settings.queueViewerPosition or {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    }
    return settings.queueViewerPosition
end

local function setComposeFields(recipient, subject, body)
    if SendMailNameEditBox then
        SendMailNameEditBox:SetText(recipient or "")
    end
    if SendMailSubjectEditBox then
        SendMailSubjectEditBox:SetText(subject or "")
    end
    if SendMailBodyEditBox then
        SendMailBodyEditBox:SetText(body or "")
    end
end

local function attachContainerItem(bag, slot)
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

function module:GetQueueCount()
    return #self.queue
end

function module:ApplyViewerPosition()
    if not self.viewer then
        return
    end

    local position = getViewerPositionSettings()
    self.viewer:ClearAllPoints()
    self.viewer:SetPoint(
        position.point or "CENTER",
        UIParent,
        position.relativePoint or position.point or "CENTER",
        tonumber(position.x) or 0,
        tonumber(position.y) or 0
    )
end

function module:SaveViewerPosition()
    if not self.viewer then
        return
    end

    local point, _, relativePoint, x, y = self.viewer:GetPoint(1)
    if not point then
        return
    end

    local position = getViewerPositionSettings()
    position.point = point
    position.relativePoint = relativePoint or point
    position.x = math.floor((x or 0) + 0.5)
    position.y = math.floor((y or 0) + 0.5)
end

function module:EnsureCloseHooks()
    if self.closeHooksApplied then
        return
    end

    local hooked = false
    local function hookFrame(frame)
        if not frame or not frame.HookScript then
            return
        end

        frame:HookScript("OnHide", function()
            module:HandleMailClosed()
        end)
        hooked = true
    end

    hookFrame(MailFrame)
    hookFrame(SendMailFrame)
    hookFrame(InboxFrame)

    if hooked then
        self.closeHooksApplied = true
    end
end

function module:EnsureQueueViewer()
    if self.viewer then
        return
    end

    local frame = CreateFrame("Frame", "EasyMailMassSendQueueViewer", UIParent, "BackdropTemplate")
    frame:SetSize(420, 300)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        module:SaveViewerPosition()
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.98)
    frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    frame.title:SetText("EasyMail Mass Send Queue")

    frame.count = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.count:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -50, -18)
    frame.count:SetText("")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -42)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 50)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(332, 1)
    scrollFrame:SetScrollChild(content)

    local clearButton = addon:CreateButton(frame, "Clear Queue", 96, 22, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -22, 16)
    clearButton:SetScript("OnClick", function()
        module:ClearQueue()
    end)

    frame.summary = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.summary:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 22)
    frame.summary:SetJustifyH("LEFT")
    frame.summary:SetText("")

    frame.scrollFrame = scrollFrame
    frame.content = content
    frame.clearButton = clearButton
    frame.rows = {}

    self.viewer = frame
    self:ApplyViewerPosition()
end

function module:RefreshQueueViewer()
    if not self.viewer then
        return
    end

    local queueCount = self:GetQueueCount()
    local rowHeight = 22
    local contentWidth = 320
    local attachmentsPerMail = ATTACHMENTS_MAX_SEND or 12
    local mailsNeeded = queueCount > 0 and math.ceil(queueCount / attachmentsPerMail) or 0

    self.viewer.count:SetText(queueCount .. " item" .. (queueCount == 1 and "" or "s"))
    if queueCount > 0 then
        self.viewer.summary:SetText(queueCount .. " queued | " .. mailsNeeded .. " mail" .. (mailsNeeded == 1 and "" or "s") .. " needed")
    else
        self.viewer.summary:SetText("Queue empty")
    end

    local visibleRows = math.max(queueCount, 1)
    self.viewer.content:SetHeight(visibleRows * rowHeight)

    for index = 1, visibleRows do
        local row = self.viewer.rows[index]
        if not row then
            row = CreateFrame("Frame", nil, self.viewer.content)
            row:SetSize(contentWidth, rowHeight)
            row:EnableMouse(true)
            row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWidth(contentWidth - 34)
            row:SetScript("OnEnter", function(selfRow)
                if not selfRow.itemLink then
                    return
                end
                GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(selfRow.itemLink)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            row.removeButton = CreateFrame("Button", nil, row, "BackdropTemplate")
            row.removeButton:SetSize(16, 16)
            row.removeButton:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            row.removeButton:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false,
                edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            row.removeButton:SetBackdropColor(0.18, 0.02, 0.02, 0.95)
            row.removeButton:SetBackdropBorderColor(0.8, 0.12, 0.12, 1)
            row.removeButton.label = row.removeButton:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            row.removeButton.label:SetPoint("CENTER", row.removeButton, "CENTER", 0, -1)
            row.removeButton.label:SetText("X")
            row.removeButton.label:SetTextColor(1, 0.35, 0.35)
            row.removeButton:SetScript("OnEnter", function(selfButton)
                GameTooltip:SetOwner(selfButton, "ANCHOR_LEFT")
                GameTooltip:AddLine("Remove from queue")
                GameTooltip:Show()
            end)
            row.removeButton:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            self.viewer.rows[index] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.viewer.content, "TOPLEFT", 4, -((index - 1) * rowHeight))

        if queueCount == 0 then
            row.itemLink = nil
            row.text:SetText("Queue is empty.")
            row.removeButton:Hide()
        else
            local entry = self.queue[index]
            local itemText = entry.itemLink or ("Bag " .. tostring(entry.bag) .. ", Slot " .. tostring(entry.slot))
            row.itemLink = entry.itemLink
            row.text:SetText(index .. ". " .. itemText)
            row.removeButton:Show()
            row.removeButton:SetScript("OnClick", function()
                table.remove(module.queue, index)
                module:RefreshQueueViewer()
            end)
        end

        row:Show()
    end

    for index = visibleRows + 1, #self.viewer.rows do
        self.viewer.rows[index]:Hide()
    end

    self.viewer.clearButton:SetEnabled(queueCount > 0)
    self.viewer.scrollFrame:SetVerticalScroll(0)
end

function module:ShowQueueViewer()
    self:EnsureCloseHooks()
    self:EnsureQueueViewer()
    self:ApplyViewerPosition()
    self:RefreshQueueViewer()
    self.viewer:Show()
end

function module:ToggleQueueViewer()
    self:EnsureQueueViewer()
    if self.viewer:IsShown() then
        self.viewer:Hide()
    else
        self:RefreshQueueViewer()
        self.viewer:Show()
    end
end

function module:IsActive()
    return self.state ~= nil
end

function module:ClearQueue(keepState)
    self.queue = {}
    if not keepState then
        self.state = nil
    end
    self:RefreshQueueViewer()
end

function module:IsItemQueued(bag, slot)
    local key = getQueueKey(bag, slot)
    for _, entry in ipairs(self.queue) do
        if entry.key == key then
            return true
        end
    end
    return false
end

function module:QueueItem(bag, slot)
    if bag == nil or slot == nil or self:IsItemQueued(bag, slot) then
        return false
    end

    local itemLink = getContainerItemLinkCompat(bag, slot)
    local itemInfo = getContainerItemInfoCompat(bag, slot)
    if not itemLink or not itemInfo or itemInfo.isLocked then
        return false
    end

    table.insert(self.queue, {
        bag = bag,
        slot = slot,
        key = getQueueKey(bag, slot),
        itemLink = itemLink,
    })
    self:RefreshQueueViewer()
    return true
end

function module:AttachQueuedItems()
    local usedSlots, maxSlots = getUsedAttachmentSlots()
    local freeSlots = math.max(0, maxSlots - usedSlots)
    local attached = 0
    local index = 1

    while freeSlots > 0 and index <= #self.queue do
        local entry = self.queue[index]
        local currentLink = getContainerItemLinkCompat(entry.bag, entry.slot)
        local itemInfo = getContainerItemInfoCompat(entry.bag, entry.slot)

        if not currentLink or not itemInfo or itemInfo.isLocked or currentLink ~= entry.itemLink then
            table.remove(self.queue, index)
            self:RefreshQueueViewer()
        elseif attachContainerItem(entry.bag, entry.slot) then
            table.remove(self.queue, index)
            attached = attached + 1
            freeSlots = freeSlots - 1
            self:RefreshQueueViewer()
        else
            index = index + 1
        end
    end

    return attached
end

function module:Finish(message)
    local sentItems = self.state and self.state.itemsSent or 0
    local sentMails = self.state and self.state.sends or 0
    local queuedLeft = self:GetQueueCount()

    self.sendAttemptToken = self.sendAttemptToken + 1
    self.state = nil

    if message then
        addon:Print(message)
        return
    end

    if sentMails > 0 or sentItems > 0 then
        addon:Print("Mass Send complete: sent " .. sentItems .. " item" .. (sentItems == 1 and "" or "s") .. " across " .. sentMails .. " mail" .. (sentMails == 1 and "" or "s") .. ".")
    elseif queuedLeft > 0 then
        addon:Print("Mass Send stopped with " .. queuedLeft .. " queued item" .. (queuedLeft == 1 and "" or "s") .. " left.")
    end
end

function module:CaptureState()
    local recipient = getCurrentRecipient()
    if not recipient then
        return nil
    end

    return {
        recipient = recipient,
        subject = getCurrentSubject(),
        body = getCurrentBody(),
        sends = 0,
        itemsSent = 0,
        awaitingResult = false,
    }
end

function module:BeginAwaitingSendResult()
    if not self.state then
        return
    end

    self.sendAttemptToken = (self.sendAttemptToken or 0) + 1
    local token = self.sendAttemptToken

    self.state.awaitingResult = true
    self.state.lastSendAttemptAt = GetTime()

    C_Timer.After(15, function()
        if not module.state or not module.state.awaitingResult or module.sendAttemptToken ~= token then
            return
        end

        module.state.awaitingResult = false
        module:Finish("Mass Send paused because the game never confirmed the last mail. This can happen with Blizzard mail throttling; click Start Mass Send again to continue.")
    end)
end

function module:PerformSend(recipient, subject, body)
    if not self.state then
        return
    end

    self:BeginAwaitingSendResult()
    SendMail(recipient, subject or "", body or "")
end

function module:ArmFromCurrentMail()
    if self:GetQueueCount() == 0 or self.state then
        return
    end

    if getOutgoingMoneyAmount() > 0 then
        addon:Print("Mass Send queue is paused because outgoing gold is set.")
        return
    end

    local state = self:CaptureState()
    local attachedCount = select(1, getUsedAttachmentSlots())
    if state and attachedCount > 0 then
        self.state = state
        self.state.itemsSent = attachedCount
        self.state.sends = 1
    end
end

function module:StartFromQueue()
    if self:GetQueueCount() == 0 then
        return
    end

    if getOutgoingMoneyAmount() > 0 then
        addon:Print("Mass Send does not support outgoing gold. Clear the money fields first.")
        return
    end

    local state = self:CaptureState()
    if not state then
        addon:Print("Enter a recipient before starting Mass Send.")
        return
    end

    self.state = state
    local attached = self:AttachQueuedItems()
    if attached <= 0 then
        self:Finish("Mass Send could not prepare the first mail.")
        return
    end

    self.state.itemsSent = attached
    self.state.sends = 1
    addon:Print("Mass Send armed for " .. state.recipient .. " with " .. self:GetQueueCount() .. " queued item" .. (self:GetQueueCount() == 1 and "" or "s") .. " remaining.")
    self:PerformSend(state.recipient, state.subject, state.body)
end

function module:ContinueAfterSuccess()
    if not self.state then
        return
    end

    self.state.awaitingResult = false

    addon:AddRecentRecipient(self.state.recipient)
    addon:SetLastMailedRecipient(self.state.recipient)

    if not SendMailFrame or not SendMailFrame:IsShown() then
        self:Finish("Mass Send stopped because the mail window was closed.")
        return
    end

    if self:GetQueueCount() == 0 then
        self:Finish()
        return
    end

    setComposeFields(self.state.recipient, self.state.subject, self.state.body)

    local attached = self:AttachQueuedItems()
    if attached <= 0 then
        self:Finish("Mass Send stopped because no queued items could be attached.")
        return
    end

    self.state.itemsSent = (self.state.itemsSent or 0) + attached
    self.state.sends = (self.state.sends or 0) + 1
    self:PerformSend(self.state.recipient, self.state.subject, self.state.body)
end

function module:HandleSendFailed()
    if self.state then
        self.state.awaitingResult = false
        self:Finish("Mass Send stopped after a send failure.")
    end
end

function module:HandleMailClosed()
    self:ClearQueue(true)
    if self.viewer then
        self.viewer:Hide()
    end

    if self.state then
        self:Finish("Mass Send stopped because the mail window was closed.")
        return
    end
end

function module:OnInitialize()
    self:EnsureCloseHooks()
end

addon:RegisterModule("MassSend", module)
