-- Detect APIs rather than project IDs: beta clients can expose a mixed API set.
EasyMail = EasyMail or {}
local compat = {}
EasyMail.compat = compat

compat.backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
compat.GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
compat.GetItemFamily = C_Item and C_Item.GetItemFamily or GetItemFamily

-- Check before comparing, branching on, or transforming values from restricted APIs.
-- Classic clients do not expose the secret-value API.
function compat.IsPublicValue(value)
    return not issecretvalue or not issecretvalue(value)
end

function compat.GetTargetName()
    local exists = UnitExists("target")
    if not compat.IsPublicValue(exists) or not exists then return nil end
    local isPlayer = UnitIsPlayer("target")
    if not compat.IsPublicValue(isPlayer) or not isPlayer then return nil end
    local isSelf = UnitIsUnit("target", "player")
    if not compat.IsPublicValue(isSelf) or isSelf then return nil end
    local name, realm = UnitName("target")
    if not compat.IsPublicValue(name) or not compat.IsPublicValue(realm) then return nil end
    if not name or name == "" then return nil end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

function compat.GetContainerItemInfo(bag, slot)
    if bag == nil or slot == nil then
        return nil
    end
    if C_Container and C_Container.GetContainerItemInfo then
        return C_Container.GetContainerItemInfo(bag, slot)
    end
    if not GetContainerItemInfo then
        return nil
    end
    -- An 'and' expression discards all but the first Lua return value.
    local texture, count, locked = GetContainerItemInfo(bag, slot)
    if not texture then
        return nil
    end
    return { iconFileID = texture, stackCount = count, isLocked = locked }
end

function compat.GetLastBagIndex()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

function compat.GetContainerLocation(button)
    if not button then
        return nil, nil
    end
    local parent = button.GetParent and button:GetParent()
    local bag = button.GetBagID and button:GetBagID() or button.bagID
    if bag == nil and parent then
        bag = parent.bagID
        if bag == nil and parent.GetID then
            bag = parent:GetID()
        end
    end
    local slot = button.slotIndex or button.slot
    if slot == nil and button.GetID then
        slot = button:GetID()
    end
    return bag, slot
end

function compat.RegisterOptionalEvent(frame, event)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
        return false
    end
    return pcall(frame.RegisterEvent, frame, event)
end
