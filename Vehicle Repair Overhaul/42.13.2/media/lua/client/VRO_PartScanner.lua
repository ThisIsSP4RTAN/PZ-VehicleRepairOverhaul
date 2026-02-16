require "VRO_PartLists"

local VROPartScanner = {}

-- =========================
-- TOGGLES
-- =========================
-- Master toggle: if false, scanner does nothing
VROPartScanner.ENABLED = false

-- If true, do NOT print candidates that appear to come from BaseGame/vanilla
VROPartScanner.EXCLUDE_VANILLA = true

-- If true, use KEYWORDS to filter matches; if false, scan everything (still respects exclusions)
VROPartScanner.USE_KEYWORDS = false

-- If true, only include ScriptItems whose DisplayCategory is VehicleMaintenance
VROPartScanner.ONLY_VEHICLE_MAINTENANCE = true

-- If true, include tags in output (when available)
VROPartScanner.SHOW_TAGS = true

-- If >0, limit tags printed per item
VROPartScanner.MAX_TAGS = 0

-- =========================
-- FILTER LISTS
-- =========================

-- Customize these (lowercase; matching is case-insensitive)
VROPartScanner.KEYWORDS = {
  "trunk", "door", "hood", "windshield", "window", "seat", "tire", "wheel",
  "muffler", "suspension", "brake", "radiator", "battery", "gastank", "tailgate",
  "heater", "roof", "rack", "bumper", "bullbar", "fender", "mirror", "spoiler",
  "runflat", "divider", "sideskirt", "mudflap", "softtop", "sidestep", "lights",
  "windowarmor", "doorarmor", "windshieldarmor", "sidearmor", "louver", "rollbar",
  "frontlip", "barrier", "bodykit", "splitlip", "lids", "lid2", "lid3", "storage",
  "toolbox1", "toolbox2", "axle", "lugs", "side_wind", "boxlid", "stakes1", "stakes2",
  "stakes3",
}

-- Exclusions to avoid false positives (lowercase)
VROPartScanner.EXCLUDE_KEYWORDS = {
  "hoodie",
  "doorway",
  "windowframe",
  "seatbelt",
  "vambrace",
  "repairablewindows",
  "tirerubber",
  "tirerepair",
  "seatframe",
  "seatfoam",
  "seatfabric",
  "rc_tempsimmod",
  "bodyarmour",
  "shoulderpad",
  "sandals",
  "mov_",
  "stonewheel",
  "doorknob",
  "firecracker",
  "crackers",
  "tirepump",
  "tireiron",
  "tirepiece",
  "vest_bullet",
  "railroadtrack",
  "scrapweapon",
  "outdoorsman",
  "magazine",
  "chocolate",
  "book",
  "racket",
  "ornament",
  "greave",
  "bullet",
  "briefs_",
  "hat_",
  "vest_waterproof",
  "baseballcap",
  "headmirror",
  "swimtrunks",
  "longhandle_brake",
  "thightire",
  "cuirass_tire",
  "cudgel_brake",
  "lighter_battery",
  "batterybox",
  "carbatterycharger",
  "plank_brake",
  "m35a2bumperrear1",
  "viewportpack",
  "recipefiller",
  "fixaflat",
  "handleclassic",
  "handlemodern",
  "dontusethis",
  "hingelarge",
  "hingesmall",
  "rubberstrip",
  "steelrimlarge",
  "steelrimmedium",
  "steelrimsmall",
  "85chevycapricecabbarrier1",
  "91fordltdcabbarrier1",
  "92fordcvpicabbarrier1",
  "99fordcvpicabbarrier1",
  "firedepthosesmedium",
  "90piercearrowhoses",
  "92jeepyjwinch2",
  "87fordf700bumperrear2",
  "foamseal",
  "93fordcf8000brushes",
  "90fordf350ambseatrear2",
  "87fordb700rearseat2",
  "towbar",
}

-- If true, also match DisplayName (if available). FullType matching is always on.
VROPartScanner.MATCH_DISPLAYNAME = true

-- If >0, only print first N matches (still prints total count).
VROPartScanner.MAX_PRINT = 0

-- If true, prints matched keyword too (when USE_KEYWORDS=true).
VROPartScanner.SHOW_KEYWORD = true

local function _lc(s) return (s and tostring(s):lower()) or "" end

local function _hasKeyword(hayLower, keywords)
  for i = 1, #keywords do
    local k = keywords[i]
    if k and k ~= "" and hayLower:find(k, 1, true) then
      return k
    end
  end
  return nil
end

local function _isExcluded(fullTypeLower, displayLower)
  if _hasKeyword(fullTypeLower, VROPartScanner.EXCLUDE_KEYWORDS) then return true end
  if displayLower and _hasKeyword(displayLower, VROPartScanner.EXCLUDE_KEYWORDS) then return true end
  return false
