---@diagnostic disable: undefined-field, param-type-mismatch
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISInventoryTransferAction"
-- Nearby materials are only exposed through the virtual inventory used while
-- building repair options.  Consumption remains VRO's normal player-inventory
-- timed action/server-command path after the selected items are staged.
local VRO = require "VRO/Core"

VRO.NearbyInventory = VRO.NearbyInventory or {}
local NearbyInventory = VRO.NearbyInventory

local function _enabled()
    return VRO.UseNearbyContainers and VRO.UseNearbyContainers() or false
end

local function _radius()
    return VRO.GetNearbySearchRadius and VRO.GetNearbySearchRadius() or 2
end

local function _searchGround()
    return VRO.SearchNearbyGroundItems and VRO.SearchNearbyGroundItems() or false
end

local function _safeItems(container)
    if not (container and container.getItems) then return nil end
    local ok, items = pcall(function() return container:getItems() end)
    return ok and items or nil
end

local function _isAccessible(container)
    if not (container and container.isAccessible) then return true end
    local ok, accessible = pcall(function() return container:isAccessible() end)
    return not ok or accessible ~= false
end

local function _addContainerItems(container, add)
    if not _isAccessible(container) then return end
    local items = _safeItems(container)
    if not (items and items.size) then return end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        add(item)
    end
end

-- Build a short-lived, de-duplicated snapshot.  It intentionally has no cache:
-- world containers can change between context-menu opens in multiplayer.
local function _collect(playerObj)
    local items, seen = {}, {}
    local function add(item)
        if not item or seen[item] then return end
        seen[item] = true
        items[#items + 1] = item
        if item.getInventory then
            local ok, nested = pcall(function() return item:getInventory() end)
            if ok and nested then _addContainerItems(nested, add) end
        end
    end

    local playerInv = playerObj and playerObj:getInventory()
    _addContainerItems(playerInv, add)
    if not (_enabled() and playerObj and getCell) then return items end

    local square = playerObj:getSquare()
    if not square then return items end
    local px, py, pz = square:getX(), square:getY(), square:getZ()
    local cell = getCell()
    if not cell then return items end

    local radius = _radius()
    for x = px - radius, px + radius do
        for y = py - radius, py + radius do
            local nearbySquare = cell:getGridSquare(x, y, pz)
            if nearbySquare then
                -- World-object containers (crates, cupboards, vehicle storage, etc.).
                local objects = nearbySquare:getObjects()
                if objects and objects.size then
                    for oi = 0, objects:size() - 1 do
                        local object = objects:get(oi)
                        if object and object.getContainer then
                            local ok, container = pcall(function() return object:getContainer() end)
                            if ok and container then _addContainerItems(container, add) end
                        end
                    end
                end

                if _searchGround() then
                    local worldItems = nearbySquare:getWorldObjects()
                    if worldItems and worldItems.size then
                        for wi = 0, worldItems:size() - 1 do
                            local worldItem = worldItems:get(wi)
                            if worldItem and worldItem:getItem() then add(worldItem:getItem()) end
                        end
                    end
                end
            end
        end
    end
    return items
end

local function _containsPlayerItem(playerObj, target)
    if not (playerObj and target) then return false end
    -- _collect contains nearby entries when enabled, so inspect the player's
    -- recursive inventory directly for this ownership check.
    local seen = {}
    local function contains(container)
        local entries = _safeItems(container)
        if not (entries and entries.size) then return false end
        for i = 0, entries:size() - 1 do
            local item = entries:get(i)
            if item == target then return true end
            if item and not seen[item] then
                seen[item] = true
                if item.getInventory then
                    local ok, nested = pcall(function() return item:getInventory() end)
                    if ok and nested and contains(nested) then return true end
                end
            end
        end
        return false
    end
    return contains(playerObj:getInventory())
end

local function _virtualInventory(playerObj)
    local snapshot = _collect(playerObj)
    local proxy = {}

    local function each(predicate)
        for i = 1, #snapshot do
            local item = snapshot[i]
            if predicate(item) then return item end
        end
        return nil
    end

    function proxy:getAllTypeRecurse(fullType, out)
        for i = 1, #snapshot do
            local item = snapshot[i]
            if item and item.getFullType and item:getFullType() == fullType then out:add(item) end
        end
    end
    function proxy:getFirstTagRecurse(tag)
        return each(function(item) return item and item.hasTag and item:hasTag(tag) end)
    end
    function proxy:containsTagRecurse(tag) return self:getFirstTagRecurse(tag) ~= nil end
    function proxy:containsTag(tag) return self:getFirstTagRecurse(tag) ~= nil end
    function proxy:getFirstEvalRecurse(predicate)
        return each(function(item) return predicate(item) end)
    end
    function proxy:getBestEvalRecurse(predicate, comparator)
        local best = nil
        for i = 1, #snapshot do
            local item = snapshot[i]
            if predicate(item) and (not best or comparator(item, best) > 0) then best = item end
        end
        return best
    end
    function proxy:getItems()
        local out = ArrayList.new()
        for i = 1, #snapshot do out:add(snapshot[i]) end
        return out
    end
    return proxy
end

function NearbyInventory.getEffectiveInventory(playerObj)
    if not _enabled() then return playerObj:getInventory() end
    return _virtualInventory(playerObj)
end

-- Equipment must reach the main inventory before normal PZ equip actions run.
-- Consumable bundles below separately leave items in carried bags alone.
NearbyInventory._queued = NearbyInventory._queued or setmetatable({}, { __mode = "k" })
if Events and Events.OnTick and not NearbyInventory._clearQueuedOnTick then
    NearbyInventory._clearQueuedOnTick = true
    Events.OnTick.Add(function()
        NearbyInventory._queued = setmetatable({}, { __mode = "k" })
    end)
end
function NearbyInventory.queueItemToPlayer(playerObj, item)
    if not item or item:getContainer() == playerObj:getInventory() then return true end
    if NearbyInventory._queued[item] then return true end

    local source = item:getContainer()
    if source then
        local ok, action = pcall(function()
            return ISInventoryTransferAction:new(playerObj, item, source, playerObj:getInventory(), 10)
        end)
        if not (ok and action) then return false end
        NearbyInventory._queued[item] = true
        ISTimedActionQueue.add(action)
        return true
    end

    -- Loose ground items need the game's normal pickup handling.
    if not (ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.transferIfNeeded) then return false end
    NearbyInventory._queued[item] = true
    local ok = pcall(ISInventoryPaneContextMenu.transferIfNeeded, playerObj, item)
    if not ok then NearbyInventory._queued[item] = nil end
    return ok
end

function NearbyInventory.queueBundleToPlayer(playerObj, bundle)
    if not bundle then return true end
    for i = 1, #bundle do
        local entry = bundle[i]
        -- VRO's normal recursive player inventory logic already consumes items
        -- from carried bags.  Only external selections need staging.
        if entry and entry.item and not _containsPlayerItem(playerObj, entry.item)
            and not NearbyInventory.queueItemToPlayer(playerObj, entry.item) then
            return false
        end
    end
    return true
end

local function _bundlesAreInPlayerInventory(playerObj, bundles)
    local inventory = playerObj and playerObj:getInventory()
    if not inventory then return false end

    local required = {}
    for i = 1, #bundles do
        local bundle = bundles[i]
        if bundle then
            for j = 1, #bundle do
                local entry = bundle[j]
                local item = entry and entry.item
                local fullType = item and item.getFullType and item:getFullType()
                if fullType then
                    required[fullType] = (required[fullType] or 0) + (entry.takeUses or 1)
                end
            end
        end
    end

    for fullType, needed in pairs(required) do
        local items = ArrayList.new()
        inventory:getAllTypeRecurse(fullType, items)
        local available = 0
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item then
                if item.getDrainableUsesInt then
                    available = available + item:getDrainableUsesInt()
                elseif item.getCurrentUses then
                    available = available + item:getCurrentUses()
                else
                    available = available + 1
                end
                if available >= needed then break end
            end
        end
        if available < needed then return false end
    end
    return true
end

local function _bundleSummary(bundles)
    local required, names = {}, {}
    for i = 1, #bundles do
        local bundle = bundles[i]
        if bundle then
            for j = 1, #bundle do
                local entry = bundle[j]
                local item = entry and entry.item
                local fullType = item and item.getFullType and item:getFullType()
                if fullType then
                    required[fullType] = (required[fullType] or 0) + (entry.takeUses or 1)
                end
            end
        end
    end
    for fullType, uses in pairs(required) do
        names[#names + 1] = fullType .. "=" .. tostring(uses)
    end
    table.sort(names)
    return table.concat(names, ", ")
end

local StageBundlesAction = ISBaseTimedAction:derive("VRO_StageBundlesAction")

function StageBundlesAction:isValid()
    return self.character ~= nil
end

function StageBundlesAction:perform()
    local ready = _bundlesAreInPlayerInventory(self.character, self.bundles)
    ISBaseTimedAction.perform(self)

    if ready then
        print("[VRO][Nearby] Materials staged; queuing repair: " .. _bundleSummary(self.bundles))
        -- The timed-action queue is still finalizing this action during
        -- perform().  Adding the path/repair on the next tick avoids losing
        -- that handoff when the queue removes its current action.
        if Events and Events.OnTick then
            local onReady = self.onReady
            local function deferRepairQueue()
                Events.OnTick.Remove(deferRepairQueue)
                print("[VRO][Nearby] Handing staged materials to repair queue")
                onReady()
            end
            Events.OnTick.Add(deferRepairQueue)
        else
            self.onReady()
        end
    elseif self.attempts < 3 then
        -- A transfer can be deferred by movement or another queued action.
        -- Put a fresh check behind its retry rather than racing it on OnTick.
        for i = 1, #self.bundles do
            NearbyInventory.queueBundleToPlayer(self.character, self.bundles[i])
        end
        ISTimedActionQueue.add(StageBundlesAction:new(
            self.character, self.bundles, self.onReady, self.attempts + 1))
    else
        print("[VRO][Nearby] Materials did not finish staging: " .. _bundleSummary(self.bundles))
    end
end

function StageBundlesAction:new(character, bundles, onReady, attempts)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.bundles = bundles
    o.onReady = onReady
    o.attempts = attempts or 0
    o.maxTime = 1
    o.stopOnWalk = false
    o.stopOnRun = false
    return o
end

-- transferIfNeeded queues normal inventory actions.  Insert a small action
-- after them, then enqueue the dependent repair only after all selected items
-- have reached the player's inventory.
function NearbyInventory.stageBundlesThen(playerObj, bundles, onReady)
    if not (playerObj and bundles and onReady) then return false end
    for i = 1, #bundles do
        if not NearbyInventory.queueBundleToPlayer(playerObj, bundles[i]) then return false end
    end
    if not ISTimedActionQueue then return false end
    ISTimedActionQueue.add(StageBundlesAction:new(playerObj, bundles, onReady))
    return true
end

return NearbyInventory
