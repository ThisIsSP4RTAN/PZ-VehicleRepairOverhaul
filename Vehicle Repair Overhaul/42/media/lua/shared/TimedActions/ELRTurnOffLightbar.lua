---@diagnostic disable: undefined-field, param-type-mismatch
--***********************************************************
--**                    Based on code by                   **
--**                                                       **
--**                    THE INDIE STONE                    **
--***********************************************************

require "TimedActions/ISBaseTimedAction"

ELRTurnOffLightbar = ISBaseTimedAction:derive("ELRTurnOffLightbar")

function ELRTurnOffLightbar:isValid()
	return true
end

function ELRTurnOffLightbar:waitToStart()
	if self.isCharacterOutside then
		-- If we are operating in the mode where the character is outside of the vehicle, then wait until the 
		--   player is facing the vehicle
		self.character:faceThisObject(getVehicleById(self.vehicleId))
		return self.character:shouldBeTurning()
	else
		-- If we are operating in the mode where the character should be in the vehicle, then wait until the 
		--   player is in a vehicle
		return not self.character:getVehicle()
	end
end

function ELRTurnOffLightbar:update()
	if self.isCharacterOutside then self.character:faceThisObject(self.vehicle) end
end

function ELRTurnOffLightbar:start()
	if self.character:getVehicle() then self.vehicle = self.character:getVehicle() end
end

function ELRTurnOffLightbar:stop()
	ISBaseTimedAction.stop(self)
end

function ELRTurnOffLightbar:perform()
	ISBaseTimedAction.perform(self)

	-- If we are operating in the mode that the player is outside of the vehicle then use our custom commands to 
	--   turn off the lightbar as the vanilla commands assume the player is inside of the vehicle. If in the 
	--   the other mode, then use the vanilla commands.
	-- We keep the ability to use the vanilla commands for the sake of potential future compatability if the 
	--   vanilla behavior of these functions is expanded in the future.
	if self.isCharacterOutside then
		-- Turn off the lightbar lights and siren from outside of the vehicle
		sendClientCommand(self.character, 'ELR_vehicle', 'setLightbarLightsMode', { mode = 0, vehicle = self.vehicleId })
		sendClientCommand(self.character, 'ELR_vehicle', 'setLightbarSirenMode', { mode = 0, vehicle = self.vehicleId })
	else
		-- Turn off the lightbar lights and siren from inside of the vehicle
		sendClientCommand(self.character, 'vehicle', 'setLightbarLightsMode', { mode = 0 })
		sendClientCommand(self.character, 'vehicle', 'setLightbarSirenMode', { mode = 0 })
	end
end

function ELRTurnOffLightbar:new(character, isCharacterOutside, vehicleId)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.character = character
	o.isCharacterOutside = isCharacterOutside
	o.vehicleId = vehicleId

	-- Default time, just a short pause
	o.maxTime = 50
	return o
end