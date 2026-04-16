local component = require("component")
local sides = require("sides")

local transposer = component.transposer

local chest = sides.left
local apiary = sides.right

-- 📢 log system
local function log(msg)
  print("[DEBUG] " .. msg)
end

-- 🔍 sprawdza inventory
local function checkSide(name, side)
  log("Sprawdzam: " .. name)

  local size = transposer.getInventorySize(side)

  if not size then
    log("❌ " .. name .. " = NIE WIDZĘ (nil)")
    return false
  end

  log("✔ " .. name .. " widoczny, slotów: " .. size)
  return true
end

-- 🧪 test stacków
local function scanSide(name, side)
  log("Skanuję: " .. name)

  local size = transposer.getInventorySize(side) or 0

  for i = 1, size do
    local stack = transposer.getStackInSlot(side, i)

    if stack then
      log(name .. " SLOT " .. i .. " -> " .. (stack.label or "UNKNOWN"))
    end
  end
end

-- 🚀 START TESTU
log("=== START DIAGNOSTYKI ===")

local chestOK = checkSide("CHEST (LEFT)", chest)
local apiaryOK = checkSide("APIARY (RIGHT)", apiary)

log("-------------------------")

if chestOK then
  scanSide("CHEST", chest)
end

log("-------------------------")

if apiaryOK then
  scanSide("APIARY", apiary)
end

log("=== KONIEC DIAGNOSTYKI ===")
