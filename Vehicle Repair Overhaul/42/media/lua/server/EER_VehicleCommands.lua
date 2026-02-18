---@diagnostic disable: param-type-mismatch
if isClient() then return end

local EER_VehicleCommands = {}
local EER_Commands = {}

EER_VehicleCommands.wantNoise = getDebug() or false
local function noise(msg)
  if EER_VehicleCommands.wantNoise then
--  print('EER_VehicleCommands: '..msg)
  end
end

local function _partMaxCondition(part)
  if not part then return 100 end
  if part.getConditionMax then
    local ok, val = pcall(function() return part:getConditionMax() end)
    if ok and type(val) == "number" and val > 0 then return val end
  end

  local inv = part.getInventoryItem and part:getInventoryItem() or nil
  if inv and inv.getConditionMax then
    local ok, val = pcall(function() return inv:getConditionMax() end)
    if ok and type(val) == "number" and val > 0 then return val end
  end
  return 100
end

local function _removeFullTypeCount(player, fullType, count)
  if not (player and fullType and count and count > 0) then return end
  local inv = player:getInventory()
  if not inv then return end
  local coll = ArrayList.new()
  inv:getAllTypeRecurse(fullType, coll)
  local remain = count
  for i = 0, coll:size() - 1 do
    if remain <= 0 then break end
    local it  = coll:get(i)
    local con = it and it:getContainer() or nil
    if con then
      con:Remove(it)
      if sendRemoveItemFromContainer then
        sendRemoveItemFromContainer(con, it)
      end
      remain = remain - 1
    end
  end
end

function EER_Commands.rebuildEngine(player, args)
  local vehicle = getVehicleById(args.vehicleId)
  if not vehicle then return end

  local part = vehicle:getPartById("Engine")
  if not part then return end

  local quality = tonumber(args.targetQuality) or 100
  if quality < 0 then quality = 0 elseif quality > 100 then quality = 100 end

  local loud, force = nil, nil

  if vehicle.getEngineLoudness then
    local ok, v = pcall(function() return vehicle:getEngineLoudness() end)
    if ok then loud = v end
  end
  if vehicle.getEnginePower then
    local ok, v = pcall(function() return vehicle:getEnginePower() end)
    if ok then force = v end
  end

  if (not loud or not force) then
    local scr = vehicle and vehicle:getScript() or nil
    if scr then
      if (not loud) and scr.getEngineLoudness then
        local ok, v = pcall(function() return scr:getEngineLoudness() end)
        if ok then loud = v end
      end
      if (not force) and scr.getEngineForce then
        local ok, v = pcall(function() return scr:getEngineForce() end)
        if ok then force = v end
      end
    end
  end

  loud  = tonumber(loud)  or 120
  force = tonumber(force) or 0

  pcall(function() vehicle:setEngineFeature(quality, loud, force) end)

  local target = math.min(100, _partMaxCondition(part))
  pcall(function() part:setCondition(target) end)

  local need = tonumber(args.consumeParts) or 0
  if need > 0 then
    _removeFullTypeCount(player, "Base.EngineParts", need)
  end

  vehicle:updatePartStats()
  vehicle:updateBulletStats()
  pcall(function()
    if vehicle.transmitEngine then vehicle:transmitEngine() end
    if part then
      vehicle:transmitPartCondition(part)
      vehicle:transmitPartItem(part)
      vehicle:transmitPartModData(part)
    end
  end)

  addXp(player, Perks.Mechanics, 50)

  player:sendObjectChange('mechanicActionDone', {
    success    = true,
    vehicleId  = vehicle:getId(),
    partId     = part:getId(),
    itemId     = -1,
    installing = true
  })
end


EER_VehicleCommands.OnClientCommand = function(module, command, player, args)
  if module == 'EER_vehicle' and EER_Commands[command] then
    args = args or {}
    EER_Commands[command](player, args)
  end
end

Events.OnClientCommand.Add(EER_VehicleCommands.OnClientCommand)