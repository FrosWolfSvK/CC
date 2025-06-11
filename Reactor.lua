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
for i = 1, 6 do
  local t = peripheral.find("turbineLogicAdapter", function(name, obj)
    return not turbiny[name] -- zabezpeci unikatnost
  end)
  if t then turbiny[#turbiny+1] = t end
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

local function vykresliTurbiny()
  monitor.setCursorPos(1, 11)
  monitor.setTextColor(colors.white)
  monitor.write("Stav Turbin:")
  for i, turbina in ipairs(turbiny) do
    local aktivna = turbina.isActive()
    local farba = aktivna and colors.lime or colors.red
    local riadok = 11 + math.floor((i - 1) / 3) + 1
    local stlpec = 2 + ((i - 1) % 3) * 8
    monitor.setCursorPos(stlpec, riadok)
    monitor.setTextColor(farba)
    monitor.write("T" .. i .. ": " .. (aktivna and "OK" or "ZLY"))
  end
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

local function vykresliMonitor(data)
  monitor.clear()
  stredText(1, "REZIM: " .. nazovReaktora, colors.green)
  stredText(3, "Status: " .. (data.status and "Online" or "Offline"), data.status and colors.lime or colors.red)
  stredText(4, string.format("Teplota: %.2f C", data.teplota - 273.15), colors.orange)
  stredText(5, string.format("Poskodenie: %.1f%%", data.poskodenie * 100), colors.red)
  stredText(6, string.format("Chladivo: %.1f%%", data.chladivo * 100), colors.cyan)
  stredText(7, string.format("Zahriate chladivo: %.1f%%", data.zahriate * 100), colors.magenta)
  stredText(8, string.format("Odpad: %.1f%%", data.odpad * 100), colors.yellow)
  stredText(9, string.format("Palivo: %.1f%%", data.palivo * 100), colors.white)
  stredText(10, string.format("Spotreba: %.2f / %.2f", data.rychlost, data.maxRychlost), colors.lightGray)
  vykresliTurbiny()
  vykresliTlacidlo(4, 18, "ZAPNUT", data.status)
  vykresliTlacidlo(18, 18, "NEAKTIVNY", not data.status)
  stredText(20, "Auto-zapnutie: " .. (autoZapnutie and "ZAPNUTE" or "VYPNUTE"), autoZapnutie and colors.lime or colors.red)
  stredText(21, "Turbiny musia byt vsetky aktivne", colors.lightBlue)
  stredText(22, "Cas: " .. textutils.formatTime(os.time(), true), colors.gray)
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
      local vsetky = true
      for _, t in ipairs(turbiny) do if not t.isActive() then vsetky = false break end end
      local turbinyStatus = vsetky and "VSETKY AKTIVNE" or "NIEKTORA NEAKTIVNA"
      chatBox.sendMessage(string.format("[%s] Teplota: %.2f C | Chladivo: %.1f%% | Odpad: %.1f%% | Palivo: %.1f%% | Spotreba: %.2f | Turbiny: %s",
        nazovReaktora, d.teplota - 273.15, d.chladivo * 100, d.odpad * 100, d.palivo * 100, d.rychlost, turbinyStatus), meno)
    end
  end
end

parallel.waitForAny(monitorSmycka, prikazSmycka)
