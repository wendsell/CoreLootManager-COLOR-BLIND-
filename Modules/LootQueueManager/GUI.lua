local _, CLM = ...

-- Libs
local ScrollingTable = LibStub("ScrollingTable")
local AceGUI = LibStub("AceGUI-3.0")

local LOG = CLM.LOG
local UTILS = CLM.UTILS
local MODULES = CLM.MODULES
local CONSTANTS = CLM.CONSTANTS
-- local RESULTS = CLM.CONSTANTS.RESULTS
local GUI = CLM.GUI

local EventManager = MODULES.EventManager
local LootQueueManager = MODULES.LootQueueManager

local RightClickMenu

local LootQueueGUI = {}

local function InitializeDB(self)
    local db = MODULES.Database:GUI()
    if not db.lootQueue then
        db.lootQueue = { }
    end
    self.db = db.lootQueue
end

local function StoreLocation(self)
    self.db.location = { self.top:GetPoint() }
end

local function RestoreLocation(self)
    if self.db.location then
        self.top:ClearAllPoints()
        self.top:SetPoint(self.db.location[3], self.db.location[4], self.db.location[5])
    end
end

local function ST_GetItemLink(row)
    return row.cols[1].value
end

local function ST_GetItemId(row)
    return row.cols[2].value
end

local function ST_GetItemSeq(row)
    return row.cols[3].value
end

function LootQueueGUI:Initialize()
    LOG:Trace("LootQueueGUI:Initialize()")
    InitializeDB(self)

    self.tooltip = CreateFrame("GameTooltip", "CLMLootQueueGUIDialogTooltip", UIParent, "GameTooltipTemplate")

    RightClickMenu = CLM.UTILS.GenerateDropDownMenu(
        {
            {
                title = "Auction item",
                func = (function()
                    local rowData = self.st:GetRow(self.st:GetSelection())
                    if not rowData or not rowData.cols then return end
                    EventManager:DispatchEvent("CLM_AUCTION_WINDOW_FILL", {
                        link = ST_GetItemLink(rowData),
                        start = false
                    })
            end),
                trustedOnly = true,
                color = "00cc00"
            },
            {
                title = "Remove item",
                func = (function()
                    local rowData = self.st:GetRow(self.st:GetSelection())
                    if not rowData or not rowData.cols then return end
                    LootQueueManager:Remove(ST_GetItemSeq(rowData))
                end),
                trustedOnly = true,
                color = "cc0000"
            },
            {
                separator = true,
                trustedOnly = true,
            },
            {
                title = "Remove all",
                func = (function()
                    LootQueueManager:Wipe()
                end),
                trustedOnly = true,
                color = "cc0000"
            }
        },
        CLM.MODULES.ACL:CheckLevel(CONSTANTS.ACL.LEVEL.ASSISTANT),
        CLM.MODULES.ACL:CheckLevel(CONSTANTS.ACL.LEVEL.MANAGER)
    )

    self:Create()
    EventManager:RegisterWoWEvent({"PLAYER_LOGOUT"}, (function(...) StoreLocation(self) end))
    self:RegisterSlash()
    self._initialized = true
    self:Refresh()
end

local ROW_HEIGHT = 18
local MIN_HEIGHT = 105

