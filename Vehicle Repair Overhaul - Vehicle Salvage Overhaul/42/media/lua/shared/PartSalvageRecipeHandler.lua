VRO = VRO or {}
VRO.PartLists = VRO.PartLists or {}

local function _mergeLists(dst, src)
  if type(dst) ~= "table" or type(src) ~= "table" then return end
  for k, v in pairs(src) do
    if type(k) == "string" and type(v) == "table" then
      dst[k] = v
    end
  end
end

local function _loadSharedPartListsOnce()
  if VRO._partListsLoaded then return end
  VRO._partListsLoaded = true

  local ok, mod = pcall(require, "VRO_PartLists")
  if ok and type(mod) == "table" then
    _mergeLists(VRO.PartLists, mod)
  end

  if type(_G.VRO) == "table" and type(_G.VRO.PartLists) == "table" then
    _mergeLists(VRO.PartLists, _G.VRO.PartLists)
  end
end

local function _getPartListByName(name)
  _loadSharedPartListsOnce()
  if type(VRO.PartLists[name]) == "table" then return VRO.PartLists[name] end
  local V = rawget(_G, "VRO")
  if V then
    if type(V.PartLists) == "table" and type(V.PartLists[name]) == "table" then return V.PartLists[name] end
    if type(V.Lists)     == "table" and type(V.Lists[name])     == "table" then return V.Lists[name]     end
  end
  return nil
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
      table.insert(includeList, ft)
    end
  end

  for _, tok in ipairs(tokens or {}) do
    if type(tok) == "string" then
      local negative = false
      if tok:sub(1,1) == "!" then
        negative = true
        tok = tok:sub(2)
      end

      if tok:sub(1,1) == "@" then
        local listName = tok:sub(2)
        local lst = _getPartListByName(listName)
        if lst then
          if negative then
            for _, ft in ipairs(lst) do excludeSet[ft] = true end
          else
            for _, ft in ipairs(lst) do
              if _existsFullType(ft) then _add(ft) end
            end
          end
        else
          print(("[VRO] [Salvage] Missing part list @%s (skipped)"):format(listName))
        end
      else
        if negative then
          excludeSet[tok] = true
        else
          if _existsFullType(tok) then _add(tok) else
            print(("[VRO] [Salvage] Missing item (skipped): %s"):format(tok))
          end
        end
      end
    end
  end

  local out = {}
  for _, ft in ipairs(includeList) do
    if not excludeSet[ft] then table.insert(out, ft) end
  end
  return out
end

-- Back-compat: array of fullTypes OR a single string token (e.g. "@GasTanks")
local function injectRecipeInputs(recipeName, itemListOrToken)
  local recipe = ScriptManager.instance:getCraftRecipe(recipeName)
  if not recipe then
    print("[VRO] Recipe not found", recipeName)
    return
  end

  local tokens = (type(itemListOrToken) == "string") and { itemListOrToken } or (itemListOrToken or {})
  local validItems = _flattenTokens(tokens)

  if #validItems > 0 then
    local inputString = "{ inputs { item 1 [" .. table.concat(validItems, ";") .. "] mode:destroy, } }"
    recipe:Load(recipeName, inputString)
    print("[VRO] Injected craftRecipe input for:", recipeName)
  else
    print("[VRO] No valid inputs found, recipe unchanged.")
  end
end

-- Always add "VRO.recipefiller" as an input to prevent exploiting empty recipes
local function injectAllRecipeInputs()

  injectRecipeInputs("Salvage Vehicle Doors",
    { "@Door_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("Salvage Military or Large Vehicle Doors",
    { "@DoorMilitary_All", "VRO.recipefiller" }
  )

  -- Contains normal and military trunk doors
  injectRecipeInputs("Salvage Vehicle Trunk Doors",
    { "@TrunkDoor_All", "@TrunkDoorMilitary_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("Salvage Vehicle Hoods or Metal Covers",
    { "@Hood_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("Salvage Military Vehicle Hoods or Armor",
    { "@MilitaryHood_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("Salvage Vehicle Gas Tanks",
    { "@GasTank_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("Salvage Small Vehicle Gas Tanks",
    { "@GasTankSmall_All", "VRO.recipefiller" }
  )

  -- Contains normal and small mufflers
  injectRecipeInputs("Salvage Vehicle Mufflers",
    { "@SmallMuffler_All", "@Muffler_All", "VRO.recipefiller" }
  )

  -- Contains small, normal and military suspension
  injectRecipeInputs("Salvage Vehicle Suspension",
    { "@SmallSuspension_All", "@Suspension_All", "@MilitarySuspension_All", "VRO.recipefiller" }
  )

  -- Contains small, normal and military brakes
  injectRecipeInputs("Salvage Vehicle Brakes",
    { "@SmallBrake_All", "@Brake_All", "@MilitaryBrake_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("Salvage Vehicle Seats",
    { "@CarSeat_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("Salvage Vehicle Tires",
    { "@Tire_All", "VRO.recipefiller" }
  )

  -- Contains bullbars and roofracks (+ some explicit items)
  injectRecipeInputs("Salvage Vehicle Bars",
    { "@Bullbar_All", "@RoofRack_All",
      "Base.M113FrontWindow1", "Base.M113FrontWindow2", "Base.M113FrontWindow3",
      "Base.M923SpareMount1", "Base.MH_MkII_guntower1", "Base.MH_MkII_guntower2", "Base.MH_MkII_guntower3",
      "Base.M998SpareMount_Item", "Base.M998SpareTireMount_Item", "Base.M35TarpFrame2",
      "Base.ShermanDriveSprocket2", "Base.ShermanRearSprocket2", "Base.ShermanHatch2", "VRO.recipefiller"
    }
  )

  injectRecipeInputs("Salvage Vehicle Saddlebags or Misc Fabrics",
    { "Base.ATAMotoBagBMW1", "Base.ATAMotoBagBMW2", "Base.ATAMotoHarleyBag",
      "Base.ATAMotoHarleyHolster", "Base.SS100topbag3", "Base.90pierceArrowHoses",
      "Base.FireDeptHosesMedium", "VRO.recipefiller"
    }
  )

  injectRecipeInputs("Salvage Hard Vehicle Saddlebags",
    { "@SaddlebagsHard_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("Salvage Vehicle Soft-tops",
    { "@SoftTops_All", "VRO.recipefiller" }
  )

  -- Contains panels and mudflaps
  injectRecipeInputs("Salvage Small Misc Vehicle Panels",
    { "@Panels_All", "VRO.recipefiller" }
  )

  -- Contains light and battery parts
  injectRecipeInputs("Salvage Vehicle Electronics",
    { "@Battery_All", "@LargeBattery_All", "@Light_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("Salvage Wooden Vehicle Parts",
    { "@WoodParts_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("Salvage Large Container Tanks",
    { "@TankContainers_All", "VRO.recipefiller" }
  )

  injectRecipeInputs("",
    { }
  )
end

Events.OnInitWorld.Add(injectAllRecipeInputs)
if isServer() then
    Events.OnGameBoot.Add(injectAllRecipeInputs)
end