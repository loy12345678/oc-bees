local component = require("component")
local sides = require("sides")

local transposer = component.transposer

-- 🔧 USTAW TO
local chest = sides.left
local apiary = sides.right

-- 🧠 znajdź pszczoły w skrzynce
function findBee(keyword)
  for i = 1, transposer.getInventorySize(chest) or 0 do
    local stack = transposer.getStackInSlot(chest, i)
    if stack and stack.label and stack.label:find(keyword) then
      return i
    end
  end
  return nil
end

-- 📥 wkładanie pszczół
function insertBees()
  local princess = findBee("Princess") or findBee("Queen")
  local drone = findBee("Drone")

  if not princess or not drone then
    print("❌ Brak pszczół w skrzynce")
    return
  end

  transposer.transferItem(chest, apiary, 1, princess, 1)
  transposer.transferItem(chest, apiary, 1, drone, 2)

  print("🐝 Włożono pszczoły")
end

-- 📦 zbieranie bez crashy
function collect()
  local size = transposer.getInventorySize(apiary)

  if not size then
    print("❌ Nie widzę apiary")
    return
  end

  for i = 1, size do
    local stack = transposer.getStackInSlot(apiary, i)
    if stack then
      transposer.transferItem(apiary, chest, stack.size, i)
    end
  end
end

-- 🧪 sprawdza czy ul jest wolny
function isFree()
  local queen = transposer.getStackInSlot(apiary, 1)
  return queen == nil
end

-- 🔁 MAIN LOOP
while true do
  if isFree() then
    print("📦 Zbieram output...")
    collect()

    os.sleep(2)

    print("🔁 Nowa hodowla")
    insertBees()
  else
    print("⏳ Pracują pszczoły...")
  end

  os.sleep(10)
end