local function CreateLootDisplay(self)
    local columns = {
        {name = "",  width = 200},
    }
    local LootQueueGroup = AceGUI:Create("SimpleGroup")
    LootQueueGroup:SetLayout("Flow")
    LootQueueGroup:SetWidth(265)
    LootQueueGroup:SetHeight(MIN_HEIGHT)
    self.LootQueueGroup = LootQueueGroup
    -- Standings
    self.st = ScrollingTable:CreateST(columns, 1, ROW_HEIGHT, nil, LootQueueGroup.frame)
    self.st:EnableSelection(true)
    self.st.frame:SetPoint("TOPLEFT", LootQueueGroup.frame, "TOPLEFT", 0, 0)
    self.st.frame:SetBackdropColor(0.1, 0.1, 0.1, 0.1)

    -- OnEnter handler -> on hover
    local OnEnterHandler = (function (rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
        local status = self.st.DefaultEvents["OnEnter"](rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
        local rowData = self.st:GetRow(realrow)
        if not rowData or not rowData.cols then return status end
        local tooltip = self.tooltip
        if not tooltip then return end
        local itemId = ST_GetItemId(rowData)
        local itemString = "item:" .. tonumber(itemId)
        tooltip:SetOwner(rowFrame, "ANCHOR_TOPRIGHT")
        tooltip:SetHyperlink(itemString)
        tooltip:Show()
        return status
    end)
    -- OnLeave handler -> on hover out
    local OnLeaveHandler = (function (rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
        local status = self.st.DefaultEvents["OnLeave"](rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
        self.tooltip:Hide()
        return status
    end)
    -- end
    -- OnClick handler
    local OnClickHandler = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, button, ...)
        local rightButton = (button == "RightButton")
        local status
        local selected = self.st:GetSelection()
        if selected ~= realrow then
            if (row or realrow) then -- disables sorting click
                status = self.st.DefaultEvents["OnClick"](rowFrame, cellFrame, data, cols, row, realrow, column, table, rightButton and "LeftButton" or button, ...)
            end
        end
        if rightButton then
            UTILS.LibDD:CloseDropDownMenus()
            UTILS.LibDD:ToggleDropDownMenu(1, nil, RightClickMenu, cellFrame, -20, 0)
        else
            if IsAltKeyDown() then
                local rowData = self.st:GetRow(realrow)
                if not rowData or not rowData.cols then return status end
                EventManager:DispatchEvent("CLM_AUCTION_WINDOW_FILL", {
                    link = ST_GetItemLink(rowData),
                    start = false
                })
            end
        end
        return status
    end
    -- end

    self.st:RegisterEvents({
        OnEnter = OnEnterHandler,
        OnLeave = OnLeaveHandler,
        OnClick = OnClickHandler
    })

    return LootQueueGroup
end

function LootQueueGUI:Create()
    LOG:Trace("LootQueueGUI:Create()")
    -- Main Frame
    local f = AceGUI:Create("Frame")
    f:SetTitle("Loot Queue")
    f:SetStatusText("")
    f:SetLayout("Table")
    f:SetUserData("table", { columns = {0, 0}, alignV =  "top" })
    f:EnableResize(false)
    f:SetWidth(265)
    f:SetHeight(MIN_HEIGHT)
    self.top = f

    f:AddChild(CreateLootDisplay(self))
    RestoreLocation(self)
    -- Hide by default
    -- f:Hide()
    MODULES.ConfigManager:RegisterUniversalExecutor("lqg", "Loot Queue GUI", self)
end

function LootQueueGUI:Refresh(visible)
    LOG:Trace("LootQueueGUI:Refresh()")
    if not self._initialized then return end
    if visible and not self.top.frame:IsVisible() then return end

    local data = {}
    local rowId = 1
    local queue = LootQueueManager:GetQueue()
    if #queue > 0 then
        for seq, item in ipairs(queue) do
            local row = {
                cols = {
                    { value = item.link },
                    { value = item.id },
                    { value = seq }
                }
            }
            data[rowId] = row
            rowId = rowId + 1
        end
        local rows = (#queue < 10) and #queue or 10
        local previousRows = self.previousRows or rows
        self.previousRows = rows
        local height = MIN_HEIGHT + ROW_HEIGHT*(rows-1)
        local _, _, point, x, y = self.top:GetPoint()
        self.top:SetHeight(height)
        self.LootQueueGroup:SetHeight(height)
        self.st:SetDisplayRows(rows, ROW_HEIGHT)
        if (rows > 1) and (rows ~= previousRows) then
            -- makes it grow down instead of omnidirectional
            self.top:SetPoint(point, x, y - ROW_HEIGHT/2)
        end
    end
    self.st:SetData(data)
end

function LootQueueGUI:Toggle()
    LOG:Trace("LootQueueGUI:Toggle()")
    if not self._initialized then return end
    if self.top.frame:IsVisible() then
        self.top.frame:Hide()
    else
        self:Refresh()
        self.top.frame:Show()
    end
end

function LootQueueGUI:RegisterSlash()
    local options = {
        queue = {
            type = "execute",
            name = "Loot Queue",
            desc = "Toggle Loot Queue window display",
            handler = self,
            func = "Toggle",
        }
    }
    MODULES.ConfigManager:RegisterSlash(options)
end

GUI.LootQueue = LootQueueGUI