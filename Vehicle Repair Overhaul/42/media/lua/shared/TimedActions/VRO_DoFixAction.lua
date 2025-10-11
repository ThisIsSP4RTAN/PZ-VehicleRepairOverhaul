---@diagnostic disable: undefined-field, param-type-mismatch, redundant-parameter
require "TimedActions/ISBaseTimedAction"

local VRO = rawget(_G, "VRO") or {}
_G.VRO = VRO

----------------------------------------------------------------
-- Minimal helpers the action relies on
----------------------------------------------------------------
local function isDrainable(it) return it and instanceof(it, "DrainableComboItem") end

local function drainableUses(it)
  if not it then return 0 end
  if isDrainable(it) then
    if it.getDrainableUsesInt then return it:getDrainableUsesInt() end
    if it.getCurrentUses then return it:getCurrentUses() end
    if it.getUsedDelta and it.getUseDelta then
      local used, step = it:getUsedDelta(), it:getUseDelta()
      if step and step > 0 then return math.max(0, math.floor((1.0 - used) / step + 0.0001)) end
    end
    return 0
  end
  return 1
end

local function consumeItems(character, bundles)
  if not bundles then return end
  for _, b in ipairs(bundles) do
    local it, take = b.item, b.takeUses or 0
    if it and take > 0 then
      if isDrainable(it) then
        if it.Use then
          for _=1,take do if drainableUses(it) <= 0 then break end; it:Use() end
        elseif it.getUseDelta and it.getUsedDelta and it.setUsedDelta then
          local step = it:getUseDelta()
          it:setUsedDelta(math.min(1.0, it:getUsedDelta() + step * take))
        end
        if drainableUses(it) <= 0 then
          local con = it.getContainer and it:getContainer() or (character and character:getInventory()) or nil
          if con then con:Remove(it) end
        end
      else
        local con = it.getContainer and it:getContainer() or (character and character:getInventory()) or nil
        if con then con:Remove(it) end
      end
    end
  end
end

-- HaveBeenRepaired persistence helpers (supports part modData or loose item HBR)
local function getHBR(part, invItem)
  if invItem and invItem.getHaveBeenRepaired then return invItem:getHaveBeenRepaired() end
  local md = part and part:getModData() or {}
  return md.VRO_HaveBeenRepaired or 0
end

local function setHBR(part, invItem, val)
  if invItem and invItem.setHaveBeenRepaired then invItem:setHaveBeenRepaired(val) end
  if part then part:getModData().VRO_HaveBeenRepaired = val end
end

-- Perk helpers + repair math
local function resolvePerk(perkName)
  if Perks then
    if Perks[perkName] then return Perks[perkName] end
    if Perks.FromString then return Perks.FromString(perkName) end
  end
  return nil
end

local function perkLevel(chr, perkName)
  local perk = resolvePerk(perkName)
  if not perk then return 0 end
  return chr:getPerkLevel(perk)
end

local function chanceOfFail(chr, fixer, hbr)
  local fail = 3.0
  if fixer and fixer.skills then
    for name,req in pairs(fixer.skills) do
      local lvl = perkLevel(chr, name)
      if lvl < req then fail = fail + (req - lvl) * 30
      else              fail = fail - (lvl - req) * 5 end
    end
  end
  fail = fail + (hbr + 1) * 2
  if chr:HasTrait("Lucky")   then fail = fail - 5 end
  if chr:HasTrait("Unlucky") then fail = fail + 5 end
  if fail < 0 then fail = 0 elseif fail > 100 then fail = 100 end
  return fail
end

local function condRepairedPercent(chr, fixing, fixer, hbr, fixerIndex)
  local base = (fixerIndex == 1) and 50.0 or ((fixerIndex == 2) and 20.0 or 10.0)
  base = base * (1.0 / (hbr + 1))
  if fixer and fixer.skills then
    for name,req in pairs(fixer.skills) do
      local lvl = perkLevel(chr, name)
      if lvl > req then base = base + math.min((lvl - req) * 5, 25)
      else              base = base - (req - lvl) * 15 end
    end
  end
  base = base * ((fixing and fixing.conditionModifier) or 1.0)
  if base < 0 then base = 0 elseif base > 100 then base = 100 end
  return base
end

local function defaultAnimForPart(part)
  if not part then return "VehicleWorkOnMid" end
  if part.getWheelIndex and part:getWheelIndex() ~= -1 then return "VehicleWorkOnTire" end
  local id = tostring(part.getId and part:getId() or "")
  if string.find(id, "Brake", 1, true) then return "VehicleWorkOnTire" end
  return "VehicleWorkOnMid"
end

