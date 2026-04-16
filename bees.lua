local component = require("component")
local sides = require("sides")

local transposer = component.transposer

local chest = sides.left
local apiary = sides.right

-- 📢 LOG system
local function log(msg)
  print("[BEE] " .. msg)
end

local function safeSize(side)
  return transposer.getInventorySize(side) or 0
end

function findBee(keyword)
  log("Skanuję skrzynkę...")
  local size = safeSize(chest)

  for i = 1, size do
    local stack = transposer.getStackInSlot(chest, i)
    if stack and stack.label and stack.label:find(keyword) then
      log("Znaleziono: " .. stack.label .. " w slocie " .. i)
      return i
    end
  end

  log("Nie znaleziono: " .. keyword)
  return nil
end

function insertBees()
  log("Wkładanie pszczół...")

  local princess = findBee("Princess") or findBee("Queen")
  local drone = findBee("Drone")

  if not princess or not drone then
    log("BRAK pszczół!")
    return
  end

  local size = safeSize(apiary)
  local qSlot, dSlot = nil, nil

  for i = 1, size do
    if not transposer.getStackInSlot(apiary, i) then
      if not qSlot then
        qSlot = i
      elseif not dSlot then
        dSlot = i
        break
      end
    end
  end

  if not qSlot or not dSlot then
    log("BRAK wolnych slotów!")
    return
  end

  transposer.transferItem(chest, apiary, 1, princess, qSlot)
  transposer.transferItem(chest, apiary, 1, drone, dSlot)

  log("Włożono pszczoły ✔")
end

function collect()
  log("Zbieranie outputu...")

  local size = safeSize(apiary)

  for i = 1, size do
    local stack = transposer.getStackInSlot(apiary, i)
    if stack then
      transposer.transferItem(apiary, chest, stack.size, i)
    end
  end
end

function isFree()
  local size = safeSize(apiary)

  for i = 1, size do
    local stack = transposer.getStackInSlot(apiary, i)
    if stack and stack.label and (stack.label:find("Queen") or stack.label:find("Princess")) then
      return false
    end
  end

  return true
end

-- 🔁 MAIN LOOP
while true do
  if isFree() then
    log("Ul wolny → zbieram")
    collect()

    os.sleep(2)

    log("Start nowej hodowli")
    insertBees()
  else
    log("Pszczoły pracują...")
  end

  os.sleep(10)
end
