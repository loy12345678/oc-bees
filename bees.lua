local component = require("component")
local sides = require("sides")

local t = component.transposer

local chest = sides.left
local apiary = sides.right

local FRAME = "untreated frame"

local function log(msg)
  print("[BEE] " .. msg)
end

-- 🔍 znajdź item w skrzynce
local function findItem(name)
  local size = t.getInventorySize(chest) or 0

  for i = 1, size do
    local stack = t.getStackInSlot(chest, i)

    if stack and stack.label and stack.label:lower():find(name:lower()) then
      return i
    end
  end

  return nil
end

-- 🧬 prosty scoring genów
local function score(label)
  local l = label:lower()
  local s = 0

  if l:find("productive") then s = s + 50 end
  if l:find("fast") then s = s + 40 end
  if l:find("draconic") then s = s + 200 end
  if l:find("imperial") then s = s + 120 end
  if l:find("industrious") then s = s + 80 end

  if l:find("slow") then s = s - 20 end
  if l:find("decay") then s = s - 50 end

  return s
end

-- 🔎 wybór najlepszej pszczoły
local function findBest(keyword)
  local size = t.getInventorySize(chest) or 0

  local bestSlot = nil
  local bestScore = -999
  local bestLabel = ""

  for i = 1, size do
    local stack = t.getStackInSlot(chest, i)

    if stack and stack.label and stack.label:lower():find(keyword:lower()) then
      local s = score(stack.label)

      log("TEST " .. stack.label .. " => " .. s)

      if s > bestScore then
        bestScore = s
        bestSlot = i
        bestLabel = stack.label
      end
    end
  end

  if bestSlot then
    log("WYBRANO: " .. bestLabel .. " (" .. bestScore .. ")")
  end

  return bestSlot
end

-- 📦 wkładanie pszczół
local function insert()
  local queen = findBest("queen") or findBest("princess")
  local drone = findBest("drone")

  if not queen or not drone then
    log("BRAK PSZCZÓŁ")
    return
  end

  local size = t.getInventorySize(apiary) or 0
  local qSlot, dSlot

  for i = 1, size do
    if not t.getStackInSlot(apiary, i) then
      if not qSlot then
        qSlot = i
      else
        dSlot = i
        break
      end
    end
  end

  if not qSlot or not dSlot then
    log("BRAK SLOTÓW")
    return
  end

  t.transferItem(chest, apiary, 1, queen, qSlot)
  t.transferItem(chest, apiary, 1, drone, dSlot)

  log("START HODOWLI")
end

-- 📦 zbieranie
-- pomocnicze: znajdź slot testowy w skrzyni (nie-pszczeli)
local function findTestItem()
  local size = t.getInventorySize(chest) or 0

  for i = 1, size do
    local stack = t.getStackInSlot(chest, i)

    if stack and stack.label then
      local l = stack.label:lower()
      if not (l:find("queen") or l:find("princess") or l:find("drone")) then
        return i
      end
    end
  end

  return nil
end

local function findFreeChestSlot()
  local size = t.getInventorySize(chest) or 0
  for i = 1, size do
    if not t.getStackInSlot(chest, i) then
      return i
    end
  end
  return nil
end

-- sprawdza czy do danego slotu apairy da się włożyć przedmiot (bez trwalej zmiany)
local function canInsertToSlot(slot)
  local testSlot = findTestItem()
  if not testSlot then
    log("BRAK PRZEDMIOTU TESTOWEGO W SKRZYNI - nie mogę przetestować slotów")
    return nil
  end

  local stack = t.getStackInSlot(apiary, slot)

  -- gdy slot pusty: spróbuj włożyć testowy przedmiot i od razu cofnąć
  if not stack then
    local moved = t.transferItem(chest, apiary, 1, testSlot, slot)
    if moved and moved > 0 then
      t.transferItem(apiary, chest, moved, slot)
      return true
    else
      return false
    end
  end

  -- gdy slot zajęty: spróbuj wyjąć 1 sztukę do wolnego slotu w skrzyni, a potem włożyć z powrotem
  local free = findFreeChestSlot()
  if not free then
    log("BRAK WOLNEGO SLOTA W SKRZNI - pomijam test dla slotu " .. slot)
    return nil
  end

  local extracted = t.transferItem(apiary, chest, 1, slot, free)
  if not extracted or extracted == 0 then
    return false
  end

  local reinserted = t.transferItem(chest, apiary, extracted, free, slot)
  if reinserted and reinserted > 0 then
    return true
  else
    -- jeśli nie udało się włożyć z powrotem, spróbuj przemieścić przedmiot z powrotem gdziekolwiek
    t.transferItem(chest, apiary, extracted, free)
    return false
  end
end

-- wykryj sloty które da się wyciągnąć ale nie da się włożyć (extract-only)
local function detectExtractOnlySlots()
  local size = t.getInventorySize(apiary) or 0
  local result = {}

  for i = 1, size do
    local stack = t.getStackInSlot(apiary, i)
    if stack and stack.label then
      local canInsert = canInsertToSlot(i)
      if canInsert == false then
        table.insert(result, i)
        log("DETECTED EXTRACT-ONLY SLOT: " .. i .. " (" .. stack.label .. ")")
      end
    end
  end

  return result
end

-- 📦 zbieranie (przenosi tylko z slotów extract-only)
local function collect()
  local slots = detectExtractOnlySlots()
  if not slots or #slots == 0 then
    log("BRAK SLOTÓW EXTRACT-ONLY do zebrania")
    return
  end

  for _, i in ipairs(slots) do
    local stack = t.getStackInSlot(apiary, i)
    if stack then
      local moved = t.transferItem(apiary, chest, stack.size, i)
      if not moved or moved == 0 then
        log("TRANSFER NIEUDANY Z SLOTA " .. i)
      end
    end
  end
end

-- 📤 wyjmowanie pszczół
local function extractBees()
  local size = t.getInventorySize(apiary) or 0

  for i = 1, size do
    local stack = t.getStackInSlot(apiary, i)

    if stack and stack.label then
      local l = stack.label:lower()

      if l:find("queen") or l:find("princess") or l:find("drone") then
        t.transferItem(apiary, chest, stack.size, i)
        log("WYJĘTO: " .. stack.label)
      end
    end
  end
end

-- 🧠 czy cykl zakończony
local function isFree()
  local size = t.getInventorySize(apiary) or 0

  for i = 1, size do
    local stack = t.getStackInSlot(apiary, i)

    if stack and stack.label then
      local l = stack.label:lower()
      if l:find("queen") or l:find("princess") then
        return false
      end
    end
  end

  return true
end

-- 🧩 refill frames
local function refillFrames()
  local size = t.getInventorySize(apiary) or 0

  for i = 1, size do
    local stack = t.getStackInSlot(apiary, i)

    if not stack then
      local slot = findItem(FRAME)

      if slot then
        t.transferItem(chest, apiary, 1, slot, i)
        log("➕ frame do slotu " .. i)
      end
    end
  end
end

-- 🔁 LOOP
log("START SYSTEMU BEE AI")

while true do

  log("pszczoly pracuja")

  if isFree() then
    log("CYKL ZAKOŃCZONY")

    collect()
    extractBees()

    os.sleep(2)

    refillFrames()
    insert()
  end

  os.sleep(5)
end
