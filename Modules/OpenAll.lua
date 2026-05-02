local addon = EasyMail
local module = {}

module.isProcessing = false
module.timer = 0
module.interval = 0.35
module.button = nil
module.openSelectedButton = nil
module.returnSelectedButton = nil
module.ahSoldButton = nil
module.menuButton = nil
module.isUiReady = false
module.defaultButtonText = OPEN_ALL_MAIL or "Open All"
module.menuFrame = nil
module.stats = nil
module.stopReason = nil
module.currentRun = nil
module.hiddenBlizzardButton = nil

local processor = CreateFrame("Frame")
local inboxRowHooksApplied = false

local function getSelectionModule()
    return addon.modules and addon.modules.OpenAllSelect or nil
end

local function getInboxCount()
    return GetInboxNumItems() or 0
end

local function getInboxItemIndex(button)
    if not button or not button.GetID then
        return nil
    end

    local page = 1
    if InboxFrame and InboxFrame.pageNum then
        page = InboxFrame.pageNum
    end

    local perPage = INBOXITEMS_TO_DISPLAY or 7
    return ((page - 1) * perPage) + button:GetID()
end

local function getDisplayMailFrames(displayIndex)
    local itemFrame = _G["MailItem" .. displayIndex] or _G["InboxItem" .. displayIndex]
    local button = _G["MailItem" .. displayIndex .. "Button"] or _G["InboxItem" .. displayIndex .. "Button"]

    if not button and itemFrame and itemFrame:IsObjectType("Button") then
        button = itemFrame
    end

    if not itemFrame and button then
        itemFrame = button:GetParent() or button
    end

    return itemFrame, button
end

local function countAttachments(index)
    local total = 0
    for attachmentIndex = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
        local itemName = GetInboxItem(index, attachmentIndex)
        if itemName then
            total = total + 1
        end
    end
    return total
end

local function detectMailType(index, sender)
    local invoiceType = GetInboxInvoiceInfo and GetInboxInvoiceInfo(index)
    if invoiceType == "seller" then
        return "ahSold"
    end
    if invoiceType == "buyer" then
        return "ahWon"
    end
    if invoiceType == "cancel" then
        return "ahCancelled"
    end

    if sender == AUCTION_HOUSE_MAIL_MULTIPLE or sender == AUCTION_HOUSE_AUCTION_SOLD or sender == AUCTION_HOUSE_AUCTION_WON then
        return "ahOther"
    end

    return "nonAH"
end

local function getMailInfo(index)
    if not index or index < 1 then
        return nil
    end

    local _, _, sender, subject, money, codAmount, daysLeft, hasItem, _, _, _, _, isGM = GetInboxHeaderInfo(index)
    return {
        sender = sender,
        subject = subject,
        money = money or 0,
        codAmount = codAmount or 0,
        daysLeft = daysLeft or 0,
        hasItem = hasItem,
        attachmentCount = hasItem and countAttachments(index) or 0,
        isGM = isGM,
        mailType = detectMailType(index, sender),
    }
end

local function formatMoney(amount)
    return GetMoneyString(amount or 0, true) or "0"
end

local function getExpiryBehavior(info)
    if not info then
        return "delete"
    end

    if info.mailType ~= "nonAH" then
        return "delete"
    end

    if (info.attachmentCount or 0) > 0 or (info.money or 0) > 0 or (info.codAmount or 0) > 0 then
        return "return"
    end

    return "delete"
end

local function getExpiryColor(daysLeft)
    if daysLeft <= 3 then
        return 1, 0.25, 0.25
    end
    if daysLeft <= 7 then
        return 1, 0.82, 0
    end
    return 0.35, 1, 0.35
end

local function getFreeBagSlots()
    local freeSlots = 0
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = BACKPACK_CONTAINER or 0, lastBag do
        if C_Container and C_Container.GetContainerNumFreeSlots then
            local count = C_Container.GetContainerNumFreeSlots(bag)
            freeSlots = freeSlots + (count or 0)
        else
            local count = GetContainerNumFreeSlots(bag)
            freeSlots = freeSlots + (count or 0)
        end
    end
    return freeSlots
end

local function getFreeBagSlotBuckets()
    local genericSlots = 0
    local specialtySlots = {}
    local reagentSlots = 0
    local reagentBagIndex = NUM_TOTAL_EQUIPPED_BAG_SLOTS and (NUM_TOTAL_EQUIPPED_BAG_SLOTS > (NUM_BAG_SLOTS or 4)) and NUM_TOTAL_EQUIPPED_BAG_SLOTS or nil

    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = BACKPACK_CONTAINER or 0, lastBag do
        local count, family
        if C_Container and C_Container.GetContainerNumFreeSlots then
            count, family = C_Container.GetContainerNumFreeSlots(bag)
        else
            count, family = GetContainerNumFreeSlots(bag)
        end

        count = count or 0
        family = family or 0

        if family == 0 then
            genericSlots = genericSlots + count
        elseif reagentBagIndex and bag == reagentBagIndex then
            reagentSlots = reagentSlots + count
        elseif count > 0 then
            specialtySlots[family] = (specialtySlots[family] or 0) + count
        end
    end

    return genericSlots, specialtySlots, reagentSlots
end

