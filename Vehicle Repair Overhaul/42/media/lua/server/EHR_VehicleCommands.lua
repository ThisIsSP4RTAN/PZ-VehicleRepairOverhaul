---@diagnostic disable: param-type-mismatch
if isClient() then return end

local EHR_VehicleCommands = {}
local EHR_Commands = {}

EHR_VehicleCommands.wantNoise = getDebug() or false

local noise = function(msg)
	if EHR_VehicleCommands.wantNoise then
--		print('VehicleCommands: '..msg)
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
    local it = coll:get(i)
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

function EHR_Commands.repairHeater(player, args)
	local vehicle = getVehicleById(args.vehicle)
	if not vehicle then return end

	local part = vehicle:getPartById("Heater")
	if not part then return end

	-- Set part condition to target, using real max
	local maxC = _partMaxCondition(part)
	local tgt  = math.min(maxC, tonumber(args.targetCondition) or maxC)
	part:setCondition(tgt)

	-- Count a “repair” and mirror to the installed inventory item
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

	for fullType, count in pairs(args.repairParts or {}) do
	local n = tonumber(count) or 0
		if n > 0 then
			_removeFullTypeCount(player, fullType, n)
		end
	end

	-- Drain exactly 10 uses from the equipped blowtorch, never delete it
	local torch = player:getPrimaryHandItem()
	if not torch or not torch.Use then
		local s = player:getSecondaryHandItem()
		if s and s.Use then torch = s end
	end
	if torch and torch.Use then
		for i = 1, 10 do
			-- support both APIs if present
			if torch.getDrainableUsesInt and torch:getDrainableUsesInt() <= 0 then break end
			if torch.getCurrentUses      and torch:getCurrentUses()      <= 0 then break end
			torch:Use()
		end
		if torch.syncItemFields then torch:syncItemFields() end
	end

	vehicle:updatePartStats()
	vehicle:updateBulletStats()
	vehicle:transmitPartCondition(part)
	vehicle:transmitPartItem(part)
	vehicle:transmitPartModData(part)

	do
		local xp = ZombRand(3,6)
		if addXp then
			addXp(player, Perks.MetalWelding, xp)
			addXp(player, Perks.Mechanics,    xp)
		else
			local xps = player and player.getXp and player:getXp()
			if xps and xps.AddXP then
			xps:AddXP(Perks.MetalWelding, xp)
			xps:AddXP(Perks.Mechanics,    xp)
			end
		end
	end


	player:sendObjectChange('mechanicActionDone', {
		success   = true,
		vehicleId = vehicle:getId(),
		partId    = part:getId(),
		itemId    = -1,
		installing= true
	})
end


EHR_VehicleCommands.OnClientCommand = function(module, command, player, args)
	if module == 'EHR_vehicle' and EHR_Commands[command] then
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
		EHR_Commands[command](player, args)
	end
end

Events.OnClientCommand.Add(EHR_VehicleCommands.OnClientCommand)