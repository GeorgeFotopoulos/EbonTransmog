-- EbonTransmog: modules/ui/PreviewModel.lua
-- DressUpModel wrapper with TryOn preview, drag-rotate, and mouse-wheel zoom.

EbonTransmog = EbonTransmog or {}
local Preview = {}
EbonTransmog.PreviewModel = Preview

local DEFAULT_FACING = 0.45

local function GetModelFacing(model)
    if model.GetFacing then
        return model:GetFacing()
    end
    if model.GetRotation then
        return model:GetRotation()
    end
    return DEFAULT_FACING
end

local function SetModelFacing(model, facing)
    if model.SetRotation then
        model:SetRotation(facing)
    elseif model.SetFacing then
        model:SetFacing(facing)
    end
end

local function ResetModel(model, preserveView)
    if not model then return end

    local facing = preserveView and GetModelFacing(model) or DEFAULT_FACING
    local zoom = preserveView and (model.zoomScale or 1.0) or 1.0

    if model.Undress then
        model:Undress()
    end
    model:SetUnit("player")
    if model.RefreshUnit then
        model:RefreshUnit()
    end

    SetModelFacing(model, facing)
    model.zoomScale = zoom
    model:SetScale(zoom)
end

function Preview.Attach(parent, width, height)
    width = width or 220
    height = height or 320

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, height)

    local model = CreateFrame("DressUpModel", nil, holder)
    model:SetAllPoints(holder)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model.zoomScale = 1.0
    holder.model = model

    model:SetScript("OnMouseWheel", function(self, delta)
        local step = 0.1
        self.zoomScale = self.zoomScale + (delta * step)
        self.zoomScale = math.max(0.5, math.min(2.0, self.zoomScale))
        self:SetScale(self.zoomScale)
    end)

    model.isDragging = false
    model.lastX = 0

    model:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not IsControlKeyDown() and not IsShiftKeyDown() then
            self.isDragging = true
            self.lastX = select(1, GetCursorPosition())
        end
    end)

    model:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self.isDragging = false
        end
    end)

    model:SetScript("OnUpdate", function(self)
        if not self.isDragging then return end
        local x = select(1, GetCursorPosition())
        local dx = x - self.lastX
        local speed = 0.005
        if self.GetFacing then
            self:SetFacing(self:GetFacing() + dx * speed)
        elseif self.GetRotation then
            self:SetRotation(self:GetRotation() + dx * speed)
        end
        self.lastX = x
    end)

    function holder:Reset()
        ResetModel(self.model)
    end

    function holder:PreviewItem(itemId)
        if not itemId then
            self:Reset()
            return
        end
        if self.model.TryOn then
            self.model:TryOn(itemId)
        end
    end

    function holder:PreviewOutfit(slotsBySub)
        ResetModel(self.model, true)
        if not slotsBySub or not self.model.TryOn then return end
        local ordered = {}
        for _, itemId in pairs(slotsBySub) do
            table.insert(ordered, itemId)
        end
        table.sort(ordered)
        for _, itemId in ipairs(ordered) do
            self.model:TryOn(itemId)
        end
    end

    function holder:PreviewItems(itemIds)
        ResetModel(self.model)
        if not itemIds or not self.model.TryOn then return end
        for _, id in ipairs(itemIds) do
            self.model:TryOn(id)
        end
    end

    holder:Reset()
    return holder
end
