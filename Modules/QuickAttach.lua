local addon = EasyMail
local module = {}

module.hookApplied = false
module.mixinHookApplied = false
module.clickHookApplied = false
module.pickupHookApplied = false
module.useHookApplied = false
module.errorFilterApplied = false
module.errorEventFilterApplied = false
module.lastHandledKey = nil
module.lastHandledAt = 0
module.definitions = {
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

local function getMassSendModule()
    return addon.modules and addon.modules.MassSend or nil
end

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

local function isAttachmentLimitError(message)
    if not message then
        return false
    end

    if ERR_MAIL_ATTACH_LIMIT and message == ERR_MAIL_ATTACH_LIMIT then
        return true
    end

    local normalized = string.lower(tostring(message))
    return normalized:find("attach more than 12 items", 1, true) ~= nil
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

function module:AttachContainerItem(bag, slot)
    if bag == nil or slot == nil or not SendMailFrame or not SendMailFrame:IsShown() then
        return false
    end

    if CursorHasItem() then
        ClickSendMailItemButton()
        return not CursorHasItem()
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

function module:ShouldSuppressAttachmentLimitError(message)
    if not isAttachmentLimitError(message) then
        return false
    end

    if not SendMailFrame or not SendMailFrame:IsShown() then
        return false
    end

    local usedSlots, maxSlots = getUsedAttachmentSlots()
    return usedSlots >= maxSlots
end

function module:GetDefinitions()
    return self.definitions
end

function module:GetMatchCount(definition)
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

function module:AttachByDefinition(definition)
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
                    if self:AttachContainerItem(bag, slot) then
                        attached = attached + 1
                    end
                end
            end
        end
    end

    return attached, matched
end

function module:HandleMailItemClick(button, mouseButton)
    if not SendMailFrame or not SendMailFrame:IsShown() then
        return
    end

    local isAltAttach = mouseButton == "LeftButton" and IsAltKeyDown()
    local isOverflowQueueClick = mouseButton == "RightButton"

    if not isAltAttach and not isOverflowQueueClick then
        return
    end

    local bag, slot = getContainerLocation(button)
    if bag == nil or slot == nil then
        return
    end

    local key = getQueueKey(bag, slot)
    local now = GetTime()
    if self.lastHandledKey == key and (now - (self.lastHandledAt or 0)) < 0.15 then
        return
    end
    self.lastHandledKey = key
    self.lastHandledAt = now

    local usedSlots, maxSlots = getUsedAttachmentSlots()
    if usedSlots < maxSlots then
        if isAltAttach then
            self:AttachContainerItem(bag, slot)
        end
        return
    end

    local massSend = getMassSendModule()
    if massSend and massSend:QueueItem(bag, slot) then
        massSend:ShowQueueViewer()
        addon:Debug("Queued item for Mass Send (" .. massSend:GetQueueCount() .. " queued).")
    end
end

function module:HandlePickupRoute(bag, slot)
    if not SendMailFrame or not SendMailFrame:IsShown() then
        return
    end

    if bag == nil or slot == nil then
        return
    end

    local isAltFlow = IsAltKeyDown()
    local isRightQueueFlow = IsMouseButtonDown and IsMouseButtonDown("RightButton")

    if not isAltFlow and not isRightQueueFlow then
        return
    end

    local key = getQueueKey(bag, slot)
    local now = GetTime()
    if self.lastHandledKey == key and (now - (self.lastHandledAt or 0)) < 0.15 then
        return
    end
    self.lastHandledKey = key
    self.lastHandledAt = now

    local usedSlots, maxSlots = getUsedAttachmentSlots()
    if usedSlots < maxSlots then
        if isAltFlow then
            C_Timer.After(0, function()
                if CursorHasItem() and SendMailFrame and SendMailFrame:IsShown() then
                    ClickSendMailItemButton()
                end
            end)
        end
        return
    end

    local massSend = getMassSendModule()
    if massSend and massSend:QueueItem(bag, slot) then
        if CursorHasItem() then
            ClearCursor()
        end
        massSend:ShowQueueViewer()
        addon:Debug("Queued item for Mass Send (" .. massSend:GetQueueCount() .. " queued).")
    end
end

function module:HandleUseRoute(bag, slot)
    if not SendMailFrame or not SendMailFrame:IsShown() or bag == nil or slot == nil then
        return
    end

    local key = getQueueKey(bag, slot)
    local now = GetTime()
    if self.lastHandledKey == key and (now - (self.lastHandledAt or 0)) < 0.15 then
        return
    end

    local usedSlots, maxSlots = getUsedAttachmentSlots()
    if usedSlots < maxSlots then
        return
    end

    self.lastHandledKey = key
    self.lastHandledAt = now

    local massSend = getMassSendModule()
    if massSend and massSend:QueueItem(bag, slot) then
        massSend:ShowQueueViewer()
        addon:Debug("Queued item for Mass Send (" .. massSend:GetQueueCount() .. " queued).")
    end
end

function module:EnsureBagHook()
    if not self.hookApplied and ContainerFrameItemButton_OnModifiedClick then
        hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(selfButton, mouseButton)
            module:HandleMailItemClick(selfButton, mouseButton)
        end)
        self.hookApplied = true
    end

    if not self.mixinHookApplied and ContainerFrameItemButtonMixin and ContainerFrameItemButtonMixin.OnModifiedClick then
        hooksecurefunc(ContainerFrameItemButtonMixin, "OnModifiedClick", function(selfButton, mouseButton)
            module:HandleMailItemClick(selfButton, mouseButton)
        end)
        self.mixinHookApplied = true
    end

    if not self.clickHookApplied and ContainerFrameItemButtonMixin and ContainerFrameItemButtonMixin.OnClick then
        hooksecurefunc(ContainerFrameItemButtonMixin, "OnClick", function(selfButton, mouseButton)
            module:HandleMailItemClick(selfButton, mouseButton)
        end)
        self.clickHookApplied = true
    end

    if not self.pickupHookApplied then
        if PickupContainerItem then
            hooksecurefunc("PickupContainerItem", function(bag, slot)
                module:HandlePickupRoute(bag, slot)
            end)
        end
        if C_Container and C_Container.PickupContainerItem then
            hooksecurefunc(C_Container, "PickupContainerItem", function(_, bag, slot)
                module:HandlePickupRoute(bag, slot)
            end)
        end
        self.pickupHookApplied = true
    end

    if not self.useHookApplied then
        if UseContainerItem then
            hooksecurefunc("UseContainerItem", function(bag, slot)
                module:HandleUseRoute(bag, slot)
            end)
        end
        if C_Container and C_Container.UseContainerItem then
            hooksecurefunc(C_Container, "UseContainerItem", function(_, bag, slot)
                module:HandleUseRoute(bag, slot)
            end)
        end
        self.useHookApplied = true
    end
end

function module:EnsureErrorFilter()
    if self.errorFilterApplied or not UIErrorsFrame or not UIErrorsFrame.AddMessage then
        return
    end

    local originalAddMessage = UIErrorsFrame.AddMessage
    UIErrorsFrame.AddMessage = function(frame, message, ...)
        if module:ShouldSuppressAttachmentLimitError(message) then
            return
        end
        return originalAddMessage(frame, message, ...)
    end

    self.errorFilterApplied = true
end

function module:EnsureErrorEventFilter()
    if self.errorEventFilterApplied or not UIErrorsFrame then
        return
    end

    local originalOnEvent = UIErrorsFrame:GetScript("OnEvent")
    if not originalOnEvent then
        return
    end

    UIErrorsFrame:SetScript("OnEvent", function(frame, event, ...)
        if event == "UI_ERROR_MESSAGE" then
            local _, message = ...
            if module:ShouldSuppressAttachmentLimitError(message) then
                return
            end
        end

        return originalOnEvent(frame, event, ...)
    end)

    self.errorEventFilterApplied = true
end

function module:OnInitialize()
    self:EnsureBagHook()
    self:EnsureErrorFilter()
    self:EnsureErrorEventFilter()
end

addon:RegisterModule("QuickAttach", module)
