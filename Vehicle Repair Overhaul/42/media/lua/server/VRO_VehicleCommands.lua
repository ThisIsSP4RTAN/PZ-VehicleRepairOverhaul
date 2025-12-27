---@diagnostic disable: undefined-field, param-type-mismatch
if isClient() then return end

-- VRO server command module
local VRO_VehicleCommands = {}
local VRO_CMDS = {}

VRO_VehicleCommands.debug = getDebug() or false
local function log(msg)
  if VRO_VehicleCommands.debug then print("[VRO_SRV] " .. tostring(msg)) end
end

--------- small helpers ----------
local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end
local function isDrainable(it) return it and instanceof(it, "DrainableComboItem") end

local function drainableUses(it)
  if not it then return 0 end
  if not isDrainable(it) then return 0 end
  if it.getDrainableUsesInt then return it:getDrainableUsesInt() end
  if it.getCurrentUses      then return it:getCurrentUses() end
  return 0
end

local function isTorchItem(it)
  if not it then return false end
  if it.hasTag and ItemTag and ResourceLocation and (ResourceLocation.of or ResourceLocation.new) then
    local rl = ResourceLocation.of and ResourceLocation.of("base:BlowTorch")
             or (ResourceLocation.new and ResourceLocation.new("base","BlowTorch"))
    if rl then
      local ok, tag = pcall(function() return ItemTag.get(rl) end)
      if ok and tag and it:hasTag(tag) then return true end
    end
  end
  local t  = it.getType     and it:getType()     or ""
  local ft = it.getFullType and it:getFullType() or ""
  return t == "BlowTorch" or ft == "Base.BlowTorch"
end

-- Count total "uses" for a fullType across all stacks (drainables = uses, others = 1 each)
local function _countUsesForFullType(player, fullType)
  if not (player and fullType) then return 0 end
  local inv = player:getInventory()
  if not inv then return 0 end
  local bag = ArrayList.new()
  inv:getAllTypeRecurse(fullType, bag)
  local have = 0
  for i = 0, bag:size() - 1 do
    local it = bag:get(i)
    if isDrainable(it) then
      have = have + drainableUses(it)
    else
      have = have + 1
    end
  end
  return have
end

-- Single-torch rule: the chosen hand torch must meet the required uses
local function _torchMeetsRequirement(player, needUses, fromPrimary)
  local need = tonumber(needUses) or 0
  if need <= 0 then return true end
  local torch = fromPrimary and player:getPrimaryHandItem() or player:getSecondaryHandItem()
  return torch and isTorchItem(torch) and (drainableUses(torch) >= need) or false
end

-- Validate we still have enough to proceed (server authority).
-- Skips "Base.BlowTorch" in consumeMap (torch handled via torchUses).
local function _requirementsOK(player, torchUses, torchFromPrimary, consumeMap)
  if not _torchMeetsRequirement(player, torchUses, torchFromPrimary) then
    return false
  end
  consumeMap = consumeMap or {}
  for fullType, need in pairs(consumeMap) do
    local n = tonumber(need) or 0
    if n > 0 and fullType ~= "Base.BlowTorch" then
      local have = _countUsesForFullType(player, fullType)
      if have < n then return false end
    end
  end
  return true
end

local function resolvePerk(name)
  if not name or not Perks then return nil end
  return Perks[name] or (Perks.FromString and Perks.FromString(name)) or nil
end

local function perkLevel(player, name)
  local p = resolvePerk(name)
  return (p and player:getPerkLevel(p)) or 0
end

local function chanceOfFail(player, fixerSkills, hbr)
  local fail = 3.0
  if fixerSkills then
    for perkName, req in pairs(fixerSkills) do
      local lvl = perkLevel(player, perkName)
      if lvl < req then fail = fail + (req - lvl) * 30
      else              fail = fail - (lvl - req) * 5 end
    end
  end
  fail = fail + (hbr + 1) * 2
  return clamp(fail, 0, 100)
end

local function repairedPercent(player, fixingCondMod, fixerSkills, hbr, fixerIndex)
  local base = (fixerIndex == 1) and 50.0 or ((fixerIndex == 2) and 20.0 or 10.0)
  base = base * (1.0 / (hbr + 1))
  if fixerSkills then
    for perkName, req in pairs(fixerSkills) do
      local lvl = perkLevel(player, perkName)
      if lvl > req then base = base + math.min((lvl - req) * 5, 25)
      else              base = base - (req - lvl) * 15 end
    end
  end
  base = base * (fixingCondMod or 1.0)
  return clamp(base, 0, 100)
