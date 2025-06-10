-- Multi Reaktor Kontrola a Ovládanie

local nazovReaktora = "reaktor1"  -- Nastav meno tohto reaktora
local povolitRedstone = true        -- Prepni na false ak nechces redstone signal

local kritHeated = 0.95
local kritCoolant = 0.1
local kritOdpad = 0.95
local interval = 2

local alarmAktivny = false
local manualnySCRAM = false

local reaktor = peripheral.find("fissionReactorLogicAdapter")
local monitor = peripheral.find("monitor")
local zvuk = peripheral.find("speaker")
local chat = peripheral.find("chatBox")

if not reaktor or not monitor then
  print("CHYBA: Reaktor alebo monitor nenajdeny!")
  return
end

monitor.setTextScale(1.5)
monitor.setBackgroundColor(colors.black)

local function stredText(y, text, farba)
  local w, _ = monitor.getSize()
  local x = math.floor((w - #text) / 2) + 1
  monitor.setCursorPos(x, y)
  monitor.setTextColor(farba or colors.white)
  monitor.write(text)
end

local function tlacidlo(x, y, text, aktivne)
  monitor.setCursorPos(x, y)
  monitor.setBackgroundColor(aktivne and colors.green or colors.gray)
  monitor.setTextColor(colors.black)
  monitor.write(string.rep(" ", 12))
  monitor.setCursorPos(x + 1, y)
  monitor.write(text)
  monitor.setBackgroundColor(colors.black)
end

local function spustiAlarm()
  if zvuk and not alarmAktivny then
    zvuk.playSound("minecraft:block.note_block.bass", 1, 0.5)
    alarmAktivny = true
  end
end

local function zastavAlarm()
  alarmAktivny = false
end

local function posliChat(sprava)
  if chat then
    chat.sendMessage("[" .. nazovReaktora .. "]: " .. sprava, "@a")
  end
end

local function dataReaktora()
  return {
    status = reaktor.getStatus(),
    teplota = reaktor.getTemperature(),
    poskodenie = reaktor.getDamagePercent(),
    coolant = reaktor.getCoolantFilledPercentage(),
    heated = reaktor.getHeatedCoolantFilledPercentage(),
    odpad = reaktor.getWasteFilledPercentage(),
    palivo = reaktor.getFuelFilledPercentage(),
    burn = reaktor.getActualBurnRate(),
    maxBurn = reaktor.getMaxBurnRate()
  }
end

local function scram()
  if reaktor.getStatus() then
    reaktor.scram()
    manualnySCRAM = true
    if povolitRedstone then redstone.setOutput("back", true) end
  end
end

local function zapniReaktor()
  if not reaktor.getStatus() then
    reaktor.activate()
    manualnySCRAM = false
    if povolitRedstone then redstone.setOutput("back", false) end
  end
end

local function updateZobrazenie(data)
  monitor.clear()
  stredText(1, "REACTOR - " .. nazovReaktora, colors.green)

  stredText(3, "Stav: " .. (data.status and "Online" or "Offline"), data.status and colors.lime or colors.red)
  stredText(4, string.format("Teplota: %.2f C", data.teplota - 273.15), colors.orange)
  stredText(5, string.format("Poskodenie: %.1f%%", data.poskodenie * 100), colors.red)
  stredText(6, string.format("Coolant: %.1f%%", data.coolant * 100), colors.cyan)
  stredText(7, string.format("Heated: %.1f%%", data.heated * 100), colors.magenta)
  stredText(8, string.format("Odpad: %.1f%%", data.odpad * 100), colors.yellow)
  stredText(9, string.format("Palivo: %.1f%%", data.palivo * 100), colors.white)
  stredText(10, string.format("Burn: %.2f / %.2f", data.burn, data.maxBurn), colors.lightGray)

  tlacidlo(5, 12, "ZAPNUT", data.status)
  tlacidlo(20, 12, "SCRAM", not data.status)

  stredText(16, "Obnovene: " .. textutils.formatTime(os.time(), true), colors.gray)
  stredText(18, "Prikazy: meno on/off/burn/status", colors.lightBlue)
end

local function kontrolaBezpecnosti(data)
  if data.heated >= kritHeated or data.coolant <= kritCoolant or data.odpad >= kritOdpad then
    scram()
    spustiAlarm()
    if data.heated >= kritHeated then posliChat("Heated coolant prilis vysoko!") end
    if data.coolant <= kritCoolant then posliChat("Nizka hladina chladiva!") end
    if data.odpad >= kritOdpad then posliChat("Odpad prilis vysoko!") end
  else
    zastavAlarm()
    if not data.status and not manualnySCRAM then
      zapniReaktor()
      posliChat("Reaktor automaticky spusteny po odstraneni kritickeho stavu.")
    end
  end
end

local function prikazovaSmycka()
  if not chat then return function() while true do os.pullEvent("key") end end end

  return function()
    while true do
      local _, uzivatel, sprava = os.pullEvent("chat")
      local input = sprava:lower()
      if not input:match("^" .. nazovReaktora) then goto continue end
      local cmd = input:gsub(nazovReaktora .. " ", "")

      if cmd == "on" then
        zapniReaktor()
        posliChat("Reaktor zapnuty uzivatelom " .. uzivatel)
      elseif cmd == "off" then
        scram()
        posliChat("Reaktor SCRAM uzivatelom " .. uzivatel)
      elseif cmd:match("^burn set%s+(%d+%.?%d*)") then
        local val = tonumber(cmd:match("^burn set%s+(%d+%.?%d*)"))
        if val then
          val = math.min(val, reaktor.getMaxBurnRate())
          reaktor.setBurnRate(val)
          posliChat("Burn rate nastaveny na " .. val .. " uzivatelom " .. uzivatel)
        end
      elseif cmd == "status" then
        local d = dataReaktora()
        posliChat(string.format("T: %.1fC C: %.1f%% O: %.1f%% P: %.1f%% B: %.2f", d.teplota - 273.15, d.coolant * 100, d.odpad * 100, d.palivo * 100, d.burn))
      end
      ::continue::
    end
  end
end

local function monitorSmycka()
  while true do
    local data = dataReaktora()
    updateZobrazenie(data)
    kontrolaBezpecnosti(data)
    sleep(interval)
  end
end

parallel.waitForAny(monitorSmycka, prikazovaSmycka())