local function getInboxAttachmentDescriptors(index)
    local descriptors = {}

    for attachmentIndex = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
        local itemLink = GetInboxItemLink and GetInboxItemLink(index, attachmentIndex)
        local itemName = nil
        if not itemLink then
            itemName = GetInboxItem(index, attachmentIndex)
        end

        if itemLink then
            local _, _, _, _, _, _, _, _, _, _, _, classID = GetItemInfo(itemLink)
            table.insert(descriptors, {
                family = GetItemFamily and (GetItemFamily(itemLink) or 0) or 0,
                classID = classID or 0,
            })
        elseif itemName then
            local _, _, _, _, _, _, _, _, _, _, _, classID = GetItemInfo(itemName)
            table.insert(descriptors, {
                family = 0,
                classID = classID or 0,
            })
        end
    end

    return descriptors
end

local function shouldConfirmDeleteAction(info)
    if not info then
        return false
    end

    return (info.money or 0) > 0
        or (info.codAmount or 0) > 0
        or (info.attachmentCount or 0) > 0
end

function module:GetSettings()
    return addon:GetOpenAllSettings()
end

function module:ExecuteDeleteAction(mailIndex)
    if not mailIndex or mailIndex < 1 or mailIndex > getInboxCount() then
        return
    end

    if InboxItemCanDelete and InboxItemCanDelete(mailIndex) and DeleteInboxItem then
        DeleteInboxItem(mailIndex)
    elseif ReturnInboxItem then
        ReturnInboxItem(mailIndex)
    end
end

function module:BuildDeleteConfirmText(info, canDelete)
    local actionText = canDelete and "delete" or "return"
    local senderText = info and info.sender and info.sender ~= "" and (" from " .. info.sender) or ""
    local detailParts = {}

    if (info.money or 0) > 0 then
        table.insert(detailParts, formatMoney(info.money))
    end
    if (info.attachmentCount or 0) > 0 then
        table.insert(detailParts, (info.attachmentCount or 0) .. " item" .. ((info.attachmentCount or 0) == 1 and "" or "s"))
    end
    if (info.codAmount or 0) > 0 then
        table.insert(detailParts, "COD " .. formatMoney(info.codAmount))
    end

    local details = #detailParts > 0 and ("\n\nContains: " .. table.concat(detailParts, ", ")) or ""
    return "EasyMail: " .. actionText:gsub("^%l", string.upper) .. " this mail" .. senderText .. "?" .. details
end

