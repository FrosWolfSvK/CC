--[[
  Multi Reactor Control Script
  Autor: [Tvoje meno]
  Popis: Tento skript zabezpecuje automatizovane riadenie fission reaktora,
  kontrolu turbín, monitorovanie a ovládanie cez chat, SCRAM ochranu a vizualizáciu na monitore.
--]]

-- Konfiguracia
local nazovReaktora = "reaktor1"
local autoZapnutie = true
local povolitRedstone = true
local redstoneStrana = "back"

-- Prahy bezpecnosti (aktualizovane podla poziadavky)
local kritickaHodnotaZahriatehoChladiva = 0.5
local kritickaHodnotaChladiva = 0.2
local kritickaHodnotaOdpadu = 0.95
local intervalObnovy = 2
local oneskorenieSCRAM = 10 -- cas v sekundach, po ktorom sa moze SCRAM aktivovat

-- Stav SCRAM a automatika
local scramManualne = false
local spustenieSCRAMOneskorene = false
local casZaciatku = os.clock()

-- Najde a vrati periferiu daného typu (alebo nil ak nie je pripojená)
local function najdiPeriferiu(typ)
  local ok, zariadenie = pcall(function()
    return peripheral.find(typ)
  end)
  return ok and zariadenie or nil
end

-- Inicializácia základných periférií
local reaktor = najdiPeriferiu("fissionReactorLogicAdapter")
local monitor = najdiPeriferiu("monitor")
local chatBox = najdiPeriferiu("chatBox")

-- Zoznam manuálne definovaných turbín (max 6)
local turbiny = {
  peripheral.wrap("turbineValve_1"),
  peripheral.wrap("turbineValve_2"),
  peripheral.wrap("turbineValve_3")
}

-- Kontrola existencie periférií
if not reaktor or not monitor then
  print("Reaktor alebo monitor nie je pripojeny!")
  return
end

-- Inicializuje monitor pre výstup údajov
monitor.setTextScale(1.5)
monitor.setBackgroundColor(colors.black)

-- Vykreslí text na stred daného riadku
local function stredText(y, text, farba)
  local w, _ = monitor.getSize()
  local x = math.floor((w - #text) / 2) + 1
  monitor.setCursorPos(x, y)
  monitor.setTextColor(farba or colors.white)
  monitor.write(text)
end

-- Zobrazí súhrnný stav turbín (koľko je aktívnych)
local function vykresliTurbinyZjednotene()
  local aktivne = 0
  for _, turbina in ipairs(turbiny) do
    local ok, aktivna = pcall(function() return turbina.isActive() end)
    if ok and aktivna then aktivne = aktivne + 1 end
  end
  local farba = aktivne == #turbiny and colors.lime or (aktivne > 0 and colors.yellow or colors.red)
  monitor.setCursorPos(1, 11)
  monitor.setTextColor(farba)
  monitor.write("Turbiny: " .. aktivne .. "/" .. #turbiny)
end

-- Vykreslí tlačidlo na monitore
local function vykresliTlacidlo(x, y, text, aktivne)
  monitor.setCursorPos(x, y)
  monitor.setBackgroundColor(aktivne and colors.green or colors.gray)
  monitor.setTextColor(colors.black)
  monitor.write(string.rep(" ", 12))
  monitor.setCursorPos(x + 1, y)
  monitor.write(text)
  monitor.setBackgroundColor(colors.black)
end

-- Odošle správu do chatu pomocou chatBoxu
local function posliChatSpravu(sprava)
  if chatBox then
    chatBox.sendMessage("[" .. nazovReaktora .. "]: " .. sprava, "@a")
  end
end

-- Načíta aktuálne údaje z reaktora
local function ziskajDataReaktora()
  local ok, data = pcall(function()
    return {
      status = reaktor.getStatus(),
      teplota = reaktor.getTemperature(),
      poskodenie = reaktor.getDamagePercent(),
      chladivo = reaktor.getCoolantFilledPercentage(),
      zahriate = reaktor.getHeatedCoolantFilledPercentage(),
      odpad = reaktor.getWasteFilledPercentage(),
      palivo = reaktor.getFuelFilledPercentage(),
      rychlost = reaktor.getActualBurnRate(),
      maxRychlost = reaktor.getMaxBurnRate()
    }
  end)
  if not ok then
    return {
      status = false,
      teplota = 0,
      poskodenie = 0,
      chladivo = 0,
      zahriate = 0,
      odpad = 0,
      palivo = 0,
      rychlost = 0,
      maxRychlost = 0
    }
  end
  return data
end

-- Zobrazí text s percentami na danom riadku
local function vykresliPercenta(y, popis, hodnota, farba)
  local percent = math.floor(hodnota * 100)
  stredText(y, string.format("%s: %d%%", popis, percent), farba)
end

-- Zobrazí kompletné informácie o stave reaktora
local function vykresliMonitor(data)
  monitor.clear()
  stredText(1, "REAKTOR: " .. nazovReaktora, colors.green)
  stredText(3, "Status: " .. (data.status and "Online" or "Offline"), data.status and colors.lime or colors.red)
  stredText(4, string.format("Teplota: %.2f C", data.teplota - 273.15), colors.orange)
  stredText(5, string.format("Poskodenie: %.1f%%", data.poskodenie * 100), colors.red)
  vykresliPercenta(6, "Chladivo", data.chladivo, colors.cyan)
  vykresliPercenta(7, "Zahriate chladivo", data.zahriate, colors.magenta)
  vykresliPercenta(8, "Odpad", data.odpad, colors.yellow)
  vykresliPercenta(9, "Palivo", data.palivo, colors.white)
  stredText(11, string.format("Spotreba: %.2f / %.2f", data.rychlost, data.maxRychlost), colors.lightGray)
  vykresliTurbinyZjednotene()
  vykresliTlacidlo(4, 18, "ZAPNUT", data.status)
  vykresliTlacidlo(18, 18, "NEAKTIVNY", not data.status)
  stredText(20, "Auto-zapnutie: " .. (autoZapnutie and "ZAPNUTE" or "VYPNUTE"), autoZapnutie and colors.lime or colors.red)
  stredText(21, "Turbiny musia byt vsetky aktivne", colors.lightBlue)
  stredText(22, "Prikazy: status, info, " .. nazovReaktora .. " on/off/auto", colors.orange)
  stredText(23, "Cas: " .. textutils.formatTime(os.time(), true), colors.gray)
end

-- Spracovanie príkazov cez chat
local function prikazSmycka()
  while true do
    local e, username, message = os.pullEvent("chat")
    local msg = string.lower(message)

    -- Parsovanie pre prikazy typu "reaktorX prikaz"
    local cmd_reaktor, cmd_action = msg:match("^(reaktor%d+) (%a+)$")
    if cmd_reaktor and cmd_action then
      if cmd_reaktor == nazovReaktora then
        if cmd_action == "on" then
          if not scramManualne then
            reaktor.setStatus(true)
            posliChatSpravu("Reaktor zapnuty")
          else
            posliChatSpravu("Nie je mozne zapnut, SCRAM aktivny")
          end
        elseif cmd_action == "off" then
          reaktor.setStatus(false)
          posliChatSpravu("Reaktor vypnuty")
        elseif cmd_action == "auto" then
          autoZapnutie = not autoZapnutie
          posliChatSpravu("Auto-zapnutie: " .. (autoZapnutie and "ZAPNUTE" or "VYPNUTE"))
        end
      end

    -- Univerzalne prikazy bez prefixu
    elseif msg == "status" then
      local data = ziskajDataReaktora()
      posliChatSpravu("Reaktor je " .. (data.status and "zapnuty" or "vypnuty"))
    elseif msg == "info" then
      local data = ziskajDataReaktora()
      posliChatSpravu(string.format("Teplota: %.1fC, Poskodenie: %.1f%%", data.teplota - 273.15, data.poskodenie * 100))
    end
  end
end