end

local function consumeUses(it, uses, keepOnEmpty)
  if not (it and uses and uses > 0) then return end
  if isDrainable(it) and it.Use then
    for _=1,uses do
      if drainableUses(it) <= 0 then break end
      it:Use()
    end
    if it.syncItemFields then it:syncItemFields() end
    if (drainableUses(it) <= 0) and (not keepOnEmpty) then
      local con = it:getContainer()
      if con then
        con:Remove(it)
        if sendRemoveItemFromContainer then sendRemoveItemFromContainer(con, it) end
      end
    end
  end
end

-- Consume a given NUMBER OF USES for a fullType, walking all items of that type.
-- For non-drainables, each item counts as "1 use" (removes N items).
-- Never delete blowtorches here; torch is handled separately.
local function consumeFullTypeCount(player, fullType, needUses)
  if not (player and fullType and needUses and needUses > 0) then return end
  local inv   = player:getInventory()
  local bag   = ArrayList.new()
  inv:getAllTypeRecurse(fullType, bag)
  if bag:isEmpty() then return end

  local remain = needUses
  for i = 0, bag:size() - 1 do
    if remain <= 0 then break end
    local it = bag:get(i)
    if isDrainable(it) then
      if isTorchItem(it) then
        -- Torch is consumed via args.torchUses; skip here.
      else
        -- Drain uses from this drainable item
        if it.Use then
          while remain > 0 and drainableUses(it) > 0 do
            it:Use()
            remain = remain - 1
          end
        end
        if it.syncItemFields then it:syncItemFields() end
        if drainableUses(it) <= 0 then
          local con = it:getContainer()
          if con then
            con:Remove(it)
            if sendRemoveItemFromContainer then sendRemoveItemFromContainer(con, it) end
          end
        end
      end
    else
      -- Non-drainable: remove one item = 1 use
      local con = it:getContainer()
      if con then
        con:Remove(it)
        if sendRemoveItemFromContainer then sendRemoveItemFromContainer(con, it) end
        remain = remain - 1
      end
    end
  end
end

-- Persist an installed part + its inventory item, then broadcast.
local function _persistInstalledPart(vehicle, part)
  if not (vehicle and part) then return end

  -- Mirror part -> installed inventory item (if any)
  local inv = part.getInventoryItem and part:getInventoryItem() or nil
  if inv then
    if inv.setCondition then inv:setCondition(part:getCondition()) end
    -- Mirror "times repaired" from part modData to item (native API if present)
    local pmd = part:getModData()
    local hbr = (pmd and pmd.VRO_HaveBeenRepaired) or 0
    if inv.setHaveBeenRepaired then
      inv:setHaveBeenRepaired(hbr)
    else
      local imd = inv:getModData()
      imd.VRO_HaveBeenRepaired = hbr
    end
    if inv.syncItemFields then inv:syncItemFields() end
  end

  -- Now broadcast all the things for the part
  vehicle:updatePartStats()
  vehicle:updateBulletStats()
  vehicle:transmitPartCondition(part)
  vehicle:transmitPartItem(part)
  vehicle:transmitPartModData(part)
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

-------- keep-flag helpers (server) --------
local function _normalizeFlags(f)
  if f == nil then return nil end
  if type(f) == "table" and f[1] == nil then return f end -- already a map
  if type(f) == "table" then
    local m, n = {}, 0
    for i = 1, #f do
      local k = f[i]
      if type(k) == "string" then m[k] = true; n = n + 1 end
    end
    return (n > 0) and m or nil
  end
  return nil
end

local function _maintenanceMod(player)
  local m = (resolvePerk and Perks and player) and ((Perks.Maintenance and player:getPerkLevel(Perks.Maintenance)) or 0) or 0
  local w = (player and player.getWeaponLevel and (player:getWeaponLevel() or 0)) or 0
  return m + math.floor(w/2)
end

local function _applyKeepFlags(player, item, flags, hiSkill)
  if not (item and flags) then return end
  local fl = _normalizeFlags(flags)
  if not fl then return end

  local function dmg(factor)
    if item.damageCheck then item:damageCheck((hiSkill or 0) + _maintenanceMod(player), factor, false) end
  end

  local function sharp()
    if item.hasSharpness and item:hasSharpness() and item.sharpnessCheck then
      item:sharpnessCheck((hiSkill or 0) + _maintenanceMod(player), 1.0, false)
    else
      dmg(6.0)
    end
  end

  if     fl.MayDegradeHeavy     then dmg(1.0)
  elseif fl.MayDegrade          then dmg(2.0)
  elseif fl.MayDegradeLight     then dmg(3.0)
  elseif fl.MayDegradeVeryLight then dmg(6.0)
  end

  if fl.SharpnessCheck then sharp() end
end

local function _pickKeepItem(player, spec)
  if not spec then return nil end
  if spec.inPrimary then
    local it = player:getPrimaryHandItem()
    if it then return it end
  end
  if spec.inSecondary then
    local it = player:getSecondaryHandItem()
    if it then return it end
  end
  if spec.fullType then
    local bag = player:getInventory()
    local coll = ArrayList.new()
    bag:getAllTypeRecurse(spec.fullType, coll)
    if coll:size() > 0 then return coll:get(0) end
  end
  return nil
end

local function _hiRelevantSkill(player, skillsTable)
  local mx = 0
  if skillsTable then
    for perkName,_ in pairs(skillsTable) do
      local lvl = perkLevel(player, perkName)
      if lvl > mx then mx = lvl end
    end
  end
  return mx
end

-- Choose the best candidate from inventory when multiples exist:
-- pick the item with the LOWEST condition among matching fullType.
local function _pickInventoryTarget(player, fullType)
  local inv = player and player:getInventory()
  if not (inv and fullType) then return nil end
  local list = ArrayList.new()
  inv:getAllTypeRecurse(fullType, list)
  local best, bestCond = nil, math.huge
  for i = 0, list:size() - 1 do
    local it = list:get(i)
    local c  = (it.getCondition and it:getCondition()) or 0
    if c < bestCond then best, bestCond = it, c end
  end
  return best
end

-- args:
--   itemFullType      = "Base.KitchenKnife" (the broken item being repaired)
--   fixerSkills, fixingCondMod, fixerIndex, hbr
--   torchUses, torchFromPrimary
--   consumeMap        = { ["Base.Thread"]=3, ["Base.DuctTape"]=2, ... }
VRO_CMDS.doFixInventory = function(player, args)
  args = args or {}
  local fullType   = args.itemFullType
  local hbr        = tonumber(args.hbr or 0)
  local fixerIndex = tonumber(args.fixerIndex or 1)
  local condMod    = tonumber(args.fixingCondMod or 1.0)
  local skills     = args.fixerSkills
  local torchUses  = tonumber(args.torchUses or 0)
  local consumeMap = args.consumeMap or {}

  if not _requirementsOK(player, torchUses, args.torchFromPrimary, consumeMap) then
    log("doFixInventory: requirements missing; abort")
    return
  end

  local it = _pickInventoryTarget(player, fullType)
  if not it then log("doFixInventory: no item "..tostring(fullType)); return end

  -- roll + compute
  local fail    = chanceOfFail(player, skills, hbr)
  local success = ZombRand(100) >= fail
  local pct     = repairedPercent(player, condMod, skills, hbr, fixerIndex)

  local max = (it.getConditionMax and it:getConditionMax()) or 100
  local cur = (it.getCondition    and it:getCondition())    or 0

  if success then
    local missing = math.max(0, max - cur)
    local gain    = math.floor((missing * (pct / 100.0)) + 0.5)
    if gain < 1 then gain = 1 end
    if it.setCondition then it:setCondition(math.min(max, cur + gain)) end
    if it.setHaveBeenRepaired then
      it:setHaveBeenRepaired((it:getHaveBeenRepaired() or 0) + 1)
    else
      local md = it:getModData(); md.VRO_HaveBeenRepaired = (md.VRO_HaveBeenRepaired or 0) + 1
    end
  else
    if cur > 0 and it.setCondition then it:setCondition(cur - 1) end
  end

  if it.syncItemFields then it:syncItemFields() end

  -- Torch: drain from chosen hand; never delete when empty
  if torchUses > 0 then
    local torch = args.torchFromPrimary and player:getPrimaryHandItem() or player:getSecondaryHandItem()
    if torch and isTorchItem(torch) then consumeUses(torch, torchUses, true) end
  end

  -- Other consumables: remove/consume uses by fullType across stacks
  for ft, uses in pairs(consumeMap) do
    uses = tonumber(uses) or 0
    if uses > 0 then
      if ft ~= "Base.BlowTorch" then consumeFullTypeCount(player, ft, uses) end
    end
  end

  -- Apply keep-flags to kept tools (degrade/sharpness) after consumption
  do
    local list = args.keepFlags
    if list and list[1] ~= nil then
      local hi = _hiRelevantSkill(player, skills)
      for i = 1, #list do
        local spec = list[i]
        local it   = _pickKeepItem(player, spec)
        if it then
          _applyKeepFlags(player, it, spec.flags, hi)
          if it.syncItemFields then it:syncItemFields() end
        end
      end
    end
  end
