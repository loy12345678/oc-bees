local component = require("component")
local sides = require("sides")

local t = component.transposer

local function log(msg)
  print("[SIDE-DEBUG] " .. msg)
end

log("=== START TESTU STRON TRANSPOSERA ===")

-- 🔍 test wszystkich stron 0–5
for i = 0, 5 do
  local size = t.getInventorySize(i)

  if size then
    log("✔ SIDE " .. i .. " = INVENTORY, slotów: " .. size)

    -- pokazujemy co jest w środku
    for slot = 1, size do
      local stack = t.getStackInSlot(i, slot)

      if stack then
        log("  SLOT " .. slot .. " -> " .. (stack.label or "UNKNOWN") .. " x" .. (stack.size or 0))
      end
    end

  else
    log("❌ SIDE " .. i .. " = brak inventory")
  end
end

log("=== KONIEC TESTU ===")
