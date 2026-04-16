--[[
  ╔════════════════════════════════════════════════════════════════╗
  ║     ZAAWANSOWANY SYSTEM HODOWLI PSZCZÓŁ NA OpenComputers      ║
  ║                   v2.0 - GTNH Edition                          ║
  ╚════════════════════════════════════════════════════════════════╝
  
  Oparty na przewodniku GTNH Bee Breeding Guide
  Automatyczne hodowanie, selekcja genetyczna i produkcja
]]

local component = require("component")
local sides = require("sides")
local t = component.transposer

-- ═══════════════════════════════════════════════════════════════
-- ⚙️   KONFIGURACJA
-- ═══════════════════════════════════════════════════════════════

local CONFIG = {
  -- Ustawienie łańcucha urządzeń
  chain = {sides.left, sides.right},  -- chest -> apiary
  
  -- Progi wyboru genetycznego
  min_score = 0,         -- TYMCZASOWO 0 - do testów (zmień na 50 gdy znajdziesz traity)
  fertility_bonus = 30,  -- Bonus do punktu za Fertility ≥3
  
  -- Konfiguracja timingu
  sleep_main_loop = 5,   -- Pauza główna (sekundy)
  sleep_after_insert = 10, -- Czekanie po włożeniu pszczół
  sleep_cycle_check = 5,  -- Interwał sprawdzania cyklu
  
  -- Frame configuration
  frame_name = "untreated frame",
  
  -- Advanced tracking
  enable_stats = true,
  max_generations_tracked = 5,
}

local chest = CONFIG.chain[1]
local apiary = CONFIG.chain[#CONFIG.chain]

-- State tracking
local STATE = {
  cycle_count = 0,
  best_queen = nil,
  best_score = -999,
  queens_produced = 0,
  products_collected = 0,
  start_time = os.time(),
}

-- ═══════════════════════════════════════════════════════════════
-- 📝 LOGGING & UTILITIES
-- ═══════════════════════════════════════════════════════════════

local LOG_FILE = "/tmp/bee_diagnostic.log"
local log_handle = nil

local function initLogFile()
  log_handle = io.open(LOG_FILE, "w")
  if log_handle then
    log_handle:write("═══════════════════════════════════════════════════════════\n")
    log_handle:write("BEE DIAGNOSTIC LOG - " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
    log_handle:write("═══════════════════════════════════════════════════════════\n\n")
    log_handle:flush()
  end
end

local function closeLogFile()
  if log_handle then
    log_handle:close()
  end
end

local function log(msg, level)
  level = level or "INFO"
  local timestamp = os.date("%H:%M:%S")
  local formatted = string.format("[%s] [%s] %s", timestamp, level, msg)
  print(formatted)
  
  -- Zapisz do pliku
  if log_handle then
    log_handle:write(formatted .. "\n")
    log_handle:flush()
  end
end

local function safePcall(fn, ...)
  local ok, result = pcall(fn, ...)
  if not ok then
    log("ERROR: " .. tostring(result), "ERROR")
    return nil
  end
  return result
end

-- ═══════════════════════════════════════════════════════════════
-- 🔧 TRANSFER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

-- Bezpieczny transfer przez między urządzeniami
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
  return safePcall(fn) or 0
end

-- Transfer przez łańcuch modułów (hopping)
local function transferAcrossChain(fromIdx, toIdx, count, fromSlot, toSlot)
  if fromIdx == toIdx then return 0 end
  
  local step = fromIdx < toIdx and 1 or -1
  local moved = 0
  local curSlot = fromSlot
  
  local i = fromIdx
  while i ~= toIdx do
    local fromSide = CONFIG.chain[i]
    local toSide = CONFIG.chain[i + step]
    local nextSlot = ((i + step) == toIdx) and toSlot or nil
    
    local movedNow = safeTransfer(fromSide, toSide, count, curSlot, nextSlot) or 0
    if movedNow == 0 then return 0 end
    
    moved = movedNow
    curSlot = nextSlot
    i = i + step
  end
  
  return moved
end

-- ═══════════════════════════════════════════════════════════════
-- 🔍 INVENTORY SCANNING
-- ═══════════════════════════════════════════════════════════════

-- Znajdź item po nazwie w skrzyni
local function findItemInChest(name)
  local size = t.getInventorySize(chest) or 0
  
  for i = 1, size do
    local stack = t.getStackInSlot(chest, i)
    if stack and stack.label and stack.label:lower():find(name:lower()) then
      return i
    end
  end
  return nil
end

-- Znajdź wolny slot w skrzyni
local function findFreeChestSlot()
  local size = t.getInventorySize(chest) or 0
  for i = 1, size do
    if not t.getStackInSlot(chest, i) then
      return i
    end
  end
  return nil
end

-- Znajdź niemożliwy do wstawienia przedmiot (do testowania)
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

-- ═══════════════════════════════════════════════════════════════
-- 🧬 GENETIC TRAIT SCORING
-- ═══════════════════════════════════════════════════════════════

--[[
  Scoring system basedon GTNH Bee Breeding Guide:
  
  POSITIVE TRAITS:
  - Productive (+50)
  - Fast (+40)
  - Fertility 3+ (+30 bonus)
  - Draconic (+200)
  - Imperial (+120)
  - Industrious (+80)
  - Fastest production speed (+60)
  - Temperature/Humidity tolerance (+20 each)
  
  NEGATIVE TRAITS:
  - Slow (-20)
  - Genetic Decay (-50)
  - Infertile/Low fertility (-30)
]]

-- ═══════════════════════════════════════════════════════════════
-- 📋 DEBUG FUNCTION - PEŁNA DIAGNOSTYKA WSZYSTKICH PSZCZÓŁ
-- ═══════════════════════════════════════════════════════════════

local function debugShowAllBees()
  log("", "DEBUG")
  log("╔═══════════════════════════════════════════════════════════════╗", "DEBUG")
  log("║        📋 PEŁNA DIAGNOSTYKA - WSZYSTKIE PSZCZOŁY W SKRZYNI   ║", "DEBUG")
  log("╚═══════════════════════════════════════════════════════════════╝", "DEBUG")
  
  local size = t.getInventorySize(chest) or 0
  local found = false
  
  if not size or size == 0 then
    log("⚠️  Błąd: Nie mogę odczytać rozmiaru skrzyni!", "ERROR")
    return
  end
  
  log(string.format("📦 Rozmiar skrzyni: %d slotów", size), "DEBUG")
  log(string.format("🔍 Skanowanie slotów...", size), "DEBUG")
  log("", "DEBUG")
  
  local bee_count = 0
  
  for i = 1, size do
    local stack = t.getStackInSlot(chest, i)
    
    if stack then
      bee_count = bee_count + 1
      found = true
      log("", "DEBUG")
      log(string.format("✅ [BEE #%d na SLOT %d]", bee_count, i), "DEBUG")
      log(string.rep("─", 67), "DEBUG")
      
      -- Pokaż label
      if stack.label then
        log(string.format("📝 LABEL: %s", stack.label), "DEBUG")
        log(string.format("   (Długość: %d znaków)", string.len(stack.label)), "DEBUG")
        
        -- Pokaż każdy character w labelu
        log("   Znaki: ", "DEBUG")
        local label_chars = ""
        for j = 1, string.len(stack.label) do
          local char = string.sub(stack.label, j, j)
          local code = string.byte(char)
          label_chars = label_chars .. string.format("[%d]", code) .. " "
        end
        log("   " .. label_chars, "DEBUG")
      else
        log("📝 LABEL: (brak)", "DEBUG")
      end
      
      -- Pokaż ilość
      log(string.format("📦 SIZE: %d szt", stack.size or 1), "DEBUG")
      
      -- Pokaż WSZYSTKIE pola stacku
      log("🔍 WSZYSTKIE POLA STACKU:", "DEBUG")
      local has_fields = false
      for key, value in pairs(stack) do
        has_fields = true
        local value_str = tostring(value)
        if type(value) == "boolean" then
          value_str = value and "true" or "false"
        elseif type(value) == "table" then
          value_str = "(table)"
        end
        log(string.format("   %s: %s", key, value_str), "DEBUG")
      end
      
      if not has_fields then
        log("   (brak dodatkowych pól)", "DEBUG")
      end
      
      -- Determine bee type
      local bee_type = "NIEZNANY"
      if stack.label then
        local l = stack.label:lower()
        if l:find("queen") then bee_type = "QUEEN"
        elseif l:find("princess") then bee_type = "PRINCESS"
        elseif l:find("drone") then bee_type = "DRONE"
        end
      end
      log(string.format("🐝 TYP: %s", bee_type), "DEBUG")
      
      log("", "DEBUG")
    end
  end
  
  if not found then
    log("⚠️  Brak pszczół w skrzyni!", "WARN")
  end
  
  log("", "DEBUG")
  log(string.rep("═", 67), "DEBUG")
  log(string.format("✅ PODSUMOWANIE: Znaleziono %d pszczół", bee_count), "DEBUG")
  log(string.rep("═", 67), "DEBUG")
  log(string.format("📝 Cała diagnostyka zapisana do: %s", LOG_FILE), "DEBUG")
  log("", "DEBUG")
end

-- ═══════════════════════════════════════════════════════════════
-- 🧬 GENETIC TRAIT SCORING - Ulepszona wersja
-- ═══════════════════════════════════════════════════════════════

--[[
  Nowy system - wyświetla WSZYSTKIE cechy i ich wartości
  Scoring oparty na faktycznych traitsach z etykiety pszczoły
]]

local TRAIT_VALUES = {
  -- Szybkość produkcji
  ["blinding"] = 70,
  ["fastest"] = 60,
  ["faster"] = 30,
  ["fast"] = 40,
  
  -- Fertility (liczba czasu rozmnażania)
  ["fertility 4"] = 50,
  ["fertility: 4"] = 50,
  ["fertility 3"] = 25,
  ["fertility: 3"] = 25,
  
  -- Gatunki vip
  ["draconic"] = 200,
  ["imperial"] = 120,
  ["industrious"] = 80,
  ["productive"] = 50,
  
  -- Tolerancja
  ["tolerant"] = 25,
  ["temperature"] = 20,
  ["humidity"] = 20,
  
  -- Negatywne
  ["slow"] = -20,
  ["decay"] = -50,
  ["shortest"] = -10,
}

local function analyzeBeeFull(label)
  local l = label:lower()
  local results = {}
  
  -- Szukaj każdego traita
  for trait, value in pairs(TRAIT_VALUES) do
    if l:find(trait, 1, true) then  -- true = plain text search, nie regex
      table.insert(results, {
        trait = trait,
        value = value,
        found = true
      })
    end
  end
  
  return results
end

local function scoreLabel(label)
  local traits = analyzeBeeFull(label)
  local score = 0
  local detail_str = ""
  
  for _, t in ipairs(traits) do
    score = score + t.value
    detail_str = detail_str .. string.format("%s(%+d) ", t.trait, t.value)
  end
  
  return score, detail_str
end

-- ═══════════════════════════════════════════════════════════════
-- 👑 BEE SELECTION LOGIC
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- 👑 BEE SELECTION LOGIC - z pełnym debugowaniem
-- ═══════════════════════════════════════════════════════════════

local function selectBee(bee_type)
  bee_type = bee_type or "queen"
  
  local size = t.getInventorySize(chest) or 0
  local candidates = {}
  
  log(string.format("\n🔍 Szukam %s...", bee_type), "SEARCH")
  
  for i = 1, size do
    local stack = t.getStackInSlot(chest, i)
    
    if stack and stack.label then
      local label = stack.label
      local l = label:lower()
      
      -- Sprawdź czy to szukanego typu
      if l:find(bee_type:lower()) then
        local score, traits_detail = scoreLabel(label)
        
        log(string.format("  [SLOT %d] %s", i, label), "INFO")
        log(string.format("    Score: %d | Traits: %s", score, traits_detail), "INFO")
        
        if score >= CONFIG.min_score then
          table.insert(candidates, {
            slot = i,
            label = label,
            score = score,
            traits = traits_detail
          })
          log(string.format("    ✓ Zaakceptowana", score), "ACCEPT")
        else
          log(string.format("    ✗ Odrzucona (score: %d < %d)", score, CONFIG.min_score), "SKIP")
        end
      end
    end
  end
  
  if #candidates == 0 then
    log(string.format("❌ BRAK %s z score ≥ %d", bee_type, CONFIG.min_score), "WARN")
    return nil
  end
  
  -- Sortuj po score (malejąco)
  table.sort(candidates, function(a, b) return a.score > b.score end)
  local best = candidates[1]
  
  log(string.format("✓ WYBRANO %s (score: %d)", bee_type, best.score), "SELECT")
  log(string.format("   %s", best.label), "SELECT")
  log(string.format("   Traits: %s", best.traits), "SELECT")
  log("", "SELECT")
  
  return best.slot
end

-- ═══════════════════════════════════════════════════════════════
-- 🐝 APIARY OPERATIONS
-- ═══════════════════════════════════════════════════════════════

-- Wybierz i włóż pszczoły do apairy
local function insertBees()
  log("🔄 Szukam pszczół...", "ACTION")
  
  local queen_slot = selectBee("queen") or selectBee("princess")
  local drone_slot = selectBee("drone")
  
  if not queen_slot or not drone_slot then
    log("❌ Brak dostępnych pszczół!", "ERROR")
    return false
  end
  
  -- Znajdź wolne sloty w apairy
  local apiary_size = t.getInventorySize(apiary) or 0
  local queen_slot_apiary, drone_slot_apiary
  
  for i = 1, apiary_size do
    if not t.getStackInSlot(apiary, i) then
      if not queen_slot_apiary then
        queen_slot_apiary = i
      else
        drone_slot_apiary = i
        break
      end
    end
  end
  
  if not queen_slot_apiary or not drone_slot_apiary then
    log("❌ Brak wolnych slotów w apairy", "ERROR")
    return false
  end
  
  -- Transfer
  transferAcrossChain(1, #CONFIG.chain, 1, queen_slot, queen_slot_apiary)
  transferAcrossChain(1, #CONFIG.chain, 1, drone_slot, drone_slot_apiary)
  
  log("✓ Pszczoły włożone do apairy", "SUCCESS")
  STATE.cycle_count = STATE.cycle_count + 1
  return true
end

-- Zbierz produkty (honeycomb, itp)
local function collectProducts()
  local apiary_size = t.getInventorySize(apiary) or 0
  local collected = 0
  
  for i = 1, apiary_size do
    local stack = t.getStackInSlot(apiary, i)
    
    if stack and stack.label then
      local l = stack.label:lower()
      
      -- Jeśli to produkt (nie pszczoła)
      if not (l:find("queen") or l:find("princess") or l:find("drone")) then
        -- Jeśli to honeycomb lub podobny produkt
        if l:find("comb") or l:find("honey") then
          local moved = transferAcrossChain(#CONFIG.chain, 1, stack.size, i)
          if moved and moved > 0 then
            collected = collected + moved
            log(string.format("📦 Zebrano: %s x%d", stack.label, moved), "PRODUCT")
          end
        end
      end
    end
  end
  
  if collected > 0 then
    STATE.products_collected = STATE.products_collected + collected
  end
  
  return collected
end

-- Wyciągnij pszczoły z apairy (głównie nowe)
local function extractBees()
  local apiary_size = t.getInventorySize(apiary) or 0
  local extracted = 0
  
  for i = 1, apiary_size do
    local stack = t.getStackInSlot(apiary, i)
    
    if stack and stack.label then
      local l = stack.label:lower()
      
      -- Jeśli to pszczoła
      if l:find("queen") or l:find("princess") or l:find("drone") then
        local moved = transferAcrossChain(#CONFIG.chain, 1, stack.size, i)
        if moved and moved > 0 then
          extracted = extracted + moved
          
          -- Śledzenie nowych queens
          if l:find("princess") then
            STATE.queens_produced = STATE.queens_produced + 1
          end
          
          log(string.format("🐝 Wyjęto: %s x%d", stack.label, moved), "EXTRACT")
        end
      end
    end
  end
  
  return extracted
end

-- Uzupełnij frame'i
local function refillFrames()
  local apiary_size = t.getInventorySize(apiary) or 0
  local refilled = 0
  
  for i = 1, apiary_size do
    local stack = t.getStackInSlot(apiary, i)
    
    if not stack then
      local frame_slot = findItemInChest(CONFIG.frame_name)
      
      if frame_slot then
        local moved = transferAcrossChain(1, #CONFIG.chain, 1, frame_slot, i)
        if moved and moved > 0 then
          refilled = refilled + 1
          log(string.format("➕ Frame do slotu %d", i), "FRAME")
        end
      end
    end
  end
  
  return refilled
end

-- Sprawdź czy cykl hodowli zakończony
local function isCycleComplete()
  local apiary_size = t.getInventorySize(apiary) or 0
  
  for i = 1, apiary_size do
    local stack = t.getStackInSlot(apiary, i)
    
    if stack and stack.label then
      local l = stack.label:lower()
      
      -- Jeśli jest jeszcze queen lub princess, cykl trwa
      if l:find("queen") or l:find("princess") then
        return false
      end
    end
  end
  
  return true
end

-- Czekaj na zakończenie cyklu
local function waitForCycleComplete()
  log("⏳ Czekanie na koniec cyklu hodowli...", "WAIT")
  
  local wait_time = 0
  while not isCycleComplete() do
    os.sleep(CONFIG.sleep_cycle_check)
    wait_time = wait_time + CONFIG.sleep_cycle_check
    
    if wait_time % 30 == 0 then
      log(string.format("⏳ Czekanie... (%d sek)", wait_time), "WAIT")
    end
  end
  
  log(string.format("✓ Cykl zakończony (~%d sek)", wait_time), "SUCCESS")
end

-- ═══════════════════════════════════════════════════════════════
-- 📊 STATISTICS & REPORTING
-- ═══════════════════════════════════════════════════════════════

local function printStats()
  local uptime = os.time() - STATE.start_time
  local hours = math.floor(uptime / 3600)
  local mins = math.floor((uptime % 3600) / 60)
  
  log("", "STAT")
  log("╔════════════════════════════════════════════╗", "STAT")
  log("║       📊 STATYSTYKA HODOWLI PSZCZÓŁ        ║", "STAT")
  log("╠════════════════════════════════════════════╣", "STAT")
  log(string.format("║ Czas pracy: %2d:%02d                      ║", hours, mins), "STAT")
  log(string.format("║ Liczba cykli: %d                         ║", STATE.cycle_count), "STAT")
  log(string.format("║ Wyprodukowanych queens: %d               ║", STATE.queens_produced), "STAT")
  log(string.format("║ Zebranych produktów: %d                  ║", STATE.products_collected), "STAT")
  log("╚════════════════════════════════════════════╝", "STAT")
  log("", "STAT")
end

-- ═══════════════════════════════════════════════════════════════
-- 🎯 MAIN LOOP
-- ═══════════════════════════════════════════════════════════════

local function main()
  log("═══════════════════════════════════════════════════════════", "BANNER")
  log("🐝 ZAAWANSOWANY SYSTEM HODOWLI PSZCZÓŁ - v2.0", "BANNER")
  log("Oparty na GTNH Bee Breeding Guide", "BANNER")
  log("═══════════════════════════════════════════════════════════", "BANNER")
  log("", "BANNER")
  log(string.format("📝 LOG ZAPISYWANY DO: %s", LOG_FILE), "BANNER")
  log("", "BANNER")
  
  log(string.format("MIN_SCORE: %d (filtrowanie genetyczne)", CONFIG.min_score), "INFO")
  log(string.format("FRAME: %s", CONFIG.frame_name), "INFO")
  log("")
  
  -- DIAGNOSTYKA - Pokaż wszystkie dostępne pszczoły
  debugShowAllBees()
  
  log("Naciśnij ENTER aby zacząć, lub Ctrl+C aby anulować...", "PROMPT")
  io.read()
  
  local cycle = 0
  while true do
    cycle = cycle + 1
    log(string.format("═══ CYKL %d ═══", cycle), "CYCLE")
    
    -- Włóż pszczoły
    if insertBees() then
      log(string.format("Czekanie %d sekund na aklimatyzację...", CONFIG.sleep_after_insert), "WAIT")
      os.sleep(CONFIG.sleep_after_insert)
      
      -- Czekaj na koniec cyklu
      waitForCycleComplete()
      os.sleep(2)
      
      -- Zbierz produkty
      collectProducts()
      os.sleep(1)
      
      -- Wyciągnij pszczoły
      extractBees()
      os.sleep(1)
      
      -- Uzupełnij frame'i
      refillFrames()
    else
      log("⚠️  Nie mogę włożyć pszczół - brakuje dostępnych osobników", "WARN")
      os.sleep(30)
    end
    
    -- Wydrukuj statystyki co 5 cykli
    if cycle % 5 == 0 then
      printStats()
    end
    
    log("", "INFO")
    os.sleep(CONFIG.sleep_main_loop)
  end
end

-- ═══════════════════════════════════════════════════════════════
-- 🚀 START
-- ═══════════════════════════════════════════════════════════════

initLogFile()

local ok, err = pcall(main)
if not ok then
  log("KRYTYCZNY BŁĄD: " .. tostring(err), "FATAL")
  printStats()
end

closeLogFile()
log("✓ LOG ZAPISANY DO: " .. LOG_FILE, "SUCCESS")
