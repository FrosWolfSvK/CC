--[[
  Multi Reactor Control Script
  Autor: [Tvoje meno]
  Popis: Tento skript zabezpecuje automatizovane riadenie fission reaktora,
  kontrolu turbín, monitorovanie a ovládanie cez chat, SCRAM ochranu a vizualizáciu na monitore.
--]]

-- Konfiguracia
local nazovReaktora = "sodik"
local autoZapnutie = true
local povolitRedstone = true
local redstoneStrana = "back"

-- Prahy bezpecnosti (aktualizovane podla poziadavky)
local kritickaHodnotaZahriatehoChladiva = 0.5
local kritickaHodnotaChladiva = 0.2
local kritickaHodnotaOdpadu = 0.95
local intervalObnovy = 2

-- Stav SCRAM a automatika
local scramManualne = false

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
  peripheral.wrap("turbineValve_0"),
  peripheral.wrap("turbineValve_1"),
 --peripheral.wrap("turbineValve_2"),
 --peripheral.wrap("turbineValve_3"),
 --peripheral.wrap("turbineValve_4"),
 --peripheral.wrap("turbineValve_5"),
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
  stredText(22, "Prikazy: status, on/off, auto on/off, info", colors.orange)
  stredText(23, "Cas: " .. textutils.formatTime(os.time(), true), colors.gray)
end

-- Bezpecnostná funkcia SCRAM: núdzovo vypne reaktor
local function scram()
  scramManualne = true
  if reaktor.getStatus() then
    reaktor.scram()
    if povolitRedstone then redstone.setOutput(redstoneStrana, true) end
    posliChatSpravu("Reaktor SCRAM aktivovany.")
  else
    posliChatSpravu("SCRAM nebol spusteny: Reaktor uz je vypnuty.")
  end
end

-- Kontrola stavu a bezpečnostné kroky vrátane automatického zapnutia
local function skontrolujBezpecnost(data)
  local vsetkyTurbinyAktivne = true
  for _, t in ipairs(turbiny) do
    local ok, aktivna = pcall(function() return t.isActive() end)
    if not (ok and aktivna) then
      vsetkyTurbinyAktivne = false
      break
    end
  end

  if data.zahriate >= kritickaHodnotaZahriatehoChladiva
    or data.chladivo <= kritickaHodnotaChladiva
    or data.odpad >= kritickaHodnotaOdpadu
    or not vsetkyTurbinyAktivne
  then
    scram()
    posliChatSpravu("Bezpecnostny SCRAM! Kontroluj system.")
  elseif autoZapnutie and not scramManualne and not data.status then
    if not reaktor.getStatus() then
      reaktor.activate()
      if povolitRedstone then redstone.setOutput(redstoneStrana, false) end
      posliChatSpravu("Reaktor bol automaticky zapnuty.")
    end
  end
end

-- Hlavná smyčka zobrazenia údajov na monitore
local function monitorSmycka()
  while true do
    local data = ziskajDataReaktora()
    vykresliMonitor(data)
    skontrolujBezpecnost(data)
    sleep(intervalObnovy)
  end
end

-- Smyčka spracovania príkazov z chatu
local function prikazSmycka()
  if not chatBox then return end
  while true do
    local _, meno, sprava = os.pullEvent("chat")
    local prikaz = string.lower(sprava)

    if prikaz == "status" then
      local d = ziskajDataReaktora()
      local aktivne = 0
      for _, t in ipairs(turbiny) do
        local ok, stav = pcall(function() return t.isActive() end)
        if ok and stav then aktivne = aktivne + 1 end
      end
      local turbinyStatus = aktivne == #turbiny and "VSETKY AKTIVNE" or (aktivne > 0 and "CASTECNE" or "ZIADNA AKTIVNA")
      chatBox.sendMessage(string.format("[%s] Teplota: %.2f C | Chladivo: %.1f%% | Odpad: %.1f%% | Palivo: %.1f%% | Spotreba: %.2f | Turbiny: %s",
        nazovReaktora, d.teplota - 273.15, d.chladivo * 100, d.odpad * 100, d.palivo * 100, d.rychlost, turbinyStatus), meno)
    elseif prikaz == "info" then
      posliChatSpravu("Prikazy: status, on/off, auto on/off, info")
    else
      local prefix = nazovReaktora .. " "
      if prikaz:sub(1, #prefix) == prefix then
        local cmd = prikaz:sub(#prefix + 1)
        if cmd == "on" then
          scramManualne = false
          if not reaktor.getStatus() then
            reaktor.activate()
            if povolitRedstone then redstone.setOutput(redstoneStrana, false) end
          end
          posliChatSpravu("Reaktor zapnuty rucne.")
        elseif cmd == "off" or cmd == "scram" then
          scram()
          posliChatSpravu("Reaktor vypnuty rucne.")
        elseif cmd == "auto on" then
          autoZapnutie = true
          posliChatSpravu("Automaticke zapnutie je povolene.")
        elseif cmd == "auto off" then
          autoZapnutie = false
          posliChatSpravu("Automaticke zapnutie je zakazane.")
        end
      end
    end
  end
end

-- Spustí monitorovaciu a príkazovú smyčku súčasne
parallel.waitForAny(monitorSmycka, prikazSmycka)