-- Build a job label like: "Repair Car Seat"
local function buildJobType(part, brokenItem)
  local label = getText("ContextMenu_Repair")
  local name
  if brokenItem and brokenItem.getDisplayName then
    name = brokenItem:getDisplayName()
  elseif part and part.getInventoryItem and part:getInventoryItem() then
    local inv = part:getInventoryItem()
    if inv and inv.getDisplayName then name = inv:getDisplayName() end
  end
  if name and name ~= "" then
    return label .. "" .. name
  end
  return label
end

----------------------------------------------------------------
-- Progress helpers: show bars on every used item
----------------------------------------------------------------
local function collectProgressItems(self)
  -- Dedup across bundles/tools/subject and extra refs we’ll resolve here.
  local list, seen = {}, {}
  local function add(it)
    if it and it.setJobDelta and not seen[it] then
      seen[it] = true
      table.insert(list, it)
    end
  end
  local function addBundle(bundle)
    if not bundle then return end
    for _,b in ipairs(bundle) do add(b.item) end
  end

  -- Bundles (consumed fixer/global items)
  addBundle(self.fixerBundle)
  addBundle(self.globalBundle)

  -- tools we equipped
  add(self.expectedPrimary)
  add(self.expectedSecondary)

  -- the broken loose item (inventory repair)
  add(self.brokenItem)

  -- Also include WEAR item (recipe/fixer equip) + NON-CONSUMED globalItems
  local inv = self.character and self.character:getInventory() or nil
  if inv then
    local function findByTag(tag)
      if inv.getFirstTagRecurse then return inv:getFirstTagRecurse(tag) end
      return nil
    end
    local function findByAnyTag(tags)
      if type(tags) == "table" then
        for _,tg in ipairs(tags) do
          local it = findByTag(tg)
          if it then return it end
        end
      elseif type(tags) == "string" then
        return findByTag(tags)
      end
      return nil
    end
    local function findByType(ft)
      if inv.getFirstTypeRecurse then return inv:getFirstTypeRecurse(ft) end
      return nil
    end

    -- Merge equip (recipe defaults, then fixer overrides)
    local eq = {}
    if self.fixing and self.fixing.equip then for k,v in pairs(self.fixing.equip) do eq[k]=v end end
    if self.fixer  and self.fixer.equip  then for k,v in pairs(self.fixer.equip)  do eq[k]=v end end
    if eq.wearTag then add(findByTag(eq.wearTag)) end
    if eq.wear    then add(findByType(eq.wear))  end

    -- Non-consumed global items (support single or list, on recipe or fixer),
    -- now with multi-tag support via gi.tags = { "TagA","TagB",... }.
    local function pushGI(gi)
      if gi and gi.consume == false then
        if gi.tags then
          add(findByAnyTag(gi.tags))
        elseif gi.tag then
          add(findByTag(gi.tag))
        elseif gi.item then
          add(findByType(gi.item))
        end
      end
    end
    if self.fixing then
      if self.fixing.globalItems then
        for _,gi in ipairs(self.fixing.globalItems) do pushGI(gi) end
      end
      if self.fixing.globalItem then pushGI(self.fixing.globalItem) end
    end
    if self.fixer and self.fixer.globalItem then pushGI(self.fixer.globalItem) end
  end

  return list
end

----------------------------------------------------------------
-- Timed Action (shared)
----------------------------------------------------------------
VRO.DoFixAction = ISBaseTimedAction:derive("VRO_DoFixAction")

function VRO.DoFixAction:isValid()
  if self.part and self.part:getVehicle() then return true end
  if self.brokenItem then return true end
  return false
end

function VRO.DoFixAction:waitToStart()
  local veh = self.part and self.part:getVehicle()
  if veh then self.character:faceThisObject(veh) end
  return self.character:shouldBeTurning()
end

function VRO.DoFixAction:update()
  local veh = self.part and self.part:getVehicle()
  if veh then self.character:faceThisObject(veh) end

  -- Drive all progress bars
  if self._progressItems then
    local jd = self:getJobDelta()
    for _,it in ipairs(self._progressItems) do
      if it and it.setJobDelta then it:setJobDelta(jd) end
    end
  end

  if self.setMetabolicTarget then
    self.character:setMetabolicTarget(Metabolics.LightWork)
  end
end

function VRO.DoFixAction:start()
  local anim = self.actionAnim or defaultAnimForPart(self.part)
  if anim and self.setActionAnim then self:setActionAnim(anim) end

  if self.setOverrideHandModels then
    if self.showModel ~= false then
      local p = self.expectedPrimary   or self.character:getPrimaryHandItem()
      local s = self.expectedSecondary or self.character:getSecondaryHandItem()
      self:setOverrideHandModels(p, s)
    else
      self:setOverrideHandModels(nil, nil)
    end
    self._didOverride = true
  end

  -- Set up all items to show progress bars + text
  self._progressItems = collectProgressItems(self)
  local job = self.jobType or buildJobType(self.part, self.brokenItem)
  for _,it in ipairs(self._progressItems) do
    if it.setJobType then it:setJobType(job) end
    if it.setJobDelta then it:setJobDelta(0) end
  end

  if self.fxSound then
    self._soundHandle = self.character:getEmitter():playSound(self.fxSound)
  end
end

function VRO.DoFixAction:stop()
  if self._progressItems then
    for _,it in ipairs(self._progressItems) do
      if it and it.setJobDelta then it:setJobDelta(0) end
    end
  end

  if self._soundHandle then
    self.character:getEmitter():stopSound(self._soundHandle)
    self._soundHandle = nil
  end
  if self._didOverride and self.setOverrideHandModels then
    self:setOverrideHandModels(nil, nil)
    self._didOverride = nil
  end
  ISBaseTimedAction.stop(self)
end

function VRO.DoFixAction:perform()
  local part   = self.part
  local broken = self.brokenItem
  local hbr    = getHBR(part, broken)
  local failPct   = chanceOfFail(self.character, self.fixer, hbr)
  local success   = ZombRand(100) >= failPct
  local pctRepair = condRepairedPercent(self.character, self.fixing, self.fixer, hbr, self.fixerIndex)

  -- Target condition (installed part or loose item)
  local targetMax, targetCur
  if part then
    targetMax = (part.getConditionMax and part:getConditionMax()) or 100
    targetCur = math.min(part:getCondition(), targetMax)
  else
    targetMax = (broken and broken.getConditionMax and broken:getConditionMax()) or 100
    targetCur = broken and broken:getCondition() or 0
  end

  if success then
    local missing = math.max(0, targetMax - targetCur)
    local gain    = math.floor((missing * (pctRepair / 100.0)) + 0.5)
    if gain < 1 then gain = 1 end

    if part then
      part:setCondition(math.min(targetMax, targetCur + gain))
      if part.getVehicle and part:getVehicle() and part:getVehicle().transmitPartCondition then
        part:getVehicle():transmitPartCondition(part)
      end
    end
    if broken then
      local newVal = math.min(targetMax, targetCur + gain)
      if broken.setConditionNoSound then broken:setConditionNoSound(newVal) else broken:setCondition(newVal) end
      broken:syncItemFields()
    end

    setHBR(part, broken, hbr + 1)

    if self._soundHandle then
      self.character:getEmitter():stopSound(self._soundHandle)
      self._soundHandle = nil
    end
    if self.successSfx then
      self.character:getEmitter():playSound(self.successSfx)
    end

    if self.fixer and self.fixer.skills then
      for perkName,_ in pairs(self.fixer.skills) do
        local perk = resolvePerk(perkName)
        if perk then self.character:getXp():AddXP(perk, ZombRand(3,6)) end
      end
    end
  else
    if part and targetCur > 0 then
      part:setCondition(targetCur - 1)
      if part.getVehicle and part:getVehicle() and part:getVehicle().transmitPartCondition then
        part:getVehicle():transmitPartCondition(part)
      end
    end
    if broken then
      local newVal = math.max(0, targetCur - 1)
      if broken.setConditionNoSound then broken:setConditionNoSound(newVal) else broken:setCondition(newVal) end
      broken:syncItemFields()
    end
    self.character:getEmitter():playSound("FixingItemFailed")
  end

  consumeItems(self.character, self.fixerBundle)
  if self.globalBundle then consumeItems(self.character, self.globalBundle) end

  -- Clear all progress bars
  if self._progressItems then
    for _,it in ipairs(self._progressItems) do
      if it and it.setJobDelta then it:setJobDelta(0) end
    end
  end

  if self._soundHandle then self.character:getEmitter():stopSound(self._soundHandle) end
  if self._didOverride and self.setOverrideHandModels then
    self:setOverrideHandModels(nil,nil)
    self._didOverride = nil
  end
  ISBaseTimedAction.perform(self)
end

function VRO.DoFixAction:new(args)
  local o = ISBaseTimedAction.new(self, args.character)
  o.stopOnWalk   = true
  o.stopOnRun    = true
  o.character    = args.character
  o.part         = args.part
  o.fixing       = args.fixing
  o.fixer        = args.fixer
  o.fixerIndex   = args.fixerIndex or 1
  o.brokenItem   = args.brokenItem
  o.fixerBundle  = args.fixerBundle
  o.globalBundle = args.globalBundle
  o.maxTime      = args.time or 150
  o.actionAnim   = args.anim
  o.fxSound      = args.sfx
  o.successSfx   = args.successSfx
  o.showModel    = (args.showModel ~= false) -- default true
  o.expectedPrimary   = args.expectedPrimary
  o.expectedSecondary = args.expectedSecondary
  -- Job label used for the inventory progress bar text
  o.jobType = args.jobType or buildJobType(args.part, args.brokenItem)
  return o
end

return VRO
