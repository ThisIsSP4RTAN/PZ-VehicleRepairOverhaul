---@diagnostic disable: undefined-field, param-type-mismatch
--***********************************************************
--**                    Based on code by                   **
--**                                                       **
--**                    THE INDIE STONE                    **
--***********************************************************

require "TimedActions/ISBaseTimedAction"
require "VRO/VRO_Sandbox"

ISRebuildEngine = ISBaseTimedAction:derive("ISRebuildEngine")

function ISRebuildEngine:isValid()
--	return self.vehicle:isInArea(self.part:getArea(), self.character)
	return true;
end

function ISRebuildEngine:waitToStart()
	self.character:faceThisObject(self.vehicle)
	return self.character:shouldBeTurning()
end

function ISRebuildEngine:update()
	self.character:faceThisObject(self.vehicle)
	self.item:setJobDelta(self:getJobDelta())

    self.character:setMetabolicTarget(Metabolics.MediumWork);
end

function ISRebuildEngine:start()
	if VRO and VRO.IsEngineRebuildEnabled and not VRO.IsEngineRebuildEnabled() then return end
	self.item:setJobType(getText("IGUI_EER_RebuildEngine"))
	self:setActionAnim("VehicleWorkOnMid")
end

function ISRebuildEngine:stop()
	self.item:setJobDelta(0)
	ISBaseTimedAction.stop(self)
end

function ISRebuildEngine:perform()
    ISBaseTimedAction.perform(self)
    self.item:setJobDelta(0)

    local engineRepairLevel   = self.vehicle:getScript():getEngineRepairLevel()
    local requiredEngineParts = engineRepairLevel * 5

    -- Show the repair immediately (SP responsiveness)
    self.part:setCondition(100.0)

    -- Vanilla repairPart (keeps vanilla sync happy)
    sendClientCommand(self.character, "vehicle", "repairPart", {
        vehicle = self.part:getVehicle():getId(),
        part    = self.part:getId(),
    })

    -- Our server command (quality + consume EngineParts + sync)
    sendClientCommand(self.character, "EER_vehicle", "rebuildEngine", {
        vehicleId     = self.vehicle:getId(),
        targetQuality = 100,
        consumeParts  = requiredEngineParts,
    })
end

function ISRebuildEngine:new(character, part, item, time)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.character = character
	o.vehicle = part:getVehicle()
	o.part = part
	o.item = item
	o.maxTime = time
	o.jobType = getText("IGUI_EER_RebuildEngine")
	return o
end