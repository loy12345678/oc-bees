local component = require("component")
local sides = require("sides")

local transposer = component.transposer

-- USTAWIENIA (ZMIEN JEŚLI TRZEBA)
local chest = sides.left
local apiary = sides.right

local SLOT_QUEEN = 1
local SLOT_DRONE = 2

-- znajdź pszczołę w skrzynce
function findBee(keyword)
  for i = 1, 100 do
    local stack = transposer.getStackInSlot(chest, i)
    if stack and stack.label and stack.label:find(keyword) then
      return i
    end
  end
  return nil
end

-- wkładanie pszczół
function insertBees()
  local princess = findBee("Princess") or findBee("Queen")
  local drone = findBee("Drone")

  if not princess or not drone then
    print("❌ Brak pszczół w skrzynce")
    return false
  end

  transposer.transferItem(chest, apiary, 1, princess, SLOT_QUEEN)
  transposer.transferItem(chest, apiary, 1, drone, SLOT_DRONE)

  print("🐝 Włożono pszczoły")
  return true
end

-- zbieranie produktów
function collect()
  for i = 3, 12 do
    local stack = transposer.getStackInSlot(apiary, i)
    if stack then
      transposer.transferItem(apiary, chest, stack.size, i)
    end
  end
end

-- sprawdza czy ul jest wolny
function isFree()
  return transposer.getStackInSlot(apiary, SLOT_QUEEN) == nil
end

-- MAIN LOOP
while true do
  if isFree() then
    print("📦 Zbieram output...")
    collect()

    os.sleep(2)

    print("🔁 Start nowej hodowli")
    insertBees()
  else
    print("⏳ Pszczoły pracują...")
  end

  os.sleep(10)
end
