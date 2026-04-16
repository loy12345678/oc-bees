local component = require("component")
local sides = require("sides")

local t = component.transposer

local chest = sides.left
local apiary = sides.right

local function log(msg)
  print("[BEE] " .. msg)
end

-- 🔍 znajdź pszczoły w skrzynce
local function findBee(name)
  local size = t.getInventorySize(chest) or 0

  for i = 1, size do
    local stack = t.getStackInSlot(chest, i)

    if stack and stack.label then
      if stack.label:lower():find(name:lower()) then
        return i
      end
    end
  end

  return nil
end

-- 📦 czy ul wolny
local function isFree()
  local size = t.getInventorySize(apiary) or 0

  for i = 1, size do
    local stack = t.getStackInSlot(apiary, i)

    if stack and stack.label then
      if stack.label:lower():find("queen")
      or stack.label:lower():find("princess") then
        return false
      end
    end
  end

  return true
end

-- 📥 wkładanie pszczół
local function insert()
  local princess = findBee("princess") or findBee("queen")
  local drone = findBee("drone")

  if not princess or not drone then
    log("BRAK PSZCZÓŁ W SKRZYNCE")
    return
  end

  local size = t.getInventorySize(apiary) or 0
  local pSlot, dSlot

  for i = 1, size do
    if not t.getStackInSlot(apiary, i) then
      if not pSlot then
        pSlot = i
      else
        dSlot = i
        break
      end
    end
  end

  if not pSlot or not dSlot then
    log("BRAK WOLNYCH SLOTÓW")
    return
  end

  t.transferItem(chest, apiary, 1, princess, pSlot)
  t.transferItem(chest, apiary, 1, drone, dSlot)

  log("Włożono pszczoły ✔")
end

-- 📦 zbieranie
local function collect()
  local size = t.getInventorySize(apiary) or 0

  for i = 1, size do
    local stack = t.getStackInSlot(apiary, i)

    if stack then
      t.transferItem(apiary, chest, stack.size, i)
    end
  end
end

-- 🔁 LOOP
log("START HODOWLI")

while true do
  if isFree() then
    log("UL WOLNY → zbieram")
    collect()

    os.sleep(2)

    log("START NOWEJ HODOWLI")
    insert()
  else
    log("PSZCZOŁY PRACUJĄ")
  end

  os.sleep(10)
end
