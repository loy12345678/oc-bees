local component = require("component")
local sides = require("sides")

local t = component.transposer

local chest = sides.left
local apiary = sides.right

local function log(msg)
  print("[BEE] " .. msg)
end

-- 🔍 sprawdź inventory
local function check(name, side)
  local size = t.getInventorySize(side)

  if not size then
    log("❌ " .. name .. " NIE WIDZĘ (nil)")
    return false
  end

  log("✔ " .. name .. " widoczny, slotów: " .. size)
  return true
end

-- 📦 skan inventory
local function scan(name, side)
  local size = t.getInventorySize(side) or 0

  log("📦 SKAN: " .. name)

  for i = 1, size do
    local stack = t.getStackInSlot(side, i)
    if stack then
      log(name .. " slot " .. i .. " -> " .. (stack.label or "UNKNOWN") .. " x" .. (stack.size or 0))
    end
  end
end

-- 📥 znajdź pszczoły
local function findBee(keyword)
  local size = t.getInventorySize(chest) or 0

  for i = 1, size do
    local stack = t.getStackInSlot(chest, i)

    if stack and stack.label then
      if stack.label:lower():find(keyword:lower()) then
        log("🔎 znaleziono " .. stack.label .. " w slocie " .. i)
        return i
      end
    end
  end

  log("❌ brak: " .. keyword)
  return nil
end

-- 📥 wkładanie pszczół
local function insertBees()
  log("📥 wkładam pszczoły")

  local princess = findBee("princess") or findBee("queen")
  local drone = findBee("drone")

  if not princess or not drone then
    log("❌ brak pszczół do insert")
    return
  end

  local size = t.getInventorySize(apiary) or 0

  local qSlot, dSlot = nil, nil

  for i = 1, size do
    if not t.getStackInSlot(apiary, i) then
      if not qSlot then
        qSlot = i
      elseif not dSlot then
        dSlot = i
        break
      end
    end
  end

  if not qSlot or not dSlot then
    log("❌ brak wolnych slotów w apiary")
    return
  end

  t.transferItem(chest, apiary, 1, princess, qSlot)
  t.transferItem(chest, apiary, 1, drone, dSlot)

  log("✔ pszczoły włożone")
end

-- 📦 zbieranie
local function collect()
  log("📦 zbieram output")

  local size = t.getInventorySize(apiary) or 0

  for i = 1, size do
    local stack = t.getStackInSlot(apiary, i)
    if stack then
      t.transferItem(apiary, chest, stack.size, i)
    end
  end
end

-- 🧠 czy ul wolny
local function isFree()
  local size = t.getInventorySize(apiary) or 0

  for i = 1, size do
    local stack = t.getStackInSlot(apiary, i)

    if stack and stack.label then
      if stack.label:lower():find("queen") or stack.label:lower():find("princess") then
        return false
      end
    end
  end

  return true
end

-- 🚀 START DIAGNOSTYKI
log("=== START ===")

local chestOK = check("CHEST (LEFT)", chest)
local apiaryOK = check("APIARY (RIGHT)", apiary)

log("------------------")

if chestOK then
  scan("CHEST", chest)
end

log("------------------")

if apiaryOK then
  scan("APIARY", apiary)
end

log("==================")

-- 🔁 LOOP
while true do
  if isFree() then
    log("📦 wolny ul → zbieram")
    collect()

    os.sleep(2)

    log("🔁 start nowej hodowli")
    insertBees()
  else
    log("⏳ pszczoły pracują")
  end

  os.sleep(10)
end
