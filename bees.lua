--[[
  ╔════════════════════════════════════════════════════════════════╗
  ║     ZAAWANSOWANY SYSTEM HODOWLI PSZCZÓŁ NA OpenComputers      ║
  ║                   v3.0 - BreederTron Inspired                  ║
  ╚════════════════════════════════════════════════════════════════╝
  
  Oparty na: BreederTron3000 + GTNH Bee Breeding Guide
  Automatyczne hodowanie z pełnym genetic scoring
]]

local component = require("component")
local sides = require("sides")
local t = component.transposer

-- ═══════════════════════════════════════════════════════════════
-- ⚙️   KONFIGURACJA
-- ═══════════════════════════════════════════════════════════════

local CONFIG = {
  chain = {sides.left, sides.right},
  
  geneWeights = {
    ["species"] = 7,
    ["fertility"] = 13,
    ["temperatureTolerance"] = 4,
    ["humidityTolerance"] = 4,
    ["nocturnal"] = 2,
    ["tolerantFlyer"] = 2,
    ["caveDwelling"] = 2,
    ["speed"] = 1,
    ["lifespan"] = 1,
    ["flowering"] = 1,
    ["flowerProvider"] = 1,
    ["territory"] = 1,
    ["effect"] = 1,
  },
  
  activeBonus = 1.3,
  min_score = 50,
  min_purity = 0,
  
  sleep_main_loop = 5,
  sleep_after_insert = 10,
  sleep_cycle_check = 1,
  frame_name = "untreated frame",
}

