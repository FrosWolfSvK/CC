-- Konfiguracia prahov
local kritickeZahriateChladivo = 0.95
local kritickeChladivo = 0.1
local kritickyOdpad = 0.95
local refreshInterval = 2

-- Redstone konfiguracia
local enableRedstoneOutput = true
local redstoneSide = "back"

-- Stavove premenne
local alarmAktivny = false
local bolNebezpecnyStav = false
local poslednaAkcia = ""
local casAkcie = 0

-- Ziskanie periferii
local reaktor = peripheral.find("fissionReactorLogicAdapter")
local monitor = peripheral.find("monitor")
local reproduktor = peripheral.find("speaker")
local chat = peripheral.find("chatBox")

-- Overenie periferii
if not reaktor or not monitor then
  print("Chyba: reaktor alebo monitor nenajdeny!")
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

local function vykresliTlacidlo(x, y, popis, aktivne)
  monitor.setCursorPos(x, y)
  monitor.setBackgroundColor(aktivne and colors.green or colors.gray)
  monitor.setTextColor(colors.black)
  monitor.write(string.rep(" ", 12))
  monitor.setCursorPos(x + 1, y)
  monitor.write(popis)
  monitor.setBackgroundColor(colors.black)
end

local function prehratAlarm()
  if reproduktor and not alarmAktivny then
    reproduktor.playSound("minecraft:block.note_block.bass", 1, 0.5)
    alarmAktivny = true
  end
end

local function zastavAlarm()
  alarmAktivny = false
end

local function posliSpravu(msg)
  if chat then
    chat.sendMessage("[Reaktor]: " .. msg, "@a")
  end
end

local function ziskajData()
  return {
    stav = reaktor.getStatus(),
    teplota = reaktor.getTemperature(),
    poskodenie = reaktor.getDamagePercent(),
    chladivo = reaktor.getCoolantFilledPercentage(),
    zahriate = reaktor.getHeatedCoolantFilledPercentage(),
    odpad = reaktor.getWasteFilledPercentage(),
    palivo = reaktor.getFuelFilledPercentage(),
    spotreba = reaktor.getActualBurnRate(),
    maximum = reaktor.getMaxBurnRate()
  }
end

local function vykresliDisplej(data)
  monitor.clear()
  stredText(1, "REAKTOR - STAV", colors.green)

  stredText(3, "Stav: " .. (data.stav and "Online" or "Offline"), data.stav and colors.lime or colors.red)
  stredText(4, string.format("Teplota: %.2f C", data.teplota - 273.15), colors.orange)
  stredText(5, string.format("Poskodenie: %.1f%%", data.poskodenie * 100), colors.red)
  stredText(6, string.format("Chladivo: %.1f%%", data.chladivo * 100), colors.cyan)
  stredText(7, string.format("Zahriate chladivo: %.1f%%", data.zahriate * 100), colors.magenta)
  stredText(8, string.format("Odpad: %.1f%%", data.odpad * 100), colors.yellow)
  stredText(9, string.format("Palivo: %.1f%%", data.palivo * 100), colors.white)
  stredText(10, string.format("Spotreba: %.2f / %.2f", data.spotreba, data.maximum), colors.lightGray)

  vykresliTlacidlo(5, 12, " Zapnut ", data.stav)
  vykresliTlacidlo(20, 12, " SCRAM ", not data.stav)

  if poslednaAkcia ~= "" then
    stredText(14, "Posledna akcia: " .. poslednaAkcia, colors.lightBlue)
  end

  stredText(16, "Cas: " .. textutils.formatTime(os.time(), true), colors.gray)
  stredText(18, "Prikazy: on / off / burn set <cislo> / status", colors.lightBlue)
end

local function zastavReaktor()
  if reaktor.getStatus() then
    reaktor.scram()
  end
end

local function skontrolujBezpecnost(data)
  if data.zahriate >= kritickeZahriateChladivo then
    zastavReaktor()
    prehratAlarm()
    posliSpravu("Zahriate chladivo je prilis vysoke!")
    bolNebezpecnyStav = true
    poslednaAkcia = "REAKTOR ZASTAVENY Z DOVODU BEZPECNOSTI"
    casAkcie = os.clock()
    if enableRedstoneOutput then redstone.setOutput(redstoneSide, true) end
  elseif data.chladivo <= kritickeChladivo then
    zastavReaktor()
    prehratAlarm()
    posliSpravu("Chladivo je prilis nizke!")
    bolNebezpecnyStav = true
    poslednaAkcia = "REAKTOR ZASTAVENY Z DOVODU BEZPECNOSTI"
    casAkcie = os.clock()
    if enableRedstoneOutput then redstone.setOutput(redstoneSide, true) end
  elseif data.odpad >= kritickyOdpad then
    zastavReaktor()
    prehratAlarm()
    posliSpravu("Prilis vela odpadu v reaktore!")
    bolNebezpecnyStav = true
    poslednaAkcia = "REAKTOR ZASTAVENY Z DOVODU BEZPECNOSTI"
    casAkcie = os.clock()
    if enableRedstoneOutput then redstone.setOutput(redstoneSide, true) end
  else
    zastavAlarm()
  end
end

local function skontrolujObnovuStavu(data)
  if bolNebezpecnyStav then
    if data.zahriate < kritickeZahriateChladivo and
       data.chladivo > kritickeChladivo and
       data.odpad < kritickyOdpad then
      if not reaktor.getStatus() then
        reaktor.activate()
        posliSpravu("Reaktor automaticky znovu zapnuty – stav je uz bezpecny.")
        poslednaAkcia = "AUTOMATICKY ZAPNUTY"
        casAkcie = os.clock()
        if enableRedstoneOutput then redstone.setOutput(redstoneSide, false) end
      end
      bolNebezpecnyStav = false
    end
  end
end

local function monitorSmycka()
  -- Pokus o automaticke zapnutie
  if not reaktor.getStatus() then
    reaktor.activate()
    posliSpravu("Reaktor bol automaticky zapnuty.")
    poslednaAkcia = "ZAPNUTY PRI SPUSTENI"
    casAkcie = os.clock()
  end

  while true do
    local data = ziskajData()
    vykresliDisplej(data)
    skontrolujBezpecnost(data)
    skontrolujObnovuStavu(data)
    sleep(refreshInterval)
  end
end

local function prikazovaSmycka()
  if not chat then
    print("ChatBox nie je dostupny. Prikazy nebudu fungovat.")
    return
  end

  while true do
    local _, meno, sprava = os.pullEvent("chat")
    local prikaz = sprava:lower()

    if prikaz == "on" then
      reaktor.activate()
      chat.sendMessage("Reaktor zapnuty uzivatelom " .. meno, "@a")
      poslednaAkcia = "MANUALNE ZAPNUTY"
      casAkcie = os.clock()
    elseif prikaz == "off" then
      zastavReaktor()
      chat.sendMessage("Reaktor SCRAM uzivatelom " .. meno, "@a")
      poslednaAkcia = "MANUALNE VYPNUTY"
      casAkcie = os.clock()
    elseif prikaz:match("^burn set%s+(%d+%.?%d*)") then
      local hodnota = tonumber(prikaz:match("^burn set%s+(%d+%.?%d*)"))
      if hodnota then
        hodnota = math.min(hodnota, reaktor.getMaxBurnRate())
        reaktor.setBurnRate(hodnota)
        chat.sendMessage("Spotreba nastavena na " .. hodnota .. " uzivatelom " .. meno, "@a")
        poslednaAkcia = "ZMENENA SPOTREBA"
        casAkcie = os.clock()
      end
    elseif prikaz == "status" then
      local d = ziskajData()
      chat.sendMessage(
        string.format("Teplota: %.2f C | Chladivo: %.1f%% | Odpad: %.1f%% | Palivo: %.1f%% | Spotreba: %.2f",
          d.teplota - 273.15, d.chladivo * 100, d.odpad * 100, d.palivo * 100, d.spotreba),
        meno
      )
    end
  end
end

-- Spustenie oboch smyciek paralelne
parallel.waitForAny(monitorSmycka, prikazovaSmycka)