end

local function _tryMethod(obj, methodName)
  if not obj then return nil end
  local ok, v = pcall(function()
    local f = obj[methodName]
    if f then return f(obj) end
    return nil
  end)
  if ok and v ~= nil and v ~= "" then return v end
  return nil
end

local function _buildPartSetFromVRO()
  local okCore, VRO = pcall(require, "VRO/Core")
  if not okCore or not VRO then
    print("[VRO][SCAN][WARN] Could not require 'VRO/Core'. Is Vehicle Repair Overhaul enabled?")
    return nil
  end

  local okPL = pcall(require, "VRO_PartLists")
  if not okPL then
    print("[VRO][SCAN][WARN] Could not require 'VRO_PartLists'. Adjust the require name in VRO_PartScanner.lua.")
  end

  local partLists = VRO.PartLists
  if type(partLists) ~= "table" then
    print("[VRO][SCAN][WARN] VRO.PartLists missing or not a table.")
    return nil
  end

  local set, total = {}, 0
  for _, list in pairs(partLists) do
    if type(list) == "table" then
      for i = 1, #list do
        local ft = list[i]
        if type(ft) == "string" and ft ~= "" and not set[ft] then
          set[ft] = true
          total = total + 1
        end
      end
    end
  end

  print(string.format("[VRO][SCAN] Loaded %d part entries from VRO.PartLists.", total))
  return set
end

local function _getScriptItemFullType(si)
  local v = _tryMethod(si, "getFullName")
  if v and v ~= "" then return tostring(v) end
  v = _tryMethod(si, "getFullType")
  if v and v ~= "" then return tostring(v) end
  v = _tryMethod(si, "getName")
  if v and v ~= "" then return tostring(v) end
  return nil
end

local function _getScriptItemDisplayName(si)
  local v = _tryMethod(si, "getDisplayName")
  if v and v ~= "" then return tostring(v) end
  return nil
end

local function _getScriptItemDisplayCategory(si)
  local v = _tryMethod(si, "getDisplayCategory")
  if v and v ~= "" then return tostring(v) end
  v = _tryMethod(si, "getDisplayCategoryString")
  if v and v ~= "" then return tostring(v) end
  v = _tryMethod(si, "getDisplayCategoryName")
  if v and v ~= "" then return tostring(v) end
  return nil
end

local function _isVehicleMaintenanceCategory(si)
  local dc = _getScriptItemDisplayCategory(si)
  if not dc then return false end
  local s = _lc(dc):gsub("%s+", "")
  return s == "vehiclemaintenance"
end

