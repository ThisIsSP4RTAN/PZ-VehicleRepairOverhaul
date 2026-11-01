---@diagnostic disable: undefined-field, param-type-mismatch
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISInventoryTransferAction"
-- Nearby materials are only exposed through the virtual inventory used while
-- building repair options. Consumption remains VRO's normal player-inventory
-- timed action/server-command path after the selected items are staged.
local VRO = require "VRO/Core"

VRO.NearbyInventory = VRO.NearbyInventory or {}
local NearbyInventory = VRO.NearbyInventory

local function _enabled()
    return VRO.UseNearbyContainers and VRO.UseNearbyContainers() or false
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

local function _canReach(fromSq, toSq)
    if fromSq == toSq then return true end
    if not (fromSq and toSq and fromSq.canReachTo) then return false end
    local ok, reach = pcall(function() return fromSq:canReachTo(toSq) end)
    return (ok and reach) and true or false
end

-- Build a short-lived, de-duplicated snapshot. It intentionally has no cache:
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

    local groundOk = _searchGround()
    for x = px - 1, px + 1 do
        for y = py - 1, py + 1 do
            local nearbySquare = cell:getGridSquare(x, y, pz)
            if nearbySquare and _canReach(square, nearbySquare) then
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

                if groundOk then
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

local function _playerInventory(playerObj)
    if not playerObj then return nil end
    local valid, getInventory = pcall(function() return playerObj.getInventory end)
    if not (valid and getInventory) then return nil end
    local ok, inventory = pcall(function() return playerObj:getInventory() end)
    return ok and inventory or nil
end

local function _itemContainer(item)
    if not item then return false, nil end
    local valid, getContainer = pcall(function() return item.getContainer end)
    if not (valid and getContainer) then return false, nil end
    local ok, container = pcall(function() return item:getContainer() end)
    return ok, container
end

local function _containerSquare(container)
    if not container then return nil end
    local ok, parent = pcall(function() return container.getParent and container:getParent() end)
    if ok and parent and parent.getSquare then
        local ok2, sq = pcall(function() return parent:getSquare() end)
        if ok2 and sq then return sq end
    end
    local ok3, grid = pcall(function() return container.getSourceGrid and container:getSourceGrid() end)
    if ok3 and grid then return grid end
    return nil
end

local function _walkToSquareOnce(playerObj, sq)
    if not sq then return false end
    if luautils and luautils.walkAdj then
        local ok, reached = pcall(luautils.walkAdj, playerObj, sq, true)
        return (ok and reached) and true or false
    end
    return false
end

local function _queueTake(playerObj, item, playerInv)
    local cont = item.getContainer and item:getContainer() or nil
    if cont then
        local ok, action = pcall(function()
            return ISInventoryTransferAction:new(playerObj, item, cont, playerInv)
        end)
        if ok and action and pcall(ISTimedActionQueue.add, action) then return true end
    end
    -- No resolvable container (rare): fall back to the engine grab on SP/host.
    local wi = item.getWorldItem and item:getWorldItem() or nil
    if wi and not isClient() and ISGrabItemAction then
        local time = 50
        if ISWorldObjectContextMenu and ISWorldObjectContextMenu.grabItemTime then
            local okT, t = pcall(ISWorldObjectContextMenu.grabItemTime, playerObj, wi)
            if okT and tonumber(t) then time = t end
        end
        if pcall(function() ISTimedActionQueue.add(ISGrabItemAction:new(playerObj, wi, time)) end) then return true end
    end
    if ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.transferIfNeeded then
        return pcall(ISInventoryPaneContextMenu.transferIfNeeded, playerObj, item)
    end
    return false
end

-- Grouping key + walk square for an item: a loose item groups by its own world
-- square; a container item groups by its container (walking to that container's
-- owning object). Items sharing a key share one walk.
local function _takeKey(item)
    local wi = item.getWorldItem and item:getWorldItem() or nil
    if wi then
        local sq = (wi.getSquare and wi:getSquare()) or nil
        return sq, sq
    end
    local cont = item.getContainer and item:getContainer() or nil
    if cont then
        return cont, _containerSquare(cont)
    end
    return nil, nil
end

-- Walk to each distinct pickup location once, then queue every take for that
-- location consecutively so same-type items merge into one continuous pickup.
-- Items with no resolvable location fall back to a plain take. Returns true
-- only if every take was queued.
local function _queueTakeItems(playerObj, items)
    local playerInv = _playerInventory(playerObj)
    if not playerInv then return false end

    local order, groups, loose, seen = {}, {}, {}, {}
    for i = 1, #items do
        local item = items[i]
        local itemValid, source = _itemContainer(item)
        -- Local dedup only: skip items already in the main inventory and any the
        -- same pass already listed. Nothing persists between passes, so an
        -- interrupted repair never blocks the next attempt from re-staging.
        if item and itemValid and source ~= playerInv and not seen[item] then
            seen[item] = true
            local key, walkSq = _takeKey(item)
            if key == nil then
                loose[#loose + 1] = item
            else
                local g = groups[key]
                if not g then
                    g = { walkSq = walkSq, items = {} }
                    groups[key] = g
                    order[#order + 1] = key
                end
                g.items[#g.items + 1] = item
            end
        end
    end

    local allOk = true
    local function take(it)
        if not _queueTake(playerObj, it, playerInv) then
            allOk = false
        end
    end

    for i = 1, #order do
        local g = groups[order[i]]
        _walkToSquareOnce(playerObj, g.walkSq)
        for j = 1, #g.items do take(g.items[j]) end
    end
    for i = 1, #loose do take(loose[i]) end
    return allOk
end

function NearbyInventory.queueItemToPlayer(playerObj, item)
    local playerInv = _playerInventory(playerObj)
    local itemValid, source = _itemContainer(item)
    if not (playerInv and itemValid) then return false end
    if source == playerInv then return true end
    if not (ISTimedActionQueue and ISTimedActionQueue.add) then return false end
    return _queueTakeItems(playerObj, { item })
end

function NearbyInventory.stageBundlesThen(playerObj, bundles, onReady)
    if not (playerObj and bundles and onReady) then return false end
    if not ISTimedActionQueue then return false end

    local items = {}
    for i = 1, #bundles do
        local bundle = bundles[i]
        if bundle then
            for j = 1, #bundle do
                local entry = bundle[j]
                if entry and entry.item and not _containsPlayerItem(playerObj, entry.item) then
                    items[#items + 1] = entry.item
                end
            end
        end
    end

    if #items > 0 and not _queueTakeItems(playerObj, items) then return false end
    onReady()
    return true
end

return NearbyInventory