---@diagnostic disable: param-type-mismatch
if isClient() then return end

local ELR_VehicleCommands = {}
local ELR_Commands = {}

ELR_VehicleCommands.wantNoise = getDebug() or false

local noise = function(msg)
	if ELR_VehicleCommands.wantNoise then
--		print('VehicleCommands: '..msg)
	end
end

local function _partMaxCondition(part)
  if not part then return 100 end
  -- Some parts have this, many don't:
  if part.getConditionMax then
    local ok, val = pcall(function() return part:getConditionMax() end)
    if ok and type(val) == "number" and val > 0 then return val end
  end
  -- Most reliable: ask the installed inventory item
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

function ELR_Commands.repairLightbar(player, args)
	local vehicle = getVehicleById(args.vehicle)
	if not vehicle then return end

	local part = vehicle:getPartById("lightbar")
	if not part then return end

	-- Apply condition with the real max
	local maxC = _partMaxCondition(part)
	local tgt  = math.min(maxC, tonumber(args.targetCondition) or maxC)
	part:setCondition(tgt)

	-- Count a repair and mirror to the installed item
	local md = part:getModData()
	md.VRO_HaveBeenRepaired = (md.VRO_HaveBeenRepaired or 0) + 1

	local inv = part.getInventoryItem and part:getInventoryItem() or nil
	if inv then
		if inv.setCondition then inv:setCondition(part:getCondition()) end
		if inv.setHaveBeenRepaired then
			inv:setHaveBeenRepaired(md.VRO_HaveBeenRepaired or 0)
		else
			local imd = inv:getModData()
			imd.VRO_HaveBeenRepaired = md.VRO_HaveBeenRepaired or 0
		end
		if inv.syncItemFields then inv:syncItemFields() end
	end

	-- Server-side removal of required parts
	for fullType, count in pairs(args.repairParts or {}) do
	local n = tonumber(count) or 0
		if n > 0 then
			_removeFullTypeCount(player, fullType, n)
	  	end
	end

	vehicle:updatePartStats()
	vehicle:updateBulletStats()
	vehicle:transmitPartCondition(part)
	vehicle:transmitPartItem(part)
	vehicle:transmitPartModData(part)

	player:sendObjectChange('mechanicActionDone', {
		success   = true,
		vehicleId = vehicle:getId(),
		partId    = part:getId(),
		itemId    = -1,
		installing= true
	})
end

function ELR_Commands.setLightbarLightsMode(player, args)
	local vehicle = getVehicleById(args.vehicle)
	local mode = tonumber(args.mode);
	if vehicle then
		vehicle:setLightbarLightsMode(mode)
	else
		noise('no vehicle for lightbar lights mode')
	end
end

function ELR_Commands.setLightbarSirenMode(player, args)
	local vehicle = getVehicleById(args.vehicle)
	local mode = tonumber(args.mode);
	if vehicle then
		vehicle:setLightbarSirenMode(mode)
		vehicle:setSirenStartTime(getGameTime():getWorldAgeHours())
	else
		noise('no vehicle for lightbar siren mode')
	end
end

ELR_VehicleCommands.OnClientCommand = function(module, command, player, args)
	if module == 'ELR_vehicle' and ELR_Commands[command] then
		local argStr = ''
		args = args or {}
		for k,v in pairs(args) do
			if k == "repairParts" then
				argStr = argStr..' '..k..'={'

				for l,w in pairs(args[k]) do
					argStr = argStr..' '..l..'='..tostring(w)
				end

				argStr = argStr..'}'
			else
				argStr = argStr..' '..k..'='..tostring(v)
			end
		end
		noise('received '..module..' '..command..' '..tostring(player)..argStr)
		ELR_Commands[command](player, args)
	end
end

Events.OnClientCommand.Add(ELR_VehicleCommands.OnClientCommand)
