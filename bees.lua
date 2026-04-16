local component = require("component")
local sides = require("sides")
local event = require("event")

local transposer = component.transposer

local chest = sides.left
local apiary = sides.right

local running = true

-- 📢 log
local function log(msg)
  print("[BEE] " .. msg)
end

-- 🛑 listener klawiatury (STOP)
local function keyListener()
  while true do
    local _, _, char, code = event.pull("key_down")

    -- ESC = stop
    if code == 1 then
      running = false
      log("🛑 STOP wciśnięty (ESC)")
      return
    end
  end
end

-- 📦 znajdź pszczoły
local function findBee(keyword)
  local size = transposer.getInventorySize(chest) or 0

  for i = 1, size do
    local stack = transposer.getStackInSlot(chest, i)
    if stack and stack.label and stack.label:lower():find(keyword:lower()) then
      return i
    end
  end

  return nil
end

-- 📥 wkładanie
local function insertBees()
  local princess = findBee("princess") or findBee("queen")
  local drone = findBee("drone")

  if not princess or not drone then
    log("❌ brak pszczół")
    return
  end

  transposer.transferItem(chest, apiary, 1, princess, 1)
  transposer.transferItem(chest, apiary, 1, drone, 2)

  log("🐝 włożono pszczoły")
end

-- 📦 zbieranie
local function collect()
  local size = transposer.getInventorySize(apiary) or 0

  for i = 1, size do
    local stack = transposer.getStackInSlot(apiary, i)
    if stack then
      transposer.transferItem(apiary, chest, stack.size, i)
    end
  end
end

-- 🧠 sprawdzenie czy ul wolny
local function isFree()
  local size = transposer.getInventorySize(apiary) or 0

  for i = 1, size do
    local stack = transposer.getStackInSlot(apiary, i)
    if stack and (stack.label:lower():find("queen") or stack.label:lower():find("princess")) then
      return false
    end
  end

  return true
end

-- 🚀 start listenera klawiatury
event.listen("key_down", function(_, _, code)
  if code == 1 then -- ESC
    running = false
    log("🛑 STOP aktywowany")
  end
end)

log("▶ START programu (ESC = STOP)")

-- 🔁 MAIN LOOP
while running do
  if isFree() then
    log("📦 zbieram")
    collect()
    os.sleep(2)

    log("🔁 nowa hodowla")
    insertBees()
  else
    log("⏳ pszczoły pracują")
  end

  os.sleep(10)
end

log("⛔ program zatrzymany")
