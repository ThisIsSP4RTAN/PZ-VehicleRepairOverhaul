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

function ELR_Commands.repairLightbar(player, args)
	local vehicle = getVehicleById(args.vehicle)
	if vehicle then
		local part = vehicle:getPartById("lightbar")

		if not part then
			noise('no such part lightbar')
			return
		end


		part:setCondition(args.targetCondition)

		player:sendObjectChange('addXp', { perk = Perks.Electricity:index(), xp = args.repairBlocks, noMultiplier = false })

		for partType,partCount in pairs(args["repairParts"]) do
			player:sendObjectChange('removeItemType', { type = partType, count = partCount })
		end

		vehicle:updatePartStats()
		vehicle:updateBulletStats()
		vehicle:transmitPartCondition(part)
		vehicle:transmitPartItem(part)
		vehicle:transmitPartModData(part)


		player:sendObjectChange('mechanicActionDone', { success = true, vehicleId = vehicle:getId(), partId = part:getId(), itemId = -1, installing = true })
	else
		noise('no such vehicle id='..tostring(args.vehicle))
	end
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