-- Tags extraction: best-effort
local function _collectTagsFromTagObject(tagObj, out)
  if not tagObj then return end

  -- If it's a string already
  if type(tagObj) == "string" then
    local s = tagObj
    for t in s:gmatch("[^;%s]+") do
      if t and t ~= "" then out[#out + 1] = t end
    end
    return
  end

  -- Many PZ collections support size()/get(i)
  if tagObj.size and tagObj.get then
    local ok, sz = pcall(function() return tagObj:size() end)
    if ok and type(sz) == "number" then
      for i = 0, sz - 1 do
        local ok2, v = pcall(function() return tagObj:get(i) end)
        if ok2 and v ~= nil then
          local s = tostring(v)
          if s ~= "" then out[#out + 1] = s end
        end
      end
      return
    end
  end

  -- Fallback: tostring and parse
  local s = tostring(tagObj)
  for t in s:gmatch("[^;%s]+") do
    if t and t ~= "" then out[#out + 1] = t end
  end
end

local function _getScriptItemTags(si)
  if not si then return nil end

  local tags = {}

  -- Try getTags()
  local v = _tryMethod(si, "getTags")
  if v ~= nil then
    _collectTagsFromTagObject(v, tags)
  end

  -- Sometimes tags live under a raw "Tags" value (rare)
  if #tags == 0 and si.Tags ~= nil then
    _collectTagsFromTagObject(si.Tags, tags)
  end

  if #tags == 0 then return nil end

  -- de-dupe, preserve order
  local seen, out = {}, {}
  for i = 1, #tags do
    local s = tostring(tags[i])
    if s ~= "" and not seen[s] then
      seen[s] = true
      out[#out + 1] = s
    end
  end

  -- Optional truncate
  local maxT = VROPartScanner.MAX_TAGS or 0
  if maxT > 0 and #out > maxT then
    local cut = {}
    for i = 1, maxT do cut[i] = out[i] end
    cut[#cut + 1] = string.format("...(+%d)", (#out - maxT))
    out = cut
  end

  return out
end

local function _getScriptItemOrigin(si, fullType)
  local v = _tryMethod(si, "getModID")
  if v and v ~= "" then return tostring(v) end

  local okM, m = pcall(function()
    return (si and si.getModule and si:getModule()) or nil
  end)
  if okM and m then
    local mid = _tryMethod(m, "getModID")
    if mid and mid ~= "" then return tostring(mid) end

    local mn = _tryMethod(m, "getName")
    if mn and mn ~= "" then
      if tostring(mn) == "Base" then return "BaseGame" end
      return tostring(mn)
    end
  end

  if fullType then
    local modPrefix = tostring(fullType):match("^([^%.]+)%.")
    if modPrefix then
      if modPrefix == "Base" then return "BaseGame" end
      return modPrefix
    end
  end

  return "Unknown"
end

local function _isVanillaOrigin(origin)
  if not origin then return false end
  local o = tostring(origin):lower()
  return (o == "basegame" or o == "base" or o == "pz-vanilla" or o:find("vanilla", 1, true) ~= nil)
end

function VROPartScanner.run()
    if not VROPartScanner.ENABLED then return end
    if VROPartScanner._ran then return end
    VROPartScanner._ran = true

  local partSet = _buildPartSetFromVRO()
  if not partSet then return end

  local sm = getScriptManager and getScriptManager() or nil
  if not sm or not sm.getAllItems then
    print("[VRO][SCAN][WARN] getScriptManager():getAllItems() not available.")
    return
  end

  local all = sm:getAllItems()
  if not all or not all.size then
    print("[VRO][SCAN][WARN] ScriptManager.getAllItems returned unexpected value.")
    return
  end

  local results = {} -- { fullType, origin, kw, tags[] }
  local seen = {}
  local totalItems = all:size()

  for idx = 0, totalItems - 1 do
    local si = all:get(idx)
    local fullType = _getScriptItemFullType(si)

    if fullType and not partSet[fullType] and not seen[fullType] then
      if VROPartScanner.ONLY_VEHICLE_MAINTENANCE and not _isVehicleMaintenanceCategory(si) then
      else
        local ftLower = _lc(fullType)

        local dn, dnLower = nil, nil
        if VROPartScanner.MATCH_DISPLAYNAME then
          dn = _getScriptItemDisplayName(si)
          dnLower = dn and _lc(dn) or nil
        end

        -- Exclusion keywords
        if not _isExcluded(ftLower, dnLower) then
          local origin = _getScriptItemOrigin(si, fullType)

          -- Optional vanilla filter
          if not (VROPartScanner.EXCLUDE_VANILLA and _isVanillaOrigin(origin)) then
            local matchedKeyword = nil

            if VROPartScanner.USE_KEYWORDS then
              matchedKeyword = _hasKeyword(ftLower, VROPartScanner.KEYWORDS)
              if not matchedKeyword and dnLower then
                matchedKeyword = _hasKeyword(dnLower, VROPartScanner.KEYWORDS)
              end
            else
              -- keyword filtering disabled => accept everything (still respects exclusions & vanilla toggle)
              matchedKeyword = ""
            end

            if matchedKeyword ~= nil then
              seen[fullType] = true
              results[#results + 1] = {
                fullType = fullType,
                origin   = origin,
                kw       = matchedKeyword,
                tags     = VROPartScanner.SHOW_TAGS and _getScriptItemTags(si) or nil,
              }
            end
          end
        end
      end
    end
  end

  table.sort(results, function(a,b) return a.fullType < b.fullType end)

  print(string.format(
    "[VRO][SCAN] Candidates not in VRO.PartLists: %d (scanned %d items). useKeywords=%s excludeVanilla=%s onlyVehicleMaintenance=%s showTags=%s",
    #results, totalItems,
    tostring(VROPartScanner.USE_KEYWORDS),
    tostring(VROPartScanner.EXCLUDE_VANILLA),
    tostring(VROPartScanner.ONLY_VEHICLE_MAINTENANCE),
    tostring(VROPartScanner.SHOW_TAGS)
  ))

  local limit = VROPartScanner.MAX_PRINT
  if limit == nil or limit < 0 then limit = 0 end

  for i = 1, #results do
    if limit > 0 and i > limit then
      print(string.format("[VRO][SCAN] (truncated output at %d items; total=%d)", limit, #results))
      break
    end

    local r = results[i]
    local tagStr = ""
    if VROPartScanner.SHOW_TAGS and r.tags and #r.tags > 0 then
      tagStr = "  tags=" .. table.concat(r.tags, ";")
    end

    if VROPartScanner.USE_KEYWORDS and VROPartScanner.SHOW_KEYWORD then
      print(string.format("[VRO][SCAN]   %s  (from=%s, kw=%s)%s", r.fullType, r.origin, tostring(r.kw), tagStr))
    else
      print(string.format("[VRO][SCAN]   %s  (from=%s)%s", r.fullType, r.origin, tagStr))
    end
  end
end

Events.OnGameStart.Add(function()
  VROPartScanner.run()
end)

return VROPartScanner