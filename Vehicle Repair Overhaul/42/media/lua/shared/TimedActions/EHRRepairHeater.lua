---@diagnostic disable: undefined-field, param-type-mismatch
--***********************************************************
--**                    Based on code by                   **
--**                                                       **
--**                    THE INDIE STONE                    **
--***********************************************************

require "TimedActions/ISBaseTimedAction"

EHRRepairHeater = ISBaseTimedAction:derive("EHRRepairHeater")

function EHRRepairHeater:isValid()
	if not self.character:hasEquipped("BlowTorch") or self.vehicle == nil then
		return false
	end

	return true
end

function EHRRepairHeater:waitToStart()
	self.character:faceThisObject(self.vehicle)
	return self.character:shouldBeTurning()
end

function EHRRepairHeater:update()
	self.character:faceThisObject(self.vehicle)
	self.blowtorch:setJobDelta(self:getJobDelta())

    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function EHRRepairHeater:start()
	-- Set the progress bar text on the equipped blowtorch in the inventory menu to be the job description
	self.blowtorch:setJobType(self.jobType)

	-- Play the character animation of using the blowtorch
	self:setActionAnim("BlowTorchMid")
	self:setOverrideHandModels(self.character:getPrimaryHandItem(), nil)

	-- Play the sound of using the blowtorch and make it audible in the world so zombies can react to it
	-- Store the reference to the sound so we can stop it once the action is done
	self.sound = self.character:getEmitter():playSound("BlowTorch")
	local radius = 20 * self.character:getWeldingSoundMod()
	addSound(self.character, self.character:getX(), self.character:getY(), self.character:getZ(), radius, radius)
end

function EHRRepairHeater:stop()
	self.blowtorch:setJobDelta(0)

	-- Stop the sound of the blowtorch once the action is complete
	if self.sound then
		self.character:getEmitter():stopSound(self.sound)
		self.sound = nil
	end
    ISBaseTimedAction.stop(self);
end

function EHRRepairHeater:perform()
    -- Stop the sound of the blowtorch once the action is complete
    if self.sound then
        self.character:getEmitter():stopSound(self.sound)
        self.sound = nil
    end
	self.blowtorch:setJobDelta(0)

	-- Repair the heater using our custom client command
	sendClientCommand(self.character, 'EHR_vehicle', 'repairHeater', { vehicle = self.part:getVehicle():getId(), part = self.part:getId(), targetCondition = self.targetCondition, repairParts = self.requiredParts })

    -- Consume the required parts once the action is complete
    for itemType, count in pairs(self.requiredParts) do
        for i = 1, count do
            local item = self.character:getInventory():FindAndReturn(itemType)
            if item then
                self.character:getInventory():Remove(item)
            end
        end
    end
	ISBaseTimedAction.perform(self)
end

function EHRRepairHeater:new(character, part, blowtorch, mask, timeToRepair, requiredParts, targetCondition)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o.character = character
	o.vehicle = part:getVehicle()
	o.part = part
	o.blowtorch = blowtorch
	o.mask = mask

	o.maxTime = timeToRepair

--[[	
	if character:HasTrait("Handy") then
		o.maxTime = timeToRepair - 20;
    end
--]]

	if character:isTimedActionInstant() then
        o.maxTime = 1;
    end
	
	o.requiredParts = requiredParts
	o.targetCondition = targetCondition
	
	o.stopOnWalk = true;
	o.stopOnRun = true;
	o.sound = nil

	o.jobType = getText("ContextMenu_Repair")..''..getText("IGUI_VehiclePartHeater")
	return o
end

