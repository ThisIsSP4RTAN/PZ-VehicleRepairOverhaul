--***********************************************************
--**                    Based on code by                   **
--**                                                       **
--**                    THE INDIE STONE                    **
--***********************************************************

require "TimedActions/ISBaseTimedAction"

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

	local engineRepairLevel = self.vehicle:getScript():getEngineRepairLevel();

	local skill = self.character:getPerkLevel(Perks.Mechanics) - engineRepairLevel;
	local numberOfParts = self.character:getInventory():getNumberOfItem("EngineParts", false, true);
	

	-- Set how many Spare Engine Parts are required to rebuild the engine on this vehicle. Equal to 5 * the Mechanics skill level required 
	--   to work on the engine.
	local requiredEngineParts = engineRepairLevel * 5;
	
--	local args = { vehicle = self.vehicle:getId(), condition = self.part:getCondition(), skillLevel = skill, numberOfParts = numberOfParts }
--	args.giveXP = self.character:getMechanicsItem(self.part:getVehicle():getMechanicalID() .. "2") == nil
--	sendClientCommand(self.character, 'vehicle', 'repairEngine', args)

	-- Engine is rebuilt, so its condition should now be full as well.
	self.part:setCondition(100.0);	
	
	-- This function is how the Indie Stone code sets the engine to maximum quality as part of the debug/cheat menus. So we use this rather than 
	--   setting the individual stats so that any additional support code (e.g. client/server code) also runs.
	sendClientCommand(self.character, "vehicle", "repairPart", { vehicle = self.part:getVehicle():getId(), part = self.part:getId() });

	local inventory = self.character:getInventory();
	
	for i=1,requiredEngineParts do
		inventory:RemoveOneOf("EngineParts");
	end

	self.character:getXp():AddXP(Perks.Mechanics, 50);
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


