local component = require("component")
local sides = require("sides")

local t = component.transposer

-- Konfiguracja łańcucha modułów: od skrzyni (index 1) do pasieki (ostatni index).
-- Możesz dodać więcej modułów między skrzynką a pasieką, np. {sides.left, sides.front, sides.right}
local CHAIN = {sides.left, sides.right}

local chest = CHAIN[1]
local apiary = CHAIN[#CHAIN]

-- Opcjonalna konfiguracja: możesz wskazać konkretne sloty w skrzyni
-- które będą używane jako slot testowy i wolny.
-- Ustaw na nil żeby użyć automatycznego wyszukiwania.
local TEST_CHEST_SLOT = nil
local FREE_CHEST_SLOT = nil

local FRAME = "untreated frame"

local function log(msg)
  print("[BEE] " .. msg)
end

-- opcjonalna integracja z zewnętrznym skanerem (szukaj poprzez component.list)
local scanner = nil
local scanner_name = ""

-- najpierw wylistuj wszystkie dostępne komponenty
local allComponents = {}
for name, addr in pairs(component.list()) do
  table.insert(allComponents, name)
end

log("Available components: " .. table.concat(allComponents, ", "))

-- szukaj skanera w dostępnych komponentach - wypisz każde sprawdzenie
local scannerComponent = nil
for name, addr in pairs(component.list()) do
  log("Checking component: " .. name .. " (addr: " .. addr .. ")")
  if name:find("scanner") or name:find("analyzer") or name:find("gt") then
    log("  -> Found potential scanner: " .. name)
    scannerComponent = name
    break
  end
end

-- spróbuj załadować znaleziony skaner
if scannerComponent then
  log("Loading scanner: " .. scannerComponent)
  scanner = component.proxy(component.list(scannerComponent)())
  scanner_name = scannerComponent
  if scanner then
    log("Scanner loaded successfully")
  else
    log("Failed to load scanner proxy")
  end
else
  log("No scanner component found in component.list()")
end

local SCAN_METHODS = {"scan","scanStack","analyze","getStack","getItem","getItemMeta","getNBT"}

log("Available components: " .. table.concat(allComponents, ", "))

if scanner then
  local avail = {}
  for _, m in ipairs(SCAN_METHODS) do if scanner[m] then table.insert(avail, m) end end
  log("Scanner detected: " .. scanner_name .. " (" .. tostring(scanner) .. "); available methods: " .. (next(avail) and table.concat(avail, ", ") or "(none)"))
else
  log("No scanner component detected (scanner=nil)")
end

local function tryScan(side, slot)
  if not scanner then return nil end
  for _, m in ipairs(SCAN_METHODS) do
    log("tryScan: trying method '" .. m .. "' on slot " .. tostring(slot))
    local fn = scanner[m]
    if not fn then
      log("tryScan: method '" .. m .. "' not present on scanner")
    else
      -- spróbuj różnych sygnatur: (side, slot) lub (slot)
      local ok, res = pcall(fn, scanner, side, slot)
      if not ok then
        log("tryScan: method '" .. m .. "' raised, retrying with (slot) signature")
        ok, res = pcall(fn, scanner, slot)
      end
      if ok and res then
        log("tryScan: method '" .. m .. "' returned data for slot " .. tostring(slot))
        return res
      else
        log("tryScan: method '" .. m .. "' returned no data for slot " .. tostring(slot))
      end
    end
  end

  log("tryScan: no method produced data for slot " .. tostring(slot))
  return nil
end

-- skaner dla slotów apairy (historyczna nazwa)
local function tryScanSlot(slot)
  return tryScan(apiary, slot)
end

-- cache wyników skanowania dla skrzyni (slot -> scan string/table)
local scannedChest = {}

-- przeskanuj wszystkie nieskanowane pszczoły w skrzyni i zapisz wynik w cached
local function scanChestUnscanned()
  if not scanner then
    log("Brak skanera - pomijam skanowanie skrzyni")
    return
  end

  local size = t.getInventorySize(chest) or 0
  for i = 1, size do
    if not scannedChest[i] then
      local stack = t.getStackInSlot(chest, i)
      if stack and stack.label then
        local l = stack.label:lower()
        if l:find("queen") or l:find("princess") or l:find("drone") then
          local scan = tryScan(chest, i)
          if scan then
            local stext = scanToString(scan)
            scannedChest[i] = stext or true
            log("ZESKANOWANO slot " .. i .. " => " .. (stext or "<dane binarne>"))
          else
            scannedChest[i] = false
            log("BRAK DANYCH SKANERA DLA SLOTA " .. i)
          end
        end
      end
    end
  end
end

-- konwertuje wynik skanera (table/string) do jednej tekstowej reprezentacji
local function scanToString(scan)
  if not scan then return nil end
  if type(scan) == "string" then return scan end
  if type(scan) ~= "table" then return tostring(scan) end

  local parts = {}
  local function collect(v)
    if not v then return end
    if type(v) == "string" then table.insert(parts, v)
    elseif type(v) == "number" then table.insert(parts, tostring(v))
    elseif type(v) == "table" then
      for k, vv in pairs(v) do collect(vv) end
    else table.insert(parts, tostring(v)) end
  end

  -- common keys
  local keys = {"displayName","name","label","genome","genomeText","analyzed","attributes","species"}
  for _, k in ipairs(keys) do
    if scan[k] then collect(scan[k]) end
  end

  -- collect any remaining values
  for k, v in pairs(scan) do collect(v) end

  return table.concat(parts, " ")
end

-- transfer przez łańcuch modułów (próbujemy hopować przez każdy moduł)
-- bezpieczny wrapper wokół transferItem (chroni pcall i różne sygnatury)
local function safeTransfer(fromSide, toSide, count, fromSlot, toSlot)
  local fn = function()
    if fromSlot and toSlot then
      return t.transferItem(fromSide, toSide, count, fromSlot, toSlot)
    elseif fromSlot then
      return t.transferItem(fromSide, toSide, count, fromSlot)
    else
      return t.transferItem(fromSide, toSide, count)
    end
  end

  local ok, res = pcall(fn)
  if not ok then
    log("ERROR transfer failed: " .. tostring(res))
    return 0
  end
  return res or 0
end

local function transferAcrossChain(srcIdx, dstIdx, count, srcSlot, dstSlot)
  if srcIdx == dstIdx then return 0 end
  local step = srcIdx < dstIdx and 1 or -1
  local moved = 0
  local curSlot = srcSlot

  local i = srcIdx
  while i ~= dstIdx do
    local fromSide = CHAIN[i]
    local toSide = CHAIN[i + step]

    local toSlot = nil
    if (i + step) == dstIdx then
      toSlot = dstSlot
      -- jeśli celem jest chest i nie mamy docelowego slotu, spróbuj znaleźć wolny
      if toSlot == nil and CHAIN[i + step] == chest then
        toSlot = findFreeChestSlot()
      end
    end

    local movedNow = safeTransfer(fromSide, toSide, count, curSlot, toSlot)
    if not movedNow or movedNow == 0 then
      return 0
    end

    moved = movedNow
    -- po pierwszym hopie zazwyczaj nie znamy dokładnego slotu w pośrednim transposerze
    -- więc ustawiamy curSlot na toSlot jeśli został jawnie określony, w przeciwnym razie nil
    curSlot = toSlot
    i = i + step
  end

  return moved
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

  -- przeskanuj wczesnie nieskanowane pszczoly w skrzyni
  scanChestUnscanned()

  for i = 1, size do
    local stack = t.getStackInSlot(chest, i)

    if stack and stack.label and stack.label:lower():find(keyword:lower()) then
      -- najpierw sprawdź cache skanera dla tego slotu
      local scanText = nil
      if scannedChest[i] and scannedChest[i] ~= false then
        scanText = scannedChest[i]
      else
        -- fallback: spróbuj szybciej zeskanować na żądanie
        local scan = tryScan(chest, i)
        scanText = scanToString(scan)
        if scanText then scannedChest[i] = scanText end
      end

      local s
      if scanText and scanText:lower():find(keyword:lower()) then
        s = score(scanText)
        log("SCAN TEST " .. (scanText or stack.label) .. " => " .. s)
      else
        s = score(stack.label)
        log("LABEL TEST " .. stack.label .. " => " .. s)
      end

      if s > bestScore then
        bestScore = s
        bestSlot = i
        bestLabel = scanText or stack.label
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

  transferAcrossChain(1, #CHAIN, 1, queen, qSlot)
  transferAcrossChain(1, #CHAIN, 1, drone, dSlot)

  log("START HODOWLI")
end

-- 📦 zbieranie
-- pomocnicze: znajdź slot testowy w skrzyni (nie-pszczeli)
local function findTestItem()
  -- jeśli skonfigurowano statyczny slot testowy, użyj go jeśli pasuje
  if TEST_CHEST_SLOT then
    local stack = t.getStackInSlot(chest, TEST_CHEST_SLOT)
    if stack and stack.label then
      local l = stack.label:lower()
      if not (l:find("queen") or l:find("princess") or l:find("drone")) then
        return TEST_CHEST_SLOT
      end
    end
    return nil
  end

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
  -- jeśli ustawiono statyczny wolny slot, użyj go jeśli jest pusty
  if FREE_CHEST_SLOT then
    if not t.getStackInSlot(chest, FREE_CHEST_SLOT) then
      return FREE_CHEST_SLOT
    else
      return nil
    end
  end

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

  -- gdy slot pusty: spróbuj włożyć testowy przedmiot i od razu cofnąć (przez łańcuch)
  if not stack then
    local moved = transferAcrossChain(1, #CHAIN, 1, testSlot, slot)
    if moved and moved > 0 then
      transferAcrossChain(#CHAIN, 1, moved, slot)
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

  local extracted = transferAcrossChain(#CHAIN, 1, 1, slot, free)
  if not extracted or extracted == 0 then
    return false
  end

  local reinserted = transferAcrossChain(1, #CHAIN, extracted, free, slot)
  if reinserted and reinserted > 0 then
    return true
  else
    -- jeśli nie udało się włożyć z powrotem, spróbuj przemieścić przedmiot z powrotem gdziekolwiek
    transferAcrossChain(1, #CHAIN, extracted, free)
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
      -- spróbuj skanera; jeśli dostępny, weź priorytetowo jego wynik
      local scan = tryScanSlot(i)
      local label = stack.label
      if scan then
        if type(scan) == "table" then
          label = scan.displayName or scan.name or scan.label or label
        elseif type(scan) == "string" then
          label = scan
        end
      end

      local canInsert = canInsertToSlot(i)
      if canInsert == false then
        table.insert(result, i)
        log("DETECTED EXTRACT-ONLY SLOT: " .. i .. " (" .. label .. ")")
      elseif canInsert == true then
        log("SLOT " .. i .. " accepts insertion")
      else
        -- fallback: jeśli detekcja nie powiodła się, ale w slocie są tylko pszczoły,
        -- potraktuj go jako extract-only (to zapobiegnie fałszywemu raportowi "pracują")
        local l = label:lower()
        if l:find("queen") or l:find("princess") or l:find("drone") then
          table.insert(result, i)
          log("FALLBACK: traktuję slot " .. i .. " jako extract-only (zawiera pszczoły) - " .. label)
        else
          log("SLOT " .. i .. " detection unknown (brak testu lub brak wolnego slotu)")
        end
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
      local scan = tryScanSlot(i)
      local label = stack.label
      if scan then
        if type(scan) == "table" then
          label = scan.displayName or scan.name or scan.label or label
        elseif type(scan) == "string" then
          label = scan
        end
      end
      local l = label and label:lower() or ""
      -- jeśli w output jest pszczoła, zabierz ją natychmiast
      if l:find("queen") or l:find("princess") or l:find("drone") then
        local moved = transferAcrossChain(#CHAIN, 1, stack.size, i)
        if not moved or moved == 0 then
          log("TRANSFER PSZCZOL Z SLOTA NIEUDANY " .. i)
        else
          log("ZABRANO PSZCZOLE: " .. label .. " ze slotu " .. i)
        end
      else
        local moved = transferAcrossChain(#CHAIN, 1, stack.size, i)
        if not moved or moved == 0 then
          log("TRANSFER NIEUDANY Z SLOTA " .. i)
        end
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
        transferAcrossChain(#CHAIN, 1, stack.size, i)
        log("WYJĘTO: " .. stack.label)
      end
    end
  end
end

-- 🧠 czy cykl zakończony
local function isFree()
  local size = t.getInventorySize(apiary) or 0
  -- wykryj sloty extract-only i zignoruj je przy sprawdzaniu "czy wolne"
  local extractOnly = detectExtractOnlySlots()
  local extractMap = {}
  for _, v in ipairs(extractOnly) do extractMap[v] = true end

  for i = 1, size do
    if not extractMap[i] then
      local stack = t.getStackInSlot(apiary, i)

      if stack and stack.label then
        local l = stack.label:lower()
        if l:find("queen") or l:find("princess") then
          return false
        end
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
        transferAcrossChain(1, #CHAIN, 1, slot, i)
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

    -- usuń produkty (np. honeycomby) z outputów bez przenoszenia pszczół
    local function extractProducts()
      local size = t.getInventorySize(apiary) or 0
      for i = 1, size do
        local stack = t.getStackInSlot(apiary, i)
        if stack and stack.label then
          local l = stack.label:lower()
          if not (l:find("queen") or l:find("princess") or l:find("drone")) then
            if l:find("honeycomb") or l:find("honey comb") or l:find(" comb") then
              local moved = transferAcrossChain(#CHAIN, 1, stack.size, i)
              if moved and moved > 0 then
                log("ZABRANO PRODUKT: " .. stack.label .. " ze slotu " .. i)
              else
                log("NIEUDANE ZABRANIE PRODUKTU: " .. stack.label .. " ze slotu " .. i)
              end
            end
          end
        end
      end
    end

    extractProducts()

    refillFrames()
    insert()
  end

  os.sleep(5)
end
