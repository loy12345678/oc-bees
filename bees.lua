local component = require("component")
local sides = require("sides")

local t = component.transposer

local chest = sides.left
local apiary = sides.right

local function log(msg)
  print("[BEE] " .. msg)
end

-- 🔧 TEST STARTU
log("START PROGRAMU")

-- 🧪 TEST: czy w ogóle działa Lua
log("Lua działa ✔")

-- 🔌 TEST INVENTORY
local function testSide(name, side)
  local size = t.getInventorySize(side)

  if not size then
    log(name .. " = ❌ NIE WIDZĘ (nil)")
    return false
  end

  log(name .. " = ✔ widzę, slotów: " .. size)
  return true
end

local chestOK = testSide("CHEST (LEFT)", chest)
local apiaryOK = testSide("APIARY (RIGHT)", apiary)

-- 📦 SKAN
local function scan(name, side)
  log("SKAN: " .. name)

  local size = t.getInventorySize(side) or 0
  local found = false

  for i = 1, size do
    local stack = t.getStackInSlot(side, i)

    if stack then
      found = true
      log(name .. " slot " .. i .. " -> " .. (stack.label or "UNKNOWN") .. " x" .. (stack.size or 0))
    end
  end

  if not found then
    log(name .. " -> pusty / brak widocznych itemów")
  end
end

if chestOK then scan("CHEST", chest) end
if apiaryOK then scan("APIARY", apiary) end

log("=== KONIEC TESTU ===")

-- 🔁 minimalny loop (żeby widzieć że żyje)
while true do
  log("tick...")
  os.sleep(5)
end