end

-- ========= Main command (vehicle-part repairs) =========
-- args:
--   vehicleId, partId
--   fixerSkills={ perkName=reqLvl, ... }, fixingCondMod=number, fixerIndex=int, hbr=int
--   torchUses=int, torchFromPrimary=bool
--   consumeMap={ ["Base.DuctTape"]=2, ["Base.Thread"]=3, ... }  (non-torch)
VRO_CMDS.doFix = function(player, args)
  args = args or {}
  local vehicleId  = args.vehicleId
  local partId     = args.partId
  local hbr        = tonumber(args.hbr or 0)
  local fixerIndex = tonumber(args.fixerIndex or 1)
  local condMod    = tonumber(args.fixingCondMod or 1.0)
  local skills     = args.fixerSkills
  local torchUses  = tonumber(args.torchUses or 0)
  local consumeMap = args.consumeMap or {}

  local vehicle = vehicleId and getVehicleById(vehicleId) or nil
  if not vehicle then log("no vehicle id="..tostring(vehicleId)); return end
  local part = vehicle:getPartById(partId)
  if not part then log("no part id="..tostring(partId)); return end

  if not _requirementsOK(player, torchUses, args.torchFromPrimary, consumeMap) then
    log("doFix: requirements missing; abort")
    return
  end

  -- roll + compute on server
  local fail = chanceOfFail(player, skills, hbr)
  local success = ZombRand(100) >= fail
  local pct = repairedPercent(player, condMod, skills, hbr, fixerIndex)

  local targetMax = _partMaxCondition(part)
  local targetCur = math.min(part:getCondition(), targetMax)

  if success then
    local missing = math.max(0, targetMax - targetCur)
    local gain = math.floor((missing * (pct / 100.0)) + 0.5)
    if gain < 1 then gain = 1 end
    part:setCondition(math.min(targetMax, targetCur + gain))

    local md = part:getModData()
    md.VRO_HaveBeenRepaired = (md.VRO_HaveBeenRepaired or 0) + 1
    _persistInstalledPart(vehicle, part)
  else
    if targetCur > 0 then part:setCondition(targetCur - 1) end
    _persistInstalledPart(vehicle, part)
  end


  -- consume blowtorch uses only on the chosen torch; never delete when empty
  if torchUses > 0 then
    local torch = args.torchFromPrimary and player:getPrimaryHandItem() or player:getSecondaryHandItem()
    if torch and isTorchItem(torch) then
      consumeUses(torch, torchUses, true) -- keepOnEmpty=true
    end
  end

  -- remove other consumables securely by type
  for fullType, uses in pairs(consumeMap) do
    uses = tonumber(uses) or 0
    if uses > 0 then
      if fullType == "Base.BlowTorch" then
        -- Torch is always handled via args.torchUses + hand item; skip here
      else
        consumeFullTypeCount(player, fullType, uses)
      end
    end
  end

  -- Apply keep-flags on server (tools kept in hand/inventory)
  do
    local list = args.keepFlags
    if list and list[1] ~= nil then
      local hi = _hiRelevantSkill(player, skills)
      for i = 1, #list do
        local spec = list[i]
        local it   = _pickKeepItem(player, spec)
        if it then
          _applyKeepFlags(player, it, spec.flags, hi)
          if it.syncItemFields then it:syncItemFields() end
        end
      end
    end
  end

  player:sendObjectChange('mechanicActionDone', {
    success    = success,
    vehicleId  = vehicleId or -1,
    partId     = partId or "",
    itemId     = -1,
    installing = true
  })
end

VRO_VehicleCommands.OnClientCommand = function(module, command, player, args)
  if module == 'VRO_vehicle' and VRO_CMDS[command] then
    if VRO_VehicleCommands.debug then
      local argStr = ''
      args = args or {}
      for k,v in pairs(args) do
        if type(v) == "table" then
          argStr = argStr .. ' ' .. k .. '={...}'
        else
          argStr = argStr .. ' ' .. k .. '=' .. tostring(v)
        end
      end
      print(('[VRO_SRV] %s %s%s'):format(module, command, argStr))
    end
    VRO_CMDS[command](player, args or {})
  end
end

Events.OnClientCommand.Add(VRO_VehicleCommands.OnClientCommand)