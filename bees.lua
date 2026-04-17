--[[
  Bee Breeder v3.0 - BreederTron Inspired
  Advanced bee breeding system for OpenComputers
  Based on BreederTron3000 + GTNH Bee Breeding Guide
]]

local component = require("component")
local sides = require("sides")
local t = component.transposer

-- CONFIGURATION

local CONFIG = {
  chain = {sides.left, sides.right},  -- chest_in -> chest_out (do przechowywania dronów)
  
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
  
  sleep_main_loop = 2,
}

local chest_in = CONFIG.chain[1]
local chest_out = CONFIG.chain[2]

local STATE = {
  cycle_count = 0,
  best_queen = nil,
  best_score = -999,
  queens_produced = 0,
  products_collected = 0,
  start_time = os.time(),
}

-- LOGGING

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

-- TRANSFER FUNCTIONS

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

-- BEE IDENTIFICATION

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

-- INVENTORY

local function findFreeSlot(side)
  local size = t.getInventorySize(side) or 0
  
  for i = 1, size do
    if not t.getStackInSlot(side, i) then
      return i
    end
  end
  return nil
end

local function debugShowAllBees()
  log("", "DEBUG")
  log("DIAGNOSTYKA - WSZYSTKIE PSZCZOLY W SKRZYNI", "DEBUG")
  log(string.rep("=", 60), "DEBUG")
  
  local size = t.getInventorySize(chest_in) or 0
  if not size or size == 0 then
    log("Blad: Nie moge odczytac rozmiaru skrzyni", "ERROR")
    return
  end
  
  log("Rozmiar skrzyni: " .. size .. " slotow", "DEBUG")
  log("", "DEBUG")
  
  local bee_count = 0
  local unscanned = 0
  
  for i = 1, size do
    local stack = t.getStackInSlot(chest_in, i)
    
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

-- SCANNER



-- BEE SELECTION

local STATE_selected_slots = {}

local function selectBee(bee_type, targetSpecies)
  bee_type = bee_type or "PRINCESS"
  targetSpecies = targetSpecies or nil
  
  local size = t.getInventorySize(chest_in) or 0
  local candidates = {}
  
  log("Szukam " .. bee_type .. "...", "SEARCH")
  
  for i = 1, size do
    local stack = t.getStackInSlot(chest_in, i)
    
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
        
        if STATE_selected_slots[i] then
          log("    SKIP - Juz uzyta w tym cyklu", "SKIP")
        elseif purity >= CONFIG.min_purity and score >= CONFIG.min_score then
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
  
  STATE_selected_slots[best.slot] = true
  return best.slot
end

-- DRONE SELECTION & STORAGE

local function selectAndStoreBestDrone()
  log("Wybieranie najlepszego drona...", "ACTION")
  
  local drone_slot = selectBee("DRONE")
  
  if not drone_slot then
    log("Brak dostepnych dronow", "ERROR")
    return false
  end
  
  -- Znajdz wolny slot w skrzynce wyjsciowej
  local free_slot = findFreeSlot(chest_out)
  
  if not free_slot then
    log("Brak wolnych slotow w skrzynce wyjsciowej", "ERROR")
    return false
  end
  
  -- Transfer drona ze skrzynki lewej na praw
  local moved = safeTransfer(chest_in, chest_out, 1, drone_slot, free_slot)
  
  if moved and moved > 0 then
    STATE_selected_slots[drone_slot] = nil
    log("Najlepszy dron umieszczony w skrzynce wyjsciowej (slot " .. free_slot .. ")", "SUCCESS")
    STATE.cycle_count = STATE.cycle_count + 1
    return true
  else
    log("Blad podczas transferu drona", "ERROR")
    return false
  end
end

-- DETAILED BEE INFO

local function printBeeDetails(slot, title)
  title = title or "PSZCZOLA"
  local stack = t.getStackInSlot(chest_in, slot)
  
  if not stack then
    log("Blad: Brak pszczoly w slocie " .. slot, "ERROR")
    return
  end
  
  if not stack.individual then
    log("Blad: Pszczola nie jest zeskanowana", "ERROR")
    return
  end
  
  local species, bee_type = getBeeName(stack)
  local purity = getBeePurity(species, stack)
  local score = getGeneticScore(stack, stack.individual.active, species)
  
  log("", "DETAIL")
  log(string.rep("=", 80), "DETAIL")
  log(title, "DETAIL")
  log(string.rep("=", 80), "DETAIL")
  log("", "DETAIL")
  
  log("LABEL: " .. (stack.label or "(brak)"), "DETAIL")
  log("TYP: " .. bee_type, "DETAIL")
  log("GATUNEK: " .. species, "DETAIL")
  log("CZYSTOŚĆ (PURITY): " .. purity .. "/2", "DETAIL")
  log("WYNIK GENETYCZNY (SCORE): " .. score, "DETAIL")
  log("ROZMIAR STACKA: " .. (stack.size or 1), "DETAIL")
  log("", "DETAIL")
  
  log("ALLELE AKTYWNE (ACTIVE):", "DETAIL")
  local active = stack.individual.active
  for gene, weight in pairs(CONFIG.geneWeights) do
    if active[gene] then
      local value = active[gene]
      if type(value) == "table" and value.name then
        log("  " .. gene .. ": " .. value.name, "DETAIL")
      else
        log("  " .. gene .. ": " .. tostring(value), "DETAIL")
      end
    end
  end
  
  log("", "DETAIL")
  log("ALLELE NIEAKTYWNE (INACTIVE):", "DETAIL")
  local inactive = stack.individual.inactive
  for gene, weight in pairs(CONFIG.geneWeights) do
    if inactive[gene] then
      local value = inactive[gene]
      if type(value) == "table" and value.name then
        log("  " .. gene .. ": " .. value.name, "DETAIL")
      else
        log("  " .. gene .. ": " .. tostring(value), "DETAIL")
      end
    end
  end
  
  log("", "DETAIL")
  log(string.rep("=", 80), "DETAIL")
  log("", "DETAIL")
end

-- EXTRACT TARGET GENES FROM DRONE

local function extractTargetGenesFromDrone(drone_slot)
  local stack = t.getStackInSlot(chest_in, drone_slot)
  
  if not stack or not stack.individual then
    return nil
  end
  
  local active = stack.individual.active
  local inactive = stack.individual.inactive
  
  -- Extrahuj najlepsze allele (active preferowane, wtedy inactive)
  local targetGenes = {}
  
  for gene, _ in pairs(CONFIG.geneWeights) do
    if active[gene] then
      targetGenes[gene] = active[gene]
    elseif inactive[gene] then
      targetGenes[gene] = inactive[gene]
    end
  end
  
  return targetGenes
end

-- FIND BEST MOTHER BEE

local function selectBestMother(droneTargetGenes)
  if not droneTargetGenes then
    log("Blad: Brak genow do porownania", "ERROR")
    return nil
  end
  
  local size = t.getInventorySize(chest_in) or 0
  local candidates = {}
  local droneSpecies = droneTargetGenes.species and droneTargetGenes.species.name or nil
  
  log("", "SEARCH")
  log("Szukam najlepszej matki (princess/queen)...", "SEARCH")
  
  for i = 1, size do
    local stack = t.getStackInSlot(chest_in, i)
    
    if stack and stack.label then
      local label = stack.label
      local species, bee_type = getBeeName(stack)
      
      -- Szukamy princess lub queen
      if bee_type == "PRINCESS" or bee_type == "QUEEN" then
        
        if stack.individual == nil then
          log("  [SLOT " .. i .. "] " .. label .. " - NIESKANOWANA", "SKIP")
          goto continue_mother
        end
        
        local purity = getBeePurity(species, stack)
        local score = getGeneticScore(stack, stack.individual.active, species)
        
        -- Liczymy dopasowanie do genow drona
        local match_count = 0
        local active = stack.individual.active
        local inactive = stack.individual.inactive
        
        for gene, targetValue in pairs(droneTargetGenes) do
          if type(targetValue) == "table" and targetValue.name then
            if (active[gene] and active[gene].name == targetValue.name) or
               (inactive[gene] and inactive[gene].name == targetValue.name) then
              match_count = match_count + 1
            end
          elseif active[gene] == targetValue or inactive[gene] == targetValue then
            match_count = match_count + 1
          end
        end
        
        log("  [SLOT " .. i .. "] " .. species .. " (" .. bee_type .. ") - " .. label, "INFO")
        log("    Purity: " .. purity .. "/2 | Score: " .. score .. " | Match: " .. match_count, "INFO")
        
        if purity >= CONFIG.min_purity and score >= CONFIG.min_score then
          table.insert(candidates, {
            slot = i,
            label = label,
            species = species,
            bee_type = bee_type,
            purity = purity,
            score = score,
            match_count = match_count,
            bee = stack
          })
          log("    OK - Zaakceptowana", "ACCEPT")
        else
          log("    SKIP - Odrzucona (purity: " .. purity .. ", score: " .. score .. ")", "SKIP")
        end
      end
    end
    
    ::continue_mother::
  end
  
  if #candidates == 0 then
    log("BRAK MATEK", "WARN")
    return nil
  end
  
  -- Sortuj: najpierw same gatunki drona, potem match, purity, score
  table.sort(candidates, function(a, b)
    -- Preferuj matkę z tym samym gatunkiem co dron
    local a_same_species = (a.species == droneSpecies) and 1 or 0
    local b_same_species = (b.species == droneSpecies) and 1 or 0
    
    if a_same_species ~= b_same_species then
      return a_same_species > b_same_species
    end
    
    -- Potem sort po dopasowaniu
    if a.match_count ~= b.match_count then
      return a.match_count > b.match_count
    end
    
    -- Potem po czystości
    if a.purity ~= b.purity then
      return a.purity > b.purity
    end
    
    -- Na koniec po score
    return a.score > b.score
  end)
  
  local best = candidates[1]
  log("WYBRANA MATKA: " .. best.species .. " (" .. best.bee_type .. ") - purity: " .. best.purity .. ", score: " .. best.score .. ", match: " .. best.match_count, "SELECT")
  log("", "SELECT")
  
  return best.slot
end

-- MAIN

local function main()
  log(string.rep("=", 60), "BANNER")
  log("BEE BREEDER v3.0 - SINGLE RUN DIAGNOSTICS", "BANNER")
  log(string.rep("=", 60), "BANNER")
  log("", "BANNER")
  
  -- Pokaż diagnostykę wszystkich pszczół
  debugShowAllBees()
  
  log("Nacisni ENTER aby wybrac drona i matke, lub Ctrl+C aby anulowac...", "PROMPT")
  io.read()
  
  log("", "INFO")
  
  -- Wybierz najlepszego drona (bez transferu)
  local drone_slot = selectBee("DRONE")
  
  if not drone_slot then
    log("Brak dostepnych dronow", "ERROR")
    return
  end
  
  log("", "INFO")
  
  -- Wyświetl szczegóły drona
  printBeeDetails(drone_slot, "INFORMACJE DRONA (OJCIEC)")
  
  -- Ekstrahuj geny drona
  local targetGenes = extractTargetGenesFromDrone(drone_slot)
  
  log("", "INFO")
  
  -- Wybierz najlepszą matkę na podstawie genów drona
  local mother_slot = selectBestMother(targetGenes)
  
  if not mother_slot then
    log("Brak dostepnych matek", "ERROR")
    return
  end
  
  log("", "INFO")
  
  -- Wyświetl szczegóły matki
  printBeeDetails(mother_slot, "INFORMACJE MATKI (PANI MATKA)")
  
  log("", "INFO")
  log("Przenoszenie pary hodowlanej do skrzynki wyjsciowej...", "ACTION")
  
  -- Pobierz dane pszczół PRZED jakimkolwiek transferem
  local drone_stack = t.getStackInSlot(chest_in, drone_slot)
  local mother_stack = t.getStackInSlot(chest_in, mother_slot)
  
  if not drone_stack then
    log("Blad: Dron zniknął z slotu " .. drone_slot, "ERROR")
    return
  end
  
  if not mother_stack then
    log("Blad: Matka zniknęła ze slotu " .. mother_slot, "ERROR")
    return
  end
  
  log("Dron label: " .. (drone_stack.label or "brak"), "DEBUG")
  log("Matka label: " .. (mother_stack.label or "brak"), "DEBUG")
  log("Dron size: " .. (drone_stack.size or 0) .. ", Matka size: " .. (mother_stack.size or 0), "DEBUG")
  
  -- Znajdź dwa wolne sloty
  local free_slot_1 = findFreeSlot(chest_out)
  if not free_slot_1 then
    log("Blad: Brak wolnych slotow dla drona", "ERROR")
    return
  end
  
  local free_slot_2 = findFreeSlot(chest_out)
  if not free_slot_2 then
    log("Blad: Brak dwóch wolnych slotów (tylko jeden)", "ERROR")
    return
  end
  
  log("Sloty do transferu - Dron: " .. free_slot_1 .. ", Matka: " .. free_slot_2, "DEBUG")
  
  -- Transfer drona
  log("Transferuję drona...", "ACTION")
  local moved_drone = t.transferItem(chest_in, chest_out, 1, drone_slot, free_slot_1)
  log("Dron transfer result: " .. tostring(moved_drone), "DEBUG")
  
  if moved_drone ~= 1 then
    log("Blad: Transfer drona nie powiódł się (moved=" .. tostring(moved_drone) .. ")", "ERROR")
    return
  end
  
  log("✓ Dron przeniesiony", "SUCCESS")
  
  -- Sprawdzenie stanu po transferze drona
  local mother_check_after_drone = t.getStackInSlot(chest_in, mother_slot)
  log("STAN PO TRANSFERZE DRONA:", "DEBUG")
  log("  Mother slot " .. mother_slot .. " zawiera: " .. tostring(mother_check_after_drone ~= nil), "DEBUG")
  if mother_check_after_drone then
    log("  Label: " .. (mother_check_after_drone.label or "brak"), "DEBUG")
    log("  Size: " .. (mother_check_after_drone.size or 0), "DEBUG")
  end
  
  -- Sprawdzenie całej chest_in po transferze drona
  log("Transferuję matkę...", "ACTION")
  local moved_mother = t.transferItem(chest_in, chest_out, 1, mother_slot, free_slot_2)
  log("Matka transfer result: " .. tostring(moved_mother), "DEBUG")
  
  if moved_mother ~= 1 then
    log("Blad: Transfer matki nie powiódł się (moved=" .. tostring(moved_mother) .. ")", "ERROR")
    return
  end
  
  log("✓ Matka przeniesiona", "SUCCESS")
  
  log("", "INFO")
  log(string.rep("=", 60), "SUCCESS")
  log("PARA HODOWLANA WYBRANA I PRZENIESIONA", "SUCCESS")
  log(string.rep("=", 60), "SUCCESS")
  log("", "SUCCESS")
  log("Program zakonczony.", "SUCCESS")
end

-- START

initLogFile()

local ok, err = pcall(main)
if not ok then
  log("FATAL ERROR: " .. tostring(err), "FATAL")
  printStats()
end

closeLogFile()
log("LOG ZAPISANY DO: " .. LOG_FILE, "SUCCESS")