function module:ConfirmDeleteAction(mailIndex)
    local info = getMailInfo(mailIndex)
    if not info then
        return
    end

    local canDelete = InboxItemCanDelete and InboxItemCanDelete(mailIndex) and DeleteInboxItem
    if not shouldConfirmDeleteAction(info) then
        self:ExecuteDeleteAction(mailIndex)
        return
    end

    StaticPopupDialogs["EASYMAIL_CONFIRM_DEL_ACTION"] = StaticPopupDialogs["EASYMAIL_CONFIRM_DEL_ACTION"] or {
        button1 = YES,
        button2 = CANCEL,
        OnAccept = function(selfPopup)
            module:ExecuteDeleteAction(selfPopup.data)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    local dialog = StaticPopupDialogs["EASYMAIL_CONFIRM_DEL_ACTION"]
    dialog.text = self:BuildDeleteConfirmText(info, canDelete)
    StaticPopup_Show("EASYMAIL_CONFIRM_DEL_ACTION", nil, nil, mailIndex)
end

function module:IsOverrideActive()
    return self.currentRun and self.currentRun.overrideFilters
end

function module:IsAhSoldOnlyRun()
    return self.currentRun and self.currentRun.ahSoldOnly
end

function module:IsSelectedOpenRun()
    return self.currentRun and self.currentRun.selectedAction == "open"
end

function module:IsSelectedReturnRun()
    return self.currentRun and self.currentRun.selectedAction == "return"
end

function module:EnsureStats()
    self.stats = self.stats or {
        mails = 0,
        items = 0,
        money = 0,
        codSpent = 0,
        skippedCOD = 0,
        skippedGM = 0,
        skippedByType = 0,
        bagStops = 0,
        byType = {},
    }
end

function module:ResetStats()
    self.stats = {
        mails = 0,
        items = 0,
        money = 0,
        codSpent = 0,
        skippedCOD = 0,
        skippedGM = 0,
        skippedByType = 0,
        bagStops = 0,
        byType = {},
    }
    self.stopReason = nil
end

function module:GetEffectiveTakeMoney()
    if self:IsOverrideActive() or self:IsAhSoldOnlyRun() or self:IsSelectedOpenRun() then
        return true
    end

    return self:GetSettings().takeMoney
end

function module:GetEffectiveTakeItems()
    if self:IsOverrideActive() or self:IsSelectedOpenRun() then
        return true
    end

    if self:IsAhSoldOnlyRun() then
        return false
    end

    return self:GetSettings().takeItems
end

function module:IsMailTypeEnabled(info)
    if self:IsAhSoldOnlyRun() then
        return info and info.mailType == "ahSold"
    end

    if self:IsOverrideActive() or self:IsSelectedOpenRun() then
        return true
    end

    local mailTypes = self:GetSettings().mailTypes or {}
    return mailTypes[info.mailType] ~= false
end

function module:HasEnoughFreeSlots(neededSlots)
    local reservedSlots = math.max(0, self:GetSettings().leaveFreeSlots or 0)
    return (getFreeBagSlots() - reservedSlots) >= (neededSlots or 1)
end

function module:GetUsableFreeBagSlots()
    local reservedSlots = math.max(0, self:GetSettings().leaveFreeSlots or 0)
    return math.max(0, getFreeBagSlots() - reservedSlots)
end

function module:CanFitAnyInboxAttachment(index, info)
    if not info or not info.hasItem then
        return false, 0
    end

    local genericSlots, specialtySlots, reagentSlots = getFreeBagSlotBuckets()
    local reservedSlots = math.max(0, self:GetSettings().leaveFreeSlots or 0)

    if reservedSlots > 0 then
        local genericReserve = math.min(genericSlots, reservedSlots)
        genericSlots = genericSlots - genericReserve
        reservedSlots = reservedSlots - genericReserve

        if reservedSlots > 0 then
            for family, count in pairs(specialtySlots) do
                if reservedSlots <= 0 then
                    break
                end

                local familyReserve = math.min(count, reservedSlots)
                specialtySlots[family] = count - familyReserve
                reservedSlots = reservedSlots - familyReserve
            end

            if reservedSlots > 0 and reagentSlots > 0 then
                local reagentReserve = math.min(reagentSlots, reservedSlots)
                reagentSlots = reagentSlots - reagentReserve
                reservedSlots = reservedSlots - reagentReserve
            end
        end
    end

    local usableSlots = genericSlots
    for _, count in pairs(specialtySlots) do
        usableSlots = usableSlots + count
    end
    usableSlots = usableSlots + reagentSlots

    if usableSlots <= 0 then
        return false, 0
    end

    local descriptors = getInboxAttachmentDescriptors(index)
    if #descriptors == 0 then
        return usableSlots > 0, usableSlots
    end

    for _, descriptor in ipairs(descriptors) do
        if genericSlots > 0 then
            return true, usableSlots
        end

        local family = descriptor.family or 0
        if family and family > 0 then
            for bagFamily, count in pairs(specialtySlots) do
                if count > 0 and bit.band(family, bagFamily) ~= 0 then
                    return true, usableSlots
                end
            end
        end

        if reagentSlots > 0 and (descriptor.classID == 7) then
            return true, usableSlots
        end
    end

    return false, usableSlots
end

function module:CountProcessableMail(filterType)
    local count = 0
    for index = getInboxCount(), 1, -1 do
        local info = getMailInfo(index)
        if info and self:IsMailProcessable(info, filterType) then
            count = count + 1
        end
    end
    return count
end

function module:HideBlizzardButton()
    if not InboxFrame or not InboxFrame.GetChildren then
        return
    end

    local children = { InboxFrame:GetChildren() }
    for _, button in ipairs(children) do
        if button
            and button ~= self.button
            and button ~= self.ahSoldButton
            and button:IsObjectType("Button")
            and button.GetText
        then
            local text = button:GetText()
            if text == OPEN_ALL_MAIL or text == "Open All" then
                button:Hide()
                button:EnableMouse(false)
                button:SetAlpha(0)
            end
        end
    end
end

function module:UpdateButtonState()
    if self.button then
        local buttonText = self.defaultButtonText
        if self.isProcessing then
            if self:IsSelectedOpenRun() then
                buttonText = "Opening Sel..."
            else
                buttonText = self:IsOverrideActive() and "Opening All..." or "Opening..."
            end
        end
        self.button:SetText(buttonText)

        local hasMail = getInboxCount() > 0
        local hasActionsEnabled = self:GetSettings().takeMoney or self:GetSettings().takeItems
        self.button:SetEnabled(hasMail and (hasActionsEnabled or self:IsOverrideActive()) and not self.isProcessing)
    end

    if self.openSelectedButton then
        local selectedCount = self:GetSelectedMailCount()
        self.openSelectedButton:SetText(self.isProcessing and self:IsSelectedOpenRun() and "Opening..." or "Open Sel")
        self.openSelectedButton:SetEnabled(selectedCount > 0 and not self.isProcessing)
    end

    if self.returnSelectedButton then
        local selectedCount = self:GetSelectedMailCount()
        self.returnSelectedButton:SetText(self.isProcessing and self:IsSelectedReturnRun() and "Returning..." or "Return Sel")
        self.returnSelectedButton:SetEnabled(selectedCount > 0 and not self.isProcessing)
    end

    if self.ahSoldButton then
        local hasSoldMail = self:CountProcessableMail("ahSold") > 0
        self.ahSoldButton:SetText(self.isProcessing and self:IsAhSoldOnlyRun() and "Opening..." or "AH Sold")
        self.ahSoldButton:SetEnabled(hasSoldMail and not self.isProcessing)
    end

    if self.menuButton then
        self.menuButton:SetEnabled(not self.isProcessing)
    end
end

function module:BuildTooltip()
    local settings = self:GetSettings()
    local overrideNote = IsShiftKeyDown() and "Shift held: next click ignores mail type filters." or "Shift-click: ignore mail type filters once."
    return {
        "Left click: process inbox",
        "Use AH Sold for auction sales only",
        "Use the small EM button for filters",
        overrideNote,
        "Shift-click mail row: quick loot money or attachments.",
        "Ctrl-click mail row: return mail.",
        "DEL sits under the expiry time and returns when delete is not allowed.",
        "Gold: " .. (settings.takeMoney and "on" or "off"),
        "Items: " .. (settings.takeItems and "on" or "off"),
        "Leave free slots: " .. (settings.leaveFreeSlots or 0),
    }
end

function module:HandleButtonClick(_, mouseButton)
    if mouseButton == "RightButton" then
        if module.menuButton then
            module:ToggleMenu(module.menuButton)
        end
        return
    end

    module:StartProcessing({ overrideFilters = IsShiftKeyDown() })
end

function module:HandleAhSoldButtonClick()
    module:StartProcessing({ ahSoldOnly = true })
end

function module:HandleOpenSelectedClick()
    module:StartProcessing({ selectedAction = "open" })
end

function module:HandleReturnSelectedClick()
    module:StartProcessing({ selectedAction = "return" })
end

function module:HandleInboxRowClick(button)
    local index = getInboxItemIndex(button)
    if not index or index < 1 or index > getInboxCount() then
        return
    end

    local info = getMailInfo(index)
    if not info then
        return
    end

    if IsControlKeyDown() then
        if info.codAmount and info.codAmount > 0 then
            addon:Print("Cannot return COD mail with Ctrl-click.")
            return
        end

        ReturnInboxItem(index)
        return
    end

    if not IsShiftKeyDown() then
        return
    end

    if info.money and info.money > 0 then
        TakeInboxMoney(index)
        addon:Debug("Quick loot: received " .. formatMoney(info.money) .. ".")
        return
    end

    if info.hasItem then
        AutoLootMailItem(index)
    end
end

function module:GetExpireTimeFrame(displayIndex)
    return _G["MailItem" .. displayIndex .. "ExpireTime"] or _G["InboxItem" .. displayIndex .. "ExpireTime"]
end

function module:GetSelectedMailCount()
    local selection = getSelectionModule()
    return selection and selection:GetSelectedMailCount() or 0
end

function module:IsMailSelected(mailIndex)
    local selection = getSelectionModule()
    return selection and selection:IsMailSelected(mailIndex) or false
end

function module:ClearSelection()
    local selection = getSelectionModule()
    if selection then
        selection:ClearSelection()
    end
end

function module:ToggleSelection(mailIndex)
    local selection = getSelectionModule()
    if selection then
        selection:ToggleSelection(mailIndex)
    end
end

function module:GetRowCheckbox(displayIndex)
    local selection = getSelectionModule()
    return selection and selection:GetRowCheckbox(displayIndex) or nil
end

function module:UpdateVisibleSelections()
    local selection = getSelectionModule()
    if selection then
        selection:UpdateVisibleSelections()
    end
end

local function styleExpiryActionButton(button)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    button:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    button:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetScript("OnEnter", function(selfButton)
        GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
        GameTooltip:SetText(selfButton.tooltipText or "")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function module:EnsureExpiryIndicator(displayIndex)
    local expireTime = self:GetExpireTimeFrame(displayIndex)
    if not expireTime then
        return nil
    end

    if expireTime.easyMailExpiryButtons then
        return expireTime.easyMailExpiryButtons
    end

    local holder = CreateFrame("Frame", nil, expireTime)
    holder:SetSize(26, 14)
    holder:SetPoint("TOP", expireTime, "BOTTOM", 29, 0)

    local delButton = CreateFrame("Button", nil, holder, "BackdropTemplate")
    delButton:SetSize(26, 14)
    delButton:SetPoint("CENTER", holder, "CENTER", 0, 0)
    styleExpiryActionButton(delButton)
    delButton.text:SetText("DEL")
    delButton:SetScript("OnClick", function(selfButton)
        if not selfButton.mailIndex then
            return
        end

        module:ConfirmDeleteAction(selfButton.mailIndex)
    end)

    expireTime.easyMailExpiryButtons = {
        holder = holder,
        del = delButton,
    }
    return expireTime.easyMailExpiryButtons
end

function module:UpdateVisibleExpiryIndicators()
    local perPage = INBOXITEMS_TO_DISPLAY or 7
    local page = InboxFrame and InboxFrame.pageNum or 1

    for displayIndex = 1, perPage do
        local buttons = self:EnsureExpiryIndicator(displayIndex)
        if buttons then
            local mailIndex = displayIndex + ((page - 1) * perPage)
            if mailIndex > getInboxCount() then
                buttons.holder:Hide()
            else
                local info = getMailInfo(mailIndex)
                if info then
                    local canDelete = InboxItemCanDelete and InboxItemCanDelete(mailIndex)
                    buttons.del.mailIndex = mailIndex
                    if shouldConfirmDeleteAction(info) then
                        buttons.del.tooltipText = canDelete and "Delete this mail. EasyMail will ask for confirmation because it still contains gold, attachments, or COD." or "Delete is not allowed here, so DEL will return the mail instead. EasyMail will ask for confirmation because it still contains gold, attachments, or COD."
                    else
                        buttons.del.tooltipText = canDelete and "Delete this mail now." or "Delete is not allowed here, so DEL will return the mail instead."
                    end
                    buttons.del.text:SetTextColor(1, 0.30, 0.30)
                    buttons.del:SetAlpha(1)
                    buttons.del:SetEnabled(true)
                    buttons.holder:Show()
                else
                    buttons.holder:Hide()
                end
            end
        end
    end
end

function module:ShowTooltip(owner)
    if not owner then
        return
    end

    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine("EasyMail")
    for _, line in ipairs(module:BuildTooltip()) do
        GameTooltip:AddLine(line, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

function module:ApplyButtonScripts(button)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(selfButton, mouseButton)
        module:HandleButtonClick(selfButton, mouseButton)
    end)
    button:SetScript("OnEnter", function(selfButton)
        module:ShowTooltip(selfButton)
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function module:IsMailProcessable(info, forcedType)
    if not info then
        return false
    end

    local settings = self:GetSettings()

    if settings.skipGM and info.isGM then
        return false
    end

    if not settings.allowCOD and info.codAmount > 0 then
        return false
    end

    if forcedType and info.mailType ~= forcedType then
        return false
    end

    if not self:IsMailTypeEnabled(info) then
        return false
    end

    if self:GetEffectiveTakeMoney() and info.money > 0 then
        return true
    end

    if self:GetEffectiveTakeItems() and info.hasItem then
        return true
    end

    return false
end

function module:ScanInboxOverview()
    local stats = {
        skippedCOD = 0,
        skippedGM = 0,
        skippedByType = 0,
    }

    for index = getInboxCount(), 1, -1 do
        local info = getMailInfo(index)
        if info then
            if info.isGM and self:GetSettings().skipGM then
                stats.skippedGM = stats.skippedGM + 1
            elseif info.codAmount > 0 and not self:GetSettings().allowCOD then
                stats.skippedCOD = stats.skippedCOD + 1
            elseif not self:IsMailTypeEnabled(info) then
                stats.skippedByType = stats.skippedByType + 1
            end
        end
    end

    return stats
end

function module:FindNextLootableMail()
    local forcedType = self:IsAhSoldOnlyRun() and "ahSold" or nil
    for index = getInboxCount(), 1, -1 do
        local info = getMailInfo(index)
        if self:IsMailProcessable(info, forcedType) then
            return index, info
        end
    end

    return nil, nil
end

function module:FindNextSelectedMail()
    for index = getInboxCount(), 1, -1 do
        if self:IsMailSelected(index) then
            local info = getMailInfo(index)
            if info then
                return index, info
            end
            self.selection[index] = nil
        end
    end

    return nil, nil
end

function module:TrackMailType(mailType)
    self.stats.byType[mailType] = (self.stats.byType[mailType] or 0) + 1
end

function module:TakeFromMail(index, info)
    self:EnsureStats()

    if self:GetEffectiveTakeMoney() and info.money > 0 then
        self.stats.mails = self.stats.mails + 1
        self.stats.money = self.stats.money + info.money
        self:TrackMailType(info.mailType)
        addon:Debug("Taking gold from mail " .. index)
        TakeInboxMoney(index)
        return true
    end

    if self:GetEffectiveTakeItems() and info.hasItem then
        local canFitAttachment, usableSlots = self:CanFitAnyInboxAttachment(index, info)
        if not canFitAttachment then
            self.stats.bagStops = self.stats.bagStops + 1
            self:StopProcessing("reserved bag space reached")
            return false
        end

        if usableSlots < (info.attachmentCount or 1) then
            addon:Debug("Bag space is tighter than this mail's attachment count; trying to loot with " .. usableSlots .. " usable slot(s).")
        end

        self.stats.mails = self.stats.mails + 1
        self.stats.items = self.stats.items + (info.attachmentCount or 1)
        self:TrackMailType(info.mailType)
        if info.codAmount > 0 then
            self.stats.codSpent = self.stats.codSpent + info.codAmount
        end
        addon:Debug("Taking item from mail " .. index)
        AutoLootMailItem(index)
        return true
    end

    return false
end

function module:ProcessNextSelectedReturn()
    local index, info = self:FindNextSelectedMail()
    if not index or not info then
        self:StopProcessing()
        return
    end

    if info.codAmount and info.codAmount > 0 then
        self.stats.skippedCOD = (self.stats.skippedCOD or 0) + 1
        self.selection[index] = nil
        return
    end

    self.stats.returned = (self.stats.returned or 0) + 1
    self.selection[index] = nil
    ReturnInboxItem(index)
end

function module:ProcessNextMail()
    if self:IsSelectedReturnRun() then
        self:ProcessNextSelectedReturn()
        return
    end

    if self:IsSelectedOpenRun() then
        local selectedIndex, selectedInfo = self:FindNextSelectedMail()
        if not selectedIndex or not selectedInfo then
            self:StopProcessing()
            return
        end

        if not self:TakeFromMail(selectedIndex, selectedInfo) and self.isProcessing then
            self.selection[selectedIndex] = nil
        end
        return
    end

    local index, info = self:FindNextLootableMail()
    if not index or not info then
        self:StopProcessing()
        return
    end

    if not self:TakeFromMail(index, info) and self.isProcessing then
        self:StopProcessing("nothing matched the current filters")
    end
end

function module:BuildTypeSummaryParts()
    local labels = {
        nonAH = "non-AH",
        ahSold = "AH sold",
        ahCancelled = "AH cancelled",
        ahWon = "AH won",
        ahOther = "AH other",
    }
    local parts = {}

    for _, key in ipairs({ "nonAH", "ahSold", "ahCancelled", "ahWon", "ahOther" }) do
        local count = self.stats.byType[key]
        if count and count > 0 then
            table.insert(parts, labels[key] .. " " .. count)
        end
    end

    return parts
end

function module:BuildSummaryMessage()
    self:EnsureStats()

    local actionLabel = "Open All"
    if self:IsSelectedReturnRun() then
        actionLabel = "Return Sel"
    elseif self:IsSelectedOpenRun() then
        actionLabel = "Open Sel"
    elseif self:IsAhSoldOnlyRun() then
        actionLabel = "AH Sold"
    end

    if self:IsSelectedReturnRun() then
        local returned = self.stats.returned or 0
        local parts = {
            "returned " .. returned .. " selected mail" .. (returned == 1 and "" or "s"),
        }
        if self.stats.skippedCOD > 0 then
            table.insert(parts, "skipped " .. self.stats.skippedCOD .. " COD")
        end
        local suffix = self.stopReason and (" (" .. self.stopReason .. ")") or ""
        return "Mailbox Summary - " .. actionLabel .. ": " .. table.concat(parts, ", ") .. suffix
    end

    local parts = {
        self.stats.mails .. " mail" .. (self.stats.mails == 1 and "" or "s"),
    }

    if self.stats.money > 0 then
        table.insert(parts, formatMoney(self.stats.money))
    end
    if self.stats.items > 0 then
        table.insert(parts, self.stats.items .. " item" .. (self.stats.items == 1 and "" or "s"))
    end
    if self.stats.codSpent > 0 then
        table.insert(parts, "paid " .. formatMoney(self.stats.codSpent) .. " COD")
    end
    if self.stats.skippedCOD > 0 then
        table.insert(parts, "skipped " .. self.stats.skippedCOD .. " COD")
    end
    if self.stats.skippedGM > 0 then
        table.insert(parts, "skipped " .. self.stats.skippedGM .. " GM")
    end
    if self.stats.skippedByType > 0 then
        table.insert(parts, "filtered " .. self.stats.skippedByType)
    end

    local typeParts = self:BuildTypeSummaryParts()
    for _, part in ipairs(typeParts) do
        table.insert(parts, part)
    end

    local suffix = self.stopReason and (" (" .. self.stopReason .. ")") or ""
    return "Mailbox Summary - " .. actionLabel .. ": " .. table.concat(parts, ", ") .. suffix
end

function module:StartProcessing(options)
    if self.isProcessing then
        return
    end

    options = options or {}
    local overrideFilters = options.overrideFilters == true
    local ahSoldOnly = options.ahSoldOnly == true
    local selectedAction = options.selectedAction

    if selectedAction and self:GetSelectedMailCount() == 0 then
        addon:Print("Select at least one mail first.")
        return
    end

    if not selectedAction and not ahSoldOnly and not overrideFilters and not self:GetSettings().takeMoney and not self:GetSettings().takeItems then
        addon:Print("Enable gold or attachment looting first, or Shift-click to override once.")
        return
    end

    self.currentRun = {
        overrideFilters = overrideFilters,
        ahSoldOnly = ahSoldOnly,
        selectedAction = selectedAction,
    }

    self:ResetStats()
    local overview = self:ScanInboxOverview()
    self.stats.skippedCOD = overview.skippedCOD
    self.stats.skippedGM = overview.skippedGM
    self.stats.skippedByType = overview.skippedByType

    self.isProcessing = true
    self.timer = 0
    processor:Show()
    self:UpdateButtonState()
end

function module:StopProcessing(reason)
    self.isProcessing = false
    self.timer = 0
    processor:Hide()
    self.stopReason = reason
    local finishedRun = self.currentRun
    local summary = self:BuildSummaryMessage()
    self.currentRun = nil
    self:UpdateButtonState()
    if finishedRun and finishedRun.selectedAction then
        self:ClearSelection()
    end
    self:UpdateVisibleExpiryIndicators()
    self:UpdateVisibleSelections()
    addon:Print(summary)
end

function module:ToggleSetting(key)
    local settings = self:GetSettings()
    settings[key] = not settings[key]
    self:UpdateButtonState()
end

function module:ToggleMailType(key)
    local settings = self:GetSettings()
    settings.mailTypes[key] = not settings.mailTypes[key]
    self:UpdateButtonState()
end

function module:AdjustReservedSlots(delta)
    local settings = self:GetSettings()
    settings.leaveFreeSlots = math.max(0, math.min(40, (settings.leaveFreeSlots or 0) + delta))
    self:UpdateButtonState()
end

function module:EnsureMenu()
    if self.menuFrame then
        return
    end

    self.menuFrame = addon:CreateContextMenu("EasyMailOpenAllMenu")
end

function module:BuildMenuItems(anchor)
    local settings = self:GetSettings()
    return {
        {
            text = "EasyMail Filters",
            isTitle = true,
        },
        {
            text = "Take Gold",
            checked = settings.takeMoney,
            keepShownOnClick = true,
            func = function()
                module:ToggleSetting("takeMoney")
                addon:PopulateContextMenu(module.menuFrame, anchor, module:BuildMenuItems(anchor))
            end,
        },
        {
            text = "Take Attachments",
            checked = settings.takeItems,
            keepShownOnClick = true,
            func = function()
                module:ToggleSetting("takeItems")
                addon:PopulateContextMenu(module.menuFrame, anchor, module:BuildMenuItems(anchor))
            end,
        },
        {
            text = "Allow COD",
            checked = settings.allowCOD,
            keepShownOnClick = true,
            func = function()
                module:ToggleSetting("allowCOD")
                addon:PopulateContextMenu(module.menuFrame, anchor, module:BuildMenuItems(anchor))
            end,
        },
        {
            text = "Skip GM Mail",
            checked = settings.skipGM,
            keepShownOnClick = true,
            func = function()
                module:ToggleSetting("skipGM")
                addon:PopulateContextMenu(module.menuFrame, anchor, module:BuildMenuItems(anchor))
            end,
        },
        {
            text = "Stop On Bags Full",
            checked = settings.stopOnBagsFull,
            keepShownOnClick = true,
            func = function()
                module:ToggleSetting("stopOnBagsFull")
                addon:PopulateContextMenu(module.menuFrame, anchor, module:BuildMenuItems(anchor))
            end,
        },
        {
            text = "Leave Free Slots: " .. (settings.leaveFreeSlots or 0),
            isTitle = true,
        },
        {
            text = "Reserve One More Slot",
            keepShownOnClick = true,
            func = function()
                module:AdjustReservedSlots(1)
                addon:PopulateContextMenu(module.menuFrame, anchor, module:BuildMenuItems(anchor))
            end,
        },
        {
            text = "Reserve One Less Slot",
            keepShownOnClick = true,
            func = function()
                module:AdjustReservedSlots(-1)
                addon:PopulateContextMenu(module.menuFrame, anchor, module:BuildMenuItems(anchor))
            end,
        },
        {
            text = "Mail Types",
            isTitle = true,
        },
        {
            text = "Non-AH Mail",
            checked = settings.mailTypes.nonAH,
            keepShownOnClick = true,
            func = function()
                module:ToggleMailType("nonAH")
                addon:PopulateContextMenu(module.menuFrame, anchor, module:BuildMenuItems(anchor))
            end,
        },
        {
            text = "AH Sold",
            checked = settings.mailTypes.ahSold,
            keepShownOnClick = true,
            func = function()
                module:ToggleMailType("ahSold")
                addon:PopulateContextMenu(module.menuFrame, anchor, module:BuildMenuItems(anchor))
            end,
        },
        {
            text = "AH Cancelled",
            checked = settings.mailTypes.ahCancelled,
            keepShownOnClick = true,
            func = function()
                module:ToggleMailType("ahCancelled")
                addon:PopulateContextMenu(module.menuFrame, anchor, module:BuildMenuItems(anchor))
            end,
        },
        {
            text = "AH Won",
            checked = settings.mailTypes.ahWon,
            keepShownOnClick = true,
            func = function()
                module:ToggleMailType("ahWon")
                addon:PopulateContextMenu(module.menuFrame, anchor, module:BuildMenuItems(anchor))
            end,
        },
        {
            text = "Other AH Mail",
            checked = settings.mailTypes.ahOther,
            keepShownOnClick = true,
            func = function()
                module:ToggleMailType("ahOther")
                addon:PopulateContextMenu(module.menuFrame, anchor, module:BuildMenuItems(anchor))
            end,
        },
    }
end

function module:ToggleMenu(anchor)
    self:EnsureMenu()
    addon:ToggleContextMenu(self.menuFrame, anchor, self:BuildMenuItems(anchor))
end

function module:EnsureUi()
    if self.isUiReady or not InboxFrame then
        return
    end

    self:HideBlizzardButton()

    local buttonAnchor = InboxFrame

    local button = addon:CreateButton(InboxFrame, self.defaultButtonText, 74, 22, "BOTTOM", buttonAnchor, "BOTTOM", -145, 102)
    button:ClearAllPoints()
    button:SetPoint("BOTTOM", buttonAnchor, "BOTTOM", -145, 102)

    local ahSoldButton = addon:CreateButton(InboxFrame, "AH Sold", 68, 22, "BOTTOM", buttonAnchor, "BOTTOM", -40, 102)
    ahSoldButton:ClearAllPoints()
    ahSoldButton:SetPoint("LEFT", button, "RIGHT", 8, 0)
    ahSoldButton:SetScript("OnClick", function()
        module:HandleAhSoldButtonClick()
    end)
    ahSoldButton:SetScript("OnEnter", function(selfButton)
        GameTooltip:SetOwner(selfButton, "ANCHOR_TOP")
        GameTooltip:AddLine("EasyMail")
        GameTooltip:AddLine("Open only sold Auction House mail.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    ahSoldButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local openSelectedButton = addon:CreateButton(InboxFrame, "Open Sel", 68, 22, "BOTTOM", buttonAnchor, "BOTTOM", 40, 102)
    openSelectedButton:ClearAllPoints()
    openSelectedButton:SetPoint("LEFT", ahSoldButton, "RIGHT", 8, 0)
    openSelectedButton:SetScript("OnClick", function()
        module:HandleOpenSelectedClick()
    end)
    openSelectedButton:SetScript("OnEnter", function(selfButton)
        GameTooltip:SetOwner(selfButton, "ANCHOR_TOP")
        GameTooltip:AddLine("EasyMail Select")
        GameTooltip:AddLine("Open the mails you selected with the row checkboxes.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    openSelectedButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local returnSelectedButton = addon:CreateButton(InboxFrame, "Return Sel", 78, 22, "BOTTOM", buttonAnchor, "BOTTOM", 120, 102)
    returnSelectedButton:ClearAllPoints()
    returnSelectedButton:SetPoint("LEFT", openSelectedButton, "RIGHT", 8, 0)
    returnSelectedButton:SetScript("OnClick", function()
        module:HandleReturnSelectedClick()
    end)
    returnSelectedButton:SetScript("OnEnter", function(selfButton)
        GameTooltip:SetOwner(selfButton, "ANCHOR_TOP")
        GameTooltip:AddLine("EasyMail Select")
        GameTooltip:AddLine("Return the mails you selected with the row checkboxes.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    returnSelectedButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local menuButton = addon:CreateButton(InboxFrame, "EM", 28, 22, "TOPRIGHT", InboxFrame, "TOPRIGHT", -68, -30)
    menuButton:ClearAllPoints()
    menuButton:SetPoint("TOPRIGHT", InboxFrame, "TOPRIGHT", -68, -30)
    menuButton:SetScript("OnClick", function()
        module:ToggleMenu(menuButton)
    end)
    menuButton:SetScript("OnEnter", function(selfButton)
        GameTooltip:SetOwner(selfButton, "ANCHOR_TOP")
        GameTooltip:AddLine("EasyMail Filters")
        GameTooltip:AddLine("Open or close the Open All filter menu.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    menuButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.button = button
    self.openSelectedButton = openSelectedButton
    self.returnSelectedButton = returnSelectedButton
    self.ahSoldButton = ahSoldButton
    self.menuButton = menuButton
    self:ApplyButtonScripts(button)
    self.isUiReady = true
    self:UpdateButtonState()
    self:UpdateVisibleExpiryIndicators()
    self:UpdateVisibleSelections()

    if not inboxRowHooksApplied then
        local perPage = INBOXITEMS_TO_DISPLAY or 7
        for index = 1, perPage do
            local _, rowButton = getDisplayMailFrames(index)
            if rowButton then
                rowButton:HookScript("OnClick", function(selfButton)
                    module:HandleInboxRowClick(selfButton)
                end)
            end
        end
        inboxRowHooksApplied = true
    end

    InboxFrame:HookScript("OnShow", function()
        module:HideBlizzardButton()
        CheckInbox()
        module:UpdateButtonState()
        module:UpdateVisibleExpiryIndicators()
        module:UpdateVisibleSelections()
    end)

    if InboxPrevPageButton then
        InboxPrevPageButton:HookScript("OnClick", function()
            C_Timer.After(0, function()
                module:UpdateVisibleExpiryIndicators()
                module:UpdateVisibleSelections()
            end)
        end)
    end

    if InboxNextPageButton then
        InboxNextPageButton:HookScript("OnClick", function()
            C_Timer.After(0, function()
                module:UpdateVisibleExpiryIndicators()
                module:UpdateVisibleSelections()
            end)
        end)
    end
end

function module:OnInitialize()
    self:EnsureMenu()

    processor:Hide()
    processor:SetScript("OnUpdate", function(_, elapsed)
        if not module.isProcessing then
            return
        end

        module.timer = module.timer + elapsed
        if module.timer < module.interval then
            return
        end

        module.timer = 0
        module:ProcessNextMail()
    end)

    processor:RegisterEvent("MAIL_INBOX_UPDATE")
    processor:RegisterEvent("MAIL_CLOSED")
    processor:RegisterEvent("MAIL_SHOW")
    processor:RegisterEvent("UI_ERROR_MESSAGE")
    processor:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "MAIL_INBOX_UPDATE" then
            module:UpdateButtonState()
            module:UpdateVisibleExpiryIndicators()
            module:UpdateVisibleSelections()
            if module.isProcessing and not module:IsSelectedReturnRun() and not module:IsSelectedOpenRun() and not module:FindNextLootableMail() then
                module:StopProcessing()
            end
        elseif event == "MAIL_SHOW" then
            module:EnsureUi()
            module:HideBlizzardButton()
            CheckInbox()
            module:UpdateButtonState()
            module:UpdateVisibleExpiryIndicators()
            module:UpdateVisibleSelections()
        elseif event == "MAIL_CLOSED" and module.isProcessing then
            module:StopProcessing("mailbox closed")
        elseif event == "UI_ERROR_MESSAGE" and module.isProcessing then
            local message = arg2 or arg1
            if message == ERR_INV_FULL or message == ERR_ITEM_MAX_COUNT or message == ERR_ITEM_MAX_COUNT_SOCKETED then
                if module:GetSettings().stopOnBagsFull then
                    module:StopProcessing("bags full")
                end
            elseif message == ERR_NOT_ENOUGH_MONEY then
                module:StopProcessing("not enough money for COD")
            end
        end
    end)
end

addon:RegisterModule("OpenAll", module)











