local chest = CONFIG.chain[1]
local apiary = CONFIG.chain[#CONFIG.chain]

local STATE = {
  cycle_count = 0,
  best_queen = nil,
  best_score = -999,
  queens_produced = 0,
  products_collected = 0,
  start_time = os.time(),
}

-- ═══════════════════════════════════════════════════════════════
-- 📝 LOGGING
-- ═══════════════════════════════════════════════════════════════

local LOG_FILE = "bee_breeder_v3.log"
local log_handle = nil

local function initLogFile()
  log_handle = io.open(LOG_FILE, "w")
  if log_handle then
    log_handle:write("BEE BREEDER v3.0 LOG - " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
    log_handle:write(string.rep("=", 60) .. "\n\n")
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
  
  if log_handle then
    log_handle:write(formatted .. "\n")
    log_handle:flush()
  end
end

-- ═══════════════════════════════════════════════════════════════
-- 🔧 TRANSFER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function safePcall(fn, ...)
  local ok, result = pcall(fn, ...)
  if not ok then
    log("ERROR: " .. tostring(result), "ERROR")
    return nil
  end
  return result
end

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
-- 🔍 BEE IDENTIFICATION
-- ═══════════════════════════════════════════════════════════════

local function getBeeName(bee)
  if bee == nil or bee.individual == nil then
    return "UNKNOWN", "UNKNOWN"
  end
  
  local active = bee.individual.active
  if not active or not active.species then
    return "UNSCANNED", "UNKNOWN"
  end
  
  local species = active.species.name
  local label = bee.label or bee.displayName or ""
  local bee_type = "UNKNOWN"
  
  if label:lower():find("queen") then 
    bee_type = "QUEEN"
  elseif label:lower():find("princess") then 
    bee_type = "PRINCESS"
  elseif label:lower():find("drone") then 
    bee_type = "DRONE"
  end
  
  return species, bee_type
end

local function getBeePurity(targetSpecies, bee)
  if bee == nil or bee.individual == nil then 
    return 0 
  end
  
  local purity = 0
  if bee.individual.active.species.name == targetSpecies then
    purity = purity + 1
  end
  if bee.individual.inactive.species.name == targetSpecies then
    purity = purity + 1
  end
  return purity
end

local function getGeneticScore(bee, targetGenes, targetSpecies)
  if bee == nil or bee.individual == nil then 
    return 0 
  end
  
  local score = 0
  local active = bee.individual.active
  local inactive = bee.individual.inactive
  
  for gene, weight in pairs(CONFIG.geneWeights) do
    if weight ~= nil then
      local targetValue = targetGenes[gene]
      if targetValue ~= nil then
        
        if gene == "species" then
          targetValue = {name = targetSpecies}
        end
        
        if type(targetValue) == "table" and targetValue.name then
          if active.species and active.species.name == targetValue.name then
            score = score + weight * CONFIG.activeBonus
          end
          if inactive.species and inactive.species.name == targetValue.name then
            score = score + weight
          end
        elseif type(targetValue) == "table" then
          local matchesActive = true
          local matchesInactive = true
          
          for tName, tValue in pairs(targetValue) do
            if active[gene] == nil or active[gene][tName] ~= tValue then
              matchesActive = false
            end
            if inactive[gene] == nil or inactive[gene][tName] ~= tValue then
              matchesInactive = false
            end
          end
          
          if matchesActive then
            score = score + weight * CONFIG.activeBonus
          end
          if matchesInactive then
            score = score + weight
          end
        else
          if active[gene] == targetValue then
            score = score + weight * CONFIG.activeBonus
          end
          if inactive[gene] == targetValue then
            score = score + weight
          end
        end
      end
    end
  end
  
  return score
end

-- ═══════════════════════════════════════════════════════════════
-- 🔍 INVENTORY
-- ═══════════════════════════════════════════════════════════════

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

local function debugShowAllBees()
  log("", "DEBUG")
  log("DIAGNOSTYKA - WSZYSTKIE PSZCZOLY W SKRZYNI", "DEBUG")
  log(string.rep("=", 60), "DEBUG")
  
  local size = t.getInventorySize(chest) or 0
  if not size or size == 0 then
    log("Blad: Nie moge odczytac rozmiaru skrzyni", "ERROR")
    return
  end
  
  log("Rozmiar skrzyni: " .. size .. " slotow", "DEBUG")
  log("", "DEBUG")
  
  local bee_count = 0
  local unscanned = 0
  
  for i = 1, size do
    local stack = t.getStackInSlot(chest, i)
    
    if stack then
      bee_count = bee_count + 1
      log("", "DEBUG")
      log("[BEE #" .. bee_count .. " - SLOT " .. i .. "]", "DEBUG")
      log(string.rep("-", 60), "DEBUG")
      
      log("LABEL: " .. (stack.label or "(brak)"), "DEBUG")
      
      if stack.individual == nil then
        log("STATUS: NIESKANOWANA", "WARN")
        unscanned = unscanned + 1
      else
        local active = stack.individual.active
        if active and active.species then
          local species = active.species.name
          local purity = getBeePurity(species, stack)
          log("GATUNEK: " .. species .. " (purity: " .. purity .. "/2)", "DEBUG")
          log("Fertility: " .. tostring(active.fertility), "DEBUG")
          log("Speed: " .. tostring(active.speed), "DEBUG")
        else
          log("STATUS: SKANOWANA ALE BEZ GATUNKU", "WARN")
        end
      end
      
      log("SIZE: " .. (stack.size or 1) .. " szt", "DEBUG")
    end
  end
  
  log("", "DEBUG")
  log(string.rep("=", 60), "DEBUG")
  log("PODSUMOWANIE: " .. bee_count .. " pszczol (" .. unscanned .. " nieskanowanych)", "DEBUG")
  log(string.rep("=", 60), "DEBUG")
  log("", "DEBUG")
end

-- ═══════════════════════════════════════════════════════════════
-- 👑 BEE SELECTION
-- ═══════════════════════════════════════════════════════════════

local function selectBee(bee_type, targetSpecies)
  bee_type = bee_type or "PRINCESS"
  targetSpecies = targetSpecies or nil
  
  local size = t.getInventorySize(chest) or 0
  local candidates = {}
  
  log("Szukam " .. bee_type .. "...", "SEARCH")
  
  for i = 1, size do
    local stack = t.getStackInSlot(chest, i)
    
    if stack and stack.label then
      local label = stack.label
      local species, type_detected = getBeeName(stack)
      
      if type_detected == bee_type then
        
        if targetSpecies and species ~= targetSpecies then
          goto continue
        end
        
        if stack.individual == nil then
          log("  [SLOT " .. i .. "] " .. label .. " - NIESKANOWANA", "SKIP")
          goto continue
        end
        
        local purity = getBeePurity(species, stack)
        local score = getGeneticScore(stack, stack.individual.active, species)
        
        log("  [SLOT " .. i .. "] " .. species .. " (" .. label .. ")", "INFO")
        log("    Purity: " .. purity .. "/2 | Score: " .. score, "INFO")
        
        if purity >= CONFIG.min_purity and score >= CONFIG.min_score then
          table.insert(candidates, {
            slot = i,
            label = label,
            species = species,
            purity = purity,
            score = score,
            bee = stack
          })
          log("    OK - Zaakceptowana", "ACCEPT")
        else
          log("    SKIP - Odrzucona (purity: " .. purity .. ", score: " .. score .. ")", "SKIP")
        end
      end
    end
    
    ::continue::
  end
  
  if #candidates == 0 then
    log("BRAK " .. bee_type, "WARN")
    return nil
  end
  
  table.sort(candidates, function(a, b)
    if a.purity ~= b.purity then 
      return a.purity > b.purity 
    end
    return a.score > b.score
  end)
  
  local best = candidates[1]
  log("WYBRANO: " .. best.species .. " (purity: " .. best.purity .. ", score: " .. best.score .. ")", "SELECT")
  log("", "SELECT")
  
  return best.slot
end

-- ═══════════════════════════════════════════════════════════════
-- 🐝 APIARY OPERATIONS
-- ═══════════════════════════════════════════════════════════════

local function cycleIsDone()
  local apiary_size = t.getInventorySize(apiary) or 0
  
  for i = 1, apiary_size do
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

local function insertBees()
  log("Wkiadanie pszczol do apairy...", "ACTION")
  
  local queen_slot = selectBee("PRINCESS") or selectBee("QUEEN")
  local drone_slot = selectBee("DRONE")
  
  if not queen_slot or not drone_slot then
    log("Brak dostepnych pszczol", "ERROR")
    return false
  end
  
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
    log("Brak wolnych slotow w apairy", "ERROR")
    return false
  end
  
  transferAcrossChain(1, #CONFIG.chain, 1, queen_slot, queen_slot_apiary)
  transferAcrossChain(1, #CONFIG.chain, 1, drone_slot, drone_slot_apiary)
  
  log("Pszczoły wlozone do apairy", "SUCCESS")
  STATE.cycle_count = STATE.cycle_count + 1
  return true
end

local function collectProducts()
  local apiary_size = t.getInventorySize(apiary) or 0
  local collected = 0
  
  for i = 1, apiary_size do
    local stack = t.getStackInSlot(apiary, i)
    
    if stack and stack.label then
      local l = stack.label:lower()
      
      if not (l:find("queen") or l:find("princess") or l:find("drone")) then
        if l:find("comb") or l:find("honey") then
          local moved = transferAcrossChain(#CONFIG.chain, 1, stack.size, i)
          if moved and moved > 0 then
            collected = collected + moved
            log("Zebrano: " .. stack.label .. " x" .. moved, "PRODUCT")
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

local function extractBees()
  local apiary_size = t.getInventorySize(apiary) or 0
  local extracted = 0
  
  for i = 1, apiary_size do
    local stack = t.getStackInSlot(apiary, i)
    
    if stack and stack.label then
      local l = stack.label:lower()
      
      if l:find("queen") or l:find("princess") or l:find("drone") then
        local moved = transferAcrossChain(#CONFIG.chain, 1, stack.size, i)
        if moved and moved > 0 then
          extracted = extracted + moved
          
          if l:find("princess") then
            STATE.queens_produced = STATE.queens_produced + 1
          end
          
          log("Wyjeto: " .. stack.label .. " x" .. moved, "EXTRACT")
        end
      end
    end
  end
  
  return extracted
end

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
          log("Frame dodany do slotu " .. i, "FRAME")
        end
      end
    end
  end
  
  return refilled
end

-- ═══════════════════════════════════════════════════════════════
-- 📊 STATISTICS
-- ═══════════════════════════════════════════════════════════════

local function printStats()
  local uptime = os.time() - STATE.start_time
  local hours = math.floor(uptime / 3600)
  local mins = math.floor((uptime % 3600) / 60)
  
  log("", "STAT")
  log(string.rep("=", 60), "STAT")
  log("STATYSTYKA HODOWLI", "STAT")
  log(string.rep("=", 60), "STAT")
  log("Uptime: " .. hours .. "h " .. mins .. "m", "STAT")
  log("Cycles: " .. STATE.cycle_count, "STAT")
  log("Queens Produced: " .. STATE.queens_produced, "STAT")
  log("Products Collected: " .. STATE.products_collected, "STAT")
  log(string.rep("=", 60), "STAT")
  log("", "STAT")
end

-- ═══════════════════════════════════════════════════════════════
-- 🎯 MAIN
-- ═══════════════════════════════════════════════════════════════

local function main()
  log(string.rep("=", 60), "BANNER")
  log("BEE BREEDER v3.0 - BreederTron Inspired", "BANNER")
  log(string.rep("=", 60), "BANNER")
  log("", "BANNER")
  
  debugShowAllBees()
  
  log("Nacisni ENTER aby zaczac, lub Ctrl+C aby anulowac...", "PROMPT")
  io.read()
  
  local cycle = 0
  while true do
    cycle = cycle + 1
    log("=== CYKL " .. cycle .. " ===", "CYCLE")
    
    if insertBees() then
      log("Czekanie " .. CONFIG.sleep_after_insert .. " sekund...", "WAIT")
      os.sleep(CONFIG.sleep_after_insert)
      
      log("Czekanie na koniec cyklu...", "WAIT")
      while not cycleIsDone() do
        os.sleep(CONFIG.sleep_cycle_check)
      end
      os.sleep(2)
      
      collectProducts()
      os.sleep(1)
      
      extractBees()
      os.sleep(1)
      
      refillFrames()
    else
      log("Brak pszczol", "WARN")
      os.sleep(30)
    end
    
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
  log("FATAL ERROR: " .. tostring(err), "FATAL")
  printStats()
end

closeLogFile()
log("LOG ZAPISANY DO: " .. LOG_FILE, "SUCCESS")
