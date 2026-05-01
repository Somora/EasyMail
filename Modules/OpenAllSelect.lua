local addon = EasyMail
local module = {}

module.selection = {}

local function getOpenAllModule()
    return addon.modules and addon.modules.OpenAll or nil
end

local function getInboxCount()
    return GetInboxNumItems() or 0
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

function module:GetSelectedMailCount()
    local count = 0
    for mailIndex, isSelected in pairs(self.selection) do
        if isSelected and mailIndex <= getInboxCount() then
            count = count + 1
        end
    end
    return count
end

function module:IsMailSelected(mailIndex)
    return self.selection and self.selection[mailIndex] == true
end

function module:ClearSelection()
    self.selection = {}
    self:UpdateVisibleSelections()

    local openAll = getOpenAllModule()
    if openAll then
        openAll:UpdateButtonState()
    end
end

function module:ToggleSelection(mailIndex)
    if not mailIndex or mailIndex < 1 or mailIndex > getInboxCount() then
        return
    end

    if self.selection[mailIndex] then
        self.selection[mailIndex] = nil
    else
        self.selection[mailIndex] = true
    end

    self:UpdateVisibleSelections()

    local openAll = getOpenAllModule()
    if openAll then
        openAll:UpdateButtonState()
    end
end

function module:GetRowCheckbox(displayIndex)
    local itemFrame, rowButton = getDisplayMailFrames(displayIndex)
    local parent = itemFrame or rowButton
    if not parent then
        return nil
    end

    if parent.easyMailSelectCheckbox then
        return parent.easyMailSelectCheckbox
    end

    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetSize(18, 18)
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", -12, -12)
    checkbox:SetScript("OnClick", function(selfCheckbox)
        if selfCheckbox.mailIndex then
            module:ToggleSelection(selfCheckbox.mailIndex)
        end
    end)
    checkbox:SetScript("OnEnter", function(selfCheckbox)
        GameTooltip:SetOwner(selfCheckbox, "ANCHOR_RIGHT")
        GameTooltip:AddLine("EasyMail Select")
        GameTooltip:AddLine("Toggle this mail for Open Sel / Return Sel.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    checkbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    parent.easyMailSelectCheckbox = checkbox
    return checkbox
end

function module:UpdateVisibleSelections()
    local perPage = INBOXITEMS_TO_DISPLAY or 7
    local page = InboxFrame and InboxFrame.pageNum or 1

    for displayIndex = 1, perPage do
        local checkbox = self:GetRowCheckbox(displayIndex)
        if checkbox then
            local mailIndex = displayIndex + ((page - 1) * perPage)
            if mailIndex > getInboxCount() then
                checkbox.mailIndex = nil
                checkbox:SetChecked(false)
                checkbox:Hide()
            else
                checkbox.mailIndex = mailIndex
                checkbox:SetChecked(self:IsMailSelected(mailIndex))
                checkbox:Show()
            end
        end
    end
end

addon:RegisterModule("OpenAllSelect", module)
