local addon = EasyMail
local module = {}

module.ancestorHookApplied = false

local function getMassSendModule()
    return addon.modules and addon.modules.MassSend or nil
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

local function getNearestAncestorWithMethod(frame, methodName)
    local current = frame
    while current do
        if type(current[methodName]) == "function" then
            return current
        end
        current = current.GetParent and current:GetParent() or nil
    end
    return nil
end

local function getBaganatorSectionMatches(frame, tree)
    if not frame or type(tree) ~= "table" or type(frame.GetActiveLayouts) ~= "function" then
        return nil
    end

    local matches = {}
    for _, layout in ipairs(frame:GetActiveLayouts() or {}) do
        if layout.type == "category" then
            local rootMatch = true
            for index, label in ipairs(tree) do
                rootMatch = layout.section[index] == label
                if not rootMatch then
                    break
                end
            end
            if rootMatch and layout.SearchMonitor and layout.SearchMonitor.GetMatches then
                for _, entry in ipairs(layout.SearchMonitor:GetMatches() or {}) do
                    table.insert(matches, entry)
                end
            end
        end
    end

    return matches
end

function module:HandleOverflow(items, usedSlots, maxSlots)
    if not SendMailFrame or not SendMailFrame:IsShown() then
        return
    end

    local freeSlots = math.max(0, (maxSlots or (ATTACHMENTS_MAX_SEND or 12)) - (usedSlots or 0))
    local validSeen = 0
    local queuedAny = false
    local massSend = getMassSendModule()

    if not massSend or type(items) ~= "table" then
        return
    end

    for _, item in ipairs(items) do
        local bag = item and item.bagID
        local slot = item and item.slotID
        local itemInfo = getContainerItemInfoCompat(bag, slot)
        local itemLink = getContainerItemLinkCompat(bag, slot)

        if bag ~= nil and slot ~= nil and itemInfo and itemLink and not itemInfo.isLocked then
            validSeen = validSeen + 1
            if validSeen > freeSlots and massSend:QueueItem(bag, slot) then
                queuedAny = true
            end
        end
    end

    if queuedAny then
        massSend:ShowQueueViewer()
        addon:Debug("Queued extra Baganator mail items for Mass Send (" .. massSend:GetQueueCount() .. " queued).")
    end
end

function module:QueueOverflowDeferred(items, usedSlots, maxSlots, attempt)
    attempt = attempt or 1

    if not SendMailFrame or not SendMailFrame:IsShown() or type(items) ~= "table" then
        return
    end

    local freeSlots = math.max(0, (maxSlots or (ATTACHMENTS_MAX_SEND or 12)) - (usedSlots or 0))
    local overflowEntries = {}
    local validSeen = 0
    local waitingOnLocks = false

    for _, item in ipairs(items) do
        local bag = item and item.bagID
        local slot = item and item.slotID
        local itemInfo = getContainerItemInfoCompat(bag, slot)
        local itemLink = getContainerItemLinkCompat(bag, slot)

        if bag ~= nil and slot ~= nil and itemInfo and itemLink then
            validSeen = validSeen + 1
            if validSeen > freeSlots then
                if itemInfo.isLocked then
                    waitingOnLocks = true
                else
                    table.insert(overflowEntries, {
                        bagID = bag,
                        slotID = slot,
                    })
                end
            end
        end
    end

    if #overflowEntries > 0 then
        addon:Debug("Baganator deferred overflow attempt " .. tostring(attempt) .. ": queueing " .. tostring(#overflowEntries) .. " item(s).")
        self:HandleOverflow(overflowEntries, freeSlots, 0)
        return
    end

    if waitingOnLocks and attempt < 5 then
        addon:Debug("Baganator deferred overflow attempt " .. tostring(attempt) .. ": waiting on locked items.")
        C_Timer.After(0.15, function()
            module:QueueOverflowDeferred(items, usedSlots, maxSlots, attempt + 1)
        end)
    else
        addon:Debug("Baganator deferred overflow attempt " .. tostring(attempt) .. ": nothing queueable.")
    end
end

function module:EnsureHook()
    if self.ancestorHookApplied or type(CallMethodOnNearestAncestor) ~= "function" then
        return
    end

    local originalCallMethodOnNearestAncestor = CallMethodOnNearestAncestor
    CallMethodOnNearestAncestor = function(frame, methodName, ...)
        local shouldInspect = SendMailFrame and SendMailFrame:IsShown()
            and (methodName == "TransferCategory" or methodName == "TransferSection")
        local items
        local usedSlots, maxSlots

        if shouldInspect then
            local ancestor = getNearestAncestorWithMethod(frame, methodName)
            usedSlots, maxSlots = getUsedAttachmentSlots()

            if methodName == "TransferCategory" then
                local sourceKey = ...
                local layout = ancestor and ancestor.layoutsBySourceKey and ancestor.layoutsBySourceKey[sourceKey] or nil
                if layout and layout.SearchMonitor and layout.SearchMonitor.GetMatches then
                    items = layout.SearchMonitor:GetMatches()
                end
            elseif methodName == "TransferSection" then
                items = getBaganatorSectionMatches(ancestor, ...)
            end

            addon:Debug("Baganator ancestor transfer: method=" .. tostring(methodName) .. ", matches=" .. tostring(items and #items or 0) .. ", used=" .. tostring(usedSlots) .. ", max=" .. tostring(maxSlots))
        end

        local results = {originalCallMethodOnNearestAncestor(frame, methodName, ...)}

        if shouldInspect and items then
            C_Timer.After(0.1, function()
                module:QueueOverflowDeferred(items, usedSlots, maxSlots, 1)
            end)
        end

        return unpack(results)
    end

    self.ancestorHookApplied = true
end

function module:OnInitialize()
    self:EnsureHook()
end

addon:RegisterModule("BaganatorCompat", module)
