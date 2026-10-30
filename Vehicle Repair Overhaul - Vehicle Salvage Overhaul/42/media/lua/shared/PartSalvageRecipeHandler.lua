local VRO = require "VRO/Core"
VRO.PartLists = VRO.PartLists or {}

local function _mergeLists(dst, src)
  if type(dst) ~= "table" or type(src) ~= "table" then return end
  for k, v in pairs(src) do
    if type(k) == "string" and type(v) == "table" then
      dst[k] = v
    end
  end
end

VRO._salvageInputsInjected = false

local function _loadSharedPartListsOnce()
  if VRO._partListsLoaded then return end
  VRO._partListsLoaded = true

  local ok, mod = pcall(require, "VRO_PartLists")
  if ok and type(mod) == "table" then _mergeLists(VRO.PartLists, mod) end
end

local function _getPartListByName(name)
  _loadSharedPartListsOnce()
  return (type(VRO.PartLists[name]) == "table") and VRO.PartLists[name] or nil
end

local function _existsFullType(fullType)
  local sm = ScriptManager and ScriptManager.instance
  return (sm and sm:getItem(fullType)) ~= nil
end

local function _flattenTokens(tokens)
  local includeList, includeSet = {}, {}
  local excludeSet = {}

  local function _add(ft)
    if not includeSet[ft] then
      includeSet[ft] = true
      includeList[#includeList + 1] = ft
    end
  end

  tokens = tokens or {}
  if tokens[1] ~= nil then
    for i = 1, #tokens do
      local tok = tokens[i]
      if type(tok) == "string" then
        local negative = false
        if tok:sub(1,1) == "!" then
          negative = true
          tok = tok:sub(2)
        end

        if tok:sub(1,1) == "@" then
          local listName = tok:sub(2)
          local lst = _getPartListByName(listName)
          if lst and lst[1] ~= nil then
            if negative then
              for j = 1, #lst do
                excludeSet[lst[j]] = true
              end
            else
              for j = 1, #lst do
                local ft = lst[j]
                if _existsFullType(ft) then _add(ft) end
              end
            end
          else
            -- missing list -> skip
          end
        else
          if negative then
            excludeSet[tok] = true
          else
            if _existsFullType(tok) then _add(tok) end
          end
        end
      end
    end
  end

  local out = {}
  if includeList[1] ~= nil then
    for i = 1, #includeList do
      local ft = includeList[i]
      if not excludeSet[ft] then
        out[#out + 1] = ft
      end
    end
  end
  return out
end

-- Back-compat: array of fullTypes OR a single string token (e.g. "@GasTanks")
local function injectRecipeInputs(recipeName, itemListOrToken)
  local recipe = ScriptManager.instance:getCraftRecipe(recipeName)
  if not recipe then
    --print("[VRO] Recipe not found", recipeName)
    return
  end

  local tokens = (type(itemListOrToken) == "string") and { itemListOrToken } or (itemListOrToken or {})
  local validItems = _flattenTokens(tokens)

  if #validItems > 0 then
    local inputString = "{ inputs { item 1 [" .. table.concat(validItems, ";") .. "] mode:destroy, } }"
    recipe:Load(recipeName, inputString)
    --print("[VRO] Injected craftRecipe input for:", recipeName)
  else
    --print("[VRO] No valid inputs found, recipe unchanged.")
  end
end

-- Always add "VRO.recipefiller" as an input to prevent exploiting empty recipes
local function injectAllRecipeInputsOnce()
  if VRO._salvageInputsInjected then return end
  VRO._salvageInputsInjected = true

  injectRecipeInputs("SalvageVehicleDoors",
    { "@Door_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("SalvageLargeVehicleDoors",
    { "@DoorMilitary_All", "VRO.recipefiller" }
  )

  -- Contains normal and military trunk doors
  injectRecipeInputs("SalvageVehicleTrunkDoors",
    { "@TrunkDoor_All", "@TrunkDoorMilitary_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("SalvageVehicleHoods",
    { "@Hood_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("SalvageVehicleArmor",
    { "@MilitaryHood_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("SalvageVehicleGasTanks",
    { "@GasTank_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("SalvageVehicleGasTanksSmall",
    { "@GasTankSmall_All", "VRO.recipefiller" }
  )

  -- Contains normal and small mufflers
  injectRecipeInputs("SalvageVehicleMufflers",
    { "@SmallMuffler_All", "@Muffler_All", "VRO.recipefiller" }
  )

  -- Contains small, normal and military suspension
  injectRecipeInputs("SalvageVehicleSuspension",
    { "@SmallSuspension_All", "@Suspension_All", "@MilitarySuspension_All", "VRO.recipefiller" }
  )

  -- Contains small, normal and military brakes
  injectRecipeInputs("SalvageVehicleBrakes",
    { "@SmallBrake_All", "@Brake_All", "@MilitaryBrake_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("SalvageVehicleSeats",
    { "@CarSeat_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("SalvageVehicleTires",
    { "@Tire_All", "VRO.recipefiller" }
  )

  -- Contains bullbars and roofracks (+ some explicit items)
  injectRecipeInputs("SalvageVehicleBars",
    { "@Bullbar_All", "@RoofRack_All",
      "Base.M113FrontWindow1", "Base.M113FrontWindow2", "Base.M113FrontWindow3",
      "Base.M923SpareMount1", "Base.MH_MkII_guntower1", "Base.MH_MkII_guntower2", "Base.MH_MkII_guntower3",
      "Base.M998SpareMount_Item", "Base.M998SpareTireMount_Item", "Base.M35TarpFrame2",
      "Base.ShermanDriveSprocket2", "Base.ShermanRearSprocket2", "Base.ShermanHatch2", "VRO.recipefiller"
    }
  )

  injectRecipeInputs("SalvageVehicleSaddlebags",
    { "Base.ATAMotoBagBMW1", "Base.ATAMotoBagBMW2", "Base.ATAMotoHarleyBag",
      "Base.ATAMotoHarleyHolster", "Base.SS100topbag3", "Base.90pierceArrowHoses",
      "Base.FireDeptHosesMedium", "VRO.recipefiller"
    }
  )

  injectRecipeInputs("SalvageHardVehicleSaddlebags",
    { "@SaddlebagsHard_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("SalvageVehicleSoftTops",
    { "@SoftTops_All", "VRO.recipefiller" }
  )

  -- Contains panels, mudflaps and hubcaps
  injectRecipeInputs("SalvageVehiclePanelsSmall",
    { "@Panels_All", "@Hubcaps_All", "VRO.recipefiller" }
  )

  -- Contains light and battery parts
  injectRecipeInputs("SalvageVehicleElectronics",
    { "@Battery_All", "@LargeBattery_All", "@MiscElectronics_All", "@Light_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("SalvageWoodenVehicleParts",
    { "@WoodParts_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("SalvageLargeContainerTanks",
    { "@TankContainers_All", "VRO.recipefiller" }
  )

end

Events.OnInitWorld.Add(injectAllRecipeInputsOnce)
if isServer() then
  Events.OnGameBoot.Add(injectAllRecipeInputsOnce)
end

local SALVAGE_TIME_OPTIONS = {
  { recipe = "SalvageVehicleDoors"          , var = "VSO_SalvageTime_Doors", default = 600 },
  { recipe = "SalvageLargeVehicleDoors"     , var = "VSO_SalvageTime_DoorsMilitary", default = 700 },
  { recipe = "SalvageVehicleTrunkDoors"     , var = "VSO_SalvageTime_TrunkDoors", default = 500 },
  { recipe = "SalvageVehicleHoods"          , var = "VSO_SalvageTime_Hoods", default = 600 },
  { recipe = "SalvageVehicleArmor"          , var = "VSO_SalvageTime_HoodsMilitary", default = 800 },
  { recipe = "SalvageWoodenVehicleParts"    , var = "VSO_SalvageTime_Wooden", default = 700 },
  { recipe = "SalvageVehicleGasTanks"       , var = "VSO_SalvageTime_GasTanks", default = 700 },
  { recipe = "SalvageVehicleGasTanksSmall"  , var = "VSO_SalvageTime_GasTanksSmall", default = 500 },
  { recipe = "SalvageVehicleMufflers"       , var = "VSO_SalvageTime_Mufflers", default = 500 },
  { recipe = "SalvageVehicleSuspension"     , var = "VSO_SalvageTime_Suspension", default = 500 },
  { recipe = "SalvageVehicleBrakes"         , var = "VSO_SalvageTime_Brakes", default = 600 },
  { recipe = "SalvageVehicleSeats"          , var = "VSO_SalvageTime_Seats", default = 600 },
  { recipe = "SalvageVehicleTires"          , var = "VSO_SalvageTime_Tires", default = 600 },
  { recipe = "SalvageVehicleBars"           , var = "VSO_SalvageTime_Bars", default = 600 },
  { recipe = "SalvageVehicleSaddlebags"     , var = "VSO_SalvageTime_SaddlebagsFabric", default = 600 },
  { recipe = "SalvageHardVehicleSaddlebags" , var = "VSO_SalvageTime_SaddlebagsHard", default = 600 },
  { recipe = "SalvageVehicleSoftTops"       , var = "VSO_SalvageTime_SoftTops", default = 300 },
  { recipe = "SalvageVehiclePanelsSmall"    , var = "VSO_SalvageTime_Panels", default = 600 },
  { recipe = "SalvageLargeContainerTanks"   , var = "VSO_SalvageTime_ContainerTanks", default = 500 },
  { recipe = "SalvageVehicleElectronics"    , var = "VSO_SalvageTime_Electronics", default = 500 },
}

local function _salvageTimeFor(opt)
  if VRO and VRO.GetSalvageTime then
    return VRO.GetSalvageTime(opt.var, opt.default)
  end
  local default = tonumber(opt.default) or 100
  if SandboxVars then
    local v = tonumber(SandboxVars[opt.var])
    if v and v >= 1 then
      return math.floor(v)
    end
  end
  return default
end

local function injectRecipeTime(recipeName, timeValue)
  local recipe = ScriptManager.instance:getCraftRecipe(recipeName)
  if not recipe then
    --print("[VRO] Recipe not found (time)", recipeName)
    return
  end
  timeValue = tonumber(timeValue)
  if not timeValue or timeValue < 1 then return end
  recipe:Load(recipeName, "{ time = " .. tostring(math.floor(timeValue)) .. ", }")
  --print("[VRO] Set salvage time for", recipeName, "=", timeValue)
end

local function injectAllRecipeTimes()
  for i = 1, #SALVAGE_TIME_OPTIONS do
    local opt = SALVAGE_TIME_OPTIONS[i]
    injectRecipeTime(opt.recipe, _salvageTimeFor(opt))
  end
end

Events.OnGameStart.Add(injectAllRecipeTimes)
if isServer() and Events.OnServerStarted and Events.OnServerStarted.Add then
  Events.OnServerStarted.Add(injectAllRecipeTimes)
end