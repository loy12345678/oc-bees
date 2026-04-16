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
  min_score = 50,        -- Minimalna punktacja aby użyć pszczołę
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

local function log(msg, level)
  level = level or "INFO"
  local timestamp = os.date("%H:%M:%S")
  print(string.format("[%s] [%s] %s", timestamp, level, msg))
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

local TRAIT_VALUES = {
  -- Pozytywne cechy
  productive = 50,
  fast = 40,
  draconic = 200,
  imperial = 120,
  industrious = 80,
  fastest = 60,
  blinding = 70,
  faster = 30,
  
  -- Temperature tolerance
  ["temperature"] = 20,
  ["humidity"] = 20,
  ["tolerant"] = 25,
  
  -- Negatywne cechy
  slow = -20,
  decay = -50,
  shortest = -10,
}

local function scoreLabel(label)
  local l = label:lower()
  local score = 0
  
  -- Sprawdź każdy trait
  for trait, value in pairs(TRAIT_VALUES) do
    if l:find(trait) then
      score = score + value
    end
  end
  
  -- Bonus za fertility ≥ 3
  if l:find("fertility") then
    if l:find("fertility: 4") or l:find("fertility 4") then
      score = score + CONFIG.fertility_bonus
    elseif l:find("fertility: 3") or l:find("fertility 3") then
      score = score + (CONFIG.fertility_bonus / 2)
    end
  end
  
  return score
end

-- ═══════════════════════════════════════════════════════════════
-- 👑 BEE SELECTION LOGIC
-- ═══════════════════════════════════════════════════════════════

--[[
  Selekcja pszczół:
  1. Szukaj queen lub princess
  2. Filtruj po MIN_SCORE
  3. Wybierz najlepszą
  4. Loguj decyzje
]]

local function selectBee(bee_type)
  bee_type = bee_type or "queen"
  
  local size = t.getInventorySize(chest) or 0
  local candidates = {}
  
  for i = 1, size do
    local stack = t.getStackInSlot(chest, i)
    
    if stack and stack.label then
      local label = stack.label
      local l = label:lower()
      
      -- Sprawdź czy to szukanego typu
      if l:find(bee_type:lower()) then
        local score = scoreLabel(label)
        
        if score >= CONFIG.min_score then
          table.insert(candidates, {
            slot = i,
            label = label,
            score = score
          })
        else
          log(string.format("⚠️  ODRZUCONA %s (score: %d < %d): %s", 
            bee_type, score, CONFIG.min_score, label), "SKIP")
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
  
  log(string.format("✓ WYBRANO %s (score: %d): %s", 
    bee_type, best.score, best.label), "SELECT")
  
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
  log("")
  
  log(string.format("MIN_SCORE: %d (filtrowanie genetyczne)", CONFIG.min_score), "INFO")
  log(string.format("FRAME: %s", CONFIG.frame_name), "INFO")
  log("")
  
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
    
    log("")
    os.sleep(CONFIG.sleep_main_loop)
  end
end

-- ═══════════════════════════════════════════════════════════════
-- 🚀 START
-- ═══════════════════════════════════════════════════════════════

local ok, err = pcall(main)
if not ok then
  log("KRYTYCZNY BŁĄD: " .. tostring(err), "FATAL")
  printStats()
end
