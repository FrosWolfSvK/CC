-- Konfiguracia
local nazovReaktora = "reaktor1"
local autoZapnutie = true
local povolitRedstone = true
local redstoneStrana = "back"

-- Prahy
local kritickaHodnotaZahriatehoChladiva = 0.95
local kritickaHodnotaChladiva = 0.1
local kritickaHodnotaOdpadu = 0.95
local intervalObnovy = 2

-- Stav
local alarmAktivny = false
local scramManualne = false

-- Periferie
local reaktor = peripheral.find("fissionReactorLogicAdapter")
local monitor = peripheral.find("monitor")
local reproduktor = peripheral.find("speaker")
local chatBox = peripheral.find("chatBox")

-- Ziskaj turbiny (max 6)
local turbiny = {}
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "turbineLogicAdapter" then
    table.insert(turbiny, peripheral.wrap(name))
    if #turbiny >= 6 then break end
  end
end

-- Kontrola periferii
if not reaktor or not monitor then
  print("Reaktor alebo monitor nie je pripojeny!")
  return
end

-- Nastavenie monitora
monitor.setTextScale(1.5)
monitor.setBackgroundColor(colors.black)

-- Pomocne funkcie
local function stredText(y, text, farba)
  local w, _ = monitor.getSize()
  local x = math.floor((w - #text) / 2) + 1
  monitor.setCursorPos(x, y)
  monitor.setTextColor(farba or colors.white)
  monitor.write(text)
end

local function vykresliTurbinyZjednotene()
  local aktivne = 0
  for _, turbina in ipairs(turbiny) do
    if turbina.isActive() then aktivne = aktivne + 1 end
  end
  local farba = aktivne == #turbiny and colors.lime or (aktivne > 0 and colors.yellow or colors.red)
  monitor.setCursorPos(1, 11)
  monitor.setTextColor(farba)
  monitor.write("Turbiny: " .. aktivne .. "/" .. #turbiny)
end

local function vykresliTlacidlo(x, y, text, aktivne)
  monitor.setCursorPos(x, y)
  monitor.setBackgroundColor(aktivne and colors.green or colors.gray)
  monitor.setTextColor(colors.black)
  monitor.write(string.rep(" ", 12))
  monitor.setCursorPos(x + 1, y)
  monitor.write(text)
  monitor.setBackgroundColor(colors.black)
end

local function prehratAlarm()
  if reproduktor and not alarmAktivny then
    reproduktor.playSound("minecraft:block.note_block.bass", 1, 0.5)
    alarmAktivny = true
  end
end

local function zastavitAlarm()
  alarmAktivny = false
end

local function posliChatSpravu(sprava)
  if chatBox then
    chatBox.sendMessage("[" .. nazovReaktora .. "]: " .. sprava, "@a")
  end
end

local function ziskajDataReaktora()
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
end

local function vykresliProgressBar(y, popis, hodnota, farba)
  local w, _ = monitor.getSize()
  local sirka = math.floor(w * 0.8)
  local x = math.floor((w - sirka) / 2) + 1
  local plne = math.floor(hodnota * sirka)
  monitor.setCursorPos(x, y)
  monitor.setTextColor(colors.white)
  monitor.write(popis .. ":")
  monitor.setCursorPos(x, y + 1)
  monitor.setBackgroundColor(colors.gray)
  monitor.write(string.rep(" ", sirka))
  monitor.setCursorPos(x, y + 1)
  monitor.setBackgroundColor(farba)
  monitor.write(string.rep(" ", plne))
  monitor.setBackgroundColor(colors.black)
end

local function vykresliMonitor(data)
  monitor.clear()
  stredText(1, "REZIM: " .. nazovReaktora, colors.green)
  stredText(3, "Status: " .. (data.status and "Online" or "Offline"), data.status and colors.lime or colors.red)
  stredText(4, string.format("Teplota: %.2f C", data.teplota - 273.15), colors.orange)
  stredText(5, string.format("Poskodenie: %.1f%%", data.poskodenie * 100), colors.red)

  vykresliProgressBar(6, "Chladivo", data.chladivo, colors.cyan)
  vykresliProgressBar(8, "Zahriate chladivo", data.zahriate, colors.magenta)
  vykresliProgressBar(10, "Odpad", data.odpad, colors.yellow)
  vykresliProgressBar(12, "Palivo", data.palivo, colors.white)

  stredText(14, string.format("Spotreba: %.2f / %.2f", data.rychlost, data.maxRychlost), colors.lightGray)
  vykresliTurbinyZjednotene()
  vykresliTlacidlo(4, 18, "ZAPNUT", data.status)
  vykresliTlacidlo(18, 18, "NEAKTIVNY", not data.status)
  stredText(20, "Auto-zapnutie: " .. (autoZapnutie and "ZAPNUTE" or "VYPNUTE"), autoZapnutie and colors.lime or colors.red)
  stredText(21, "Turbiny musia byt vsetky aktivne", colors.lightBlue)
  stredText(22, "Prikazy: status, on, off, scram, auto on/off, info", colors.orange)
  stredText(23, "Cas: " .. textutils.formatTime(os.time(), true), colors.gray)
end

local function scram()
  scramManualne = true
  reaktor.scram()
  if povolitRedstone then redstone.setOutput(redstoneStrana, true) end
end

local function skontrolujBezpecnost(data)
  local vsetkyTurbinyAktivne = true
  for _, t in ipairs(turbiny) do
    if not t.isActive() then
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
    prehratAlarm()
    posliChatSpravu("Bezpecnostny SCRAM! Kontroluj system.")
  else
    zastavitAlarm()
    if autoZapnutie and not scramManualne and not data.status then
      reaktor.activate()
      if povolitRedstone then redstone.setOutput(redstoneStrana, false) end
      posliChatSpravu("Reaktor bol automaticky zapnuty.")
    end
  end
end

local function monitorSmycka()
  while true do
    local data = ziskajDataReaktora()
    vykresliMonitor(data)
    skontrolujBezpecnost(data)
    sleep(intervalObnovy)
  end
end

local function prikazSmycka()
  if not chatBox then return end
  while true do
    local _, meno, sprava = os.pullEvent("chat")
    local prikaz = string.lower(sprava)

    if prikaz == "status" then
      local d = ziskajDataReaktora()
      local aktivne = 0
      for _, t in ipairs(turbiny) do if t.isActive() then aktivne = aktivne + 1 end end
      local turbinyStatus = aktivne == #turbiny and "VSETKY AKTIVNE" or (aktivne > 0 and "CASTECNE" or "ZIAIDNA AKTIVNA")
      chatBox.sendMessage(string.format("[%s] Teplota: %.2f C | Chladivo: %.1f%% | Odpad: %.1f%% | Palivo: %.1f%% | Spotreba: %.2f | Turbiny: %s",
        nazovReaktora, d.teplota - 273.15, d.chladivo * 100, d.odpad * 100, d.palivo * 100, d.rychlost, turbinyStatus), meno)
    elseif prikaz == "on" then
      scramManualne = false
      reaktor.activate()
      if povolitRedstone then redstone.setOutput(redstoneStrana, false) end
      posliChatSpravu("Reaktor zapnuty rucne.")
    elseif prikaz == "off" then
      scramManualne = true
      reaktor.scram()
      if povolitRedstone then redstone.setOutput(redstoneStrana, true) end
      posliChatSpravu("Reaktor vypnuty rucne.")
    elseif prikaz == "scram" then
      scramManualne = true
      reaktor.scram()
      if povolitRedstone then redstone.setOutput(redstoneStrana, true) end
      posliChatSpravu("SCRAM vykonany.")
    elseif prikaz == "auto on" then
      autoZapnutie = true
      posliChatSpravu("Automaticke zapnutie je povolene.")
    elseif prikaz == "auto off" then
      autoZapnutie = false
      posliChatSpravu("Automaticke zapnutie je zakazane.")
    elseif prikaz == "info" then
      posliChatSpravu("Prikazy: status, on, off, scram, auto on, auto off, info")
    end
  end
end

parallel.waitForAny(monitorSmycka, prikazSmycka)
