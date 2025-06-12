-- Nastavenie konfiguracie
local reaktorMeno = "reaktor1" -- Unikatne meno tohto reaktora
local kritickeHoruceChladivo = 0.95
local kritickeChladivo = 0.1
local kritickyOdpad = 0.95
local refreshInterval = 2
local povolitRedstone = true
local redstoneStrana = "back" -- Napr. "back", "right", "left"

-- Inicializacia premennych
local alarmAktivny = false
local poslednaAkcia = "--"
local casAkcie = 0

-- Ziskanie periferii
local reaktor = peripheral.find("fissionReactorLogicAdapter")
local monitor = peripheral.find("monitor")
local chat = peripheral.find("chatBox")

-- Kontrola periferii
if not reaktor or not monitor then
  print("Reaktor alebo monitor nenajdeny!")
  return
end

-- Priprava monitora
monitor.setTextScale(1.5)
monitor.setBackgroundColor(colors.black)

-- Zobrazí text vycentrovaný na daný riadok monitora
local function strednyText(y, text, farba)
  local w, _ = monitor.getSize()
  local x = math.floor((w - #text) / 2) + 1
  monitor.setCursorPos(x, y)
  monitor.setTextColor(farba or colors.white)
  monitor.write(text)
end

-- Vykreslí farebné tlačidlo s textom
local function tlacidlo(x, y, text, aktivne)
  monitor.setCursorPos(x, y)
  monitor.setBackgroundColor(aktivne and colors.green or colors.red)
  monitor.setTextColor(colors.black)
  monitor.write(string.rep(" ", 14))
  monitor.setCursorPos(x + 2, y)
  monitor.write(text)
  monitor.setBackgroundColor(colors.black)
end

-- Vykreslí dve tlačidlá vycentrované na monitore
local function vykresliTlacidla(data)
  local w, _ = monitor.getSize()
  local sirkaTlacidla = 14
  local medzera = 2
  local totalWidth = sirkaTlacidla * 2 + medzera
  local startX = math.floor((w - totalWidth) / 2)

  tlacidlo(startX, 12, "ZAPNUT", data.stav)
  tlacidlo(startX + sirkaTlacidla + medzera, 12, "NEAKTIVNY", not data.stav)
end

-- Aktivuje výstražný alarm a odošle správu do chatu
local function prehratAlarm()
  alarmAktivny = true
  if chat then chat.sendMessage("["..reaktorMeno.."]: ALARM aktivovany!", "@a") end
end

-- Zastaví alarm
local function zastavitAlarm()
  alarmAktivny = false
end

-- Vykoná SCRAM, ak je reaktor zapnutý, a aktivuje redstone signál
local function zastavReaktor()
  if reaktor.getStatus() then
    reaktor.scram()
    if povolitRedstone then redstone.setOutput(redstoneStrana, true) end
  end
end

-- Zapne reaktor, ak je vypnutý, a vypne redstone signál
local function zapniReaktor()
  if not reaktor.getStatus() then
    reaktor.activate()
    if povolitRedstone then redstone.setOutput(redstoneStrana, false) end
  end
end

-- Získa a vráti štruktúrované dáta z reaktora
local function ziskajData()
  return {
    stav = reaktor.getStatus(),
    teplota = reaktor.getTemperature(),
    poskodenie = reaktor.getDamagePercent(),
    chladivo = reaktor.getCoolantFilledPercentage(),
    horuce = reaktor.getHeatedCoolantFilledPercentage(),
    odpad = reaktor.getWasteFilledPercentage(),
    palivo = reaktor.getFuelFilledPercentage(),
    spotreba = reaktor.getActualBurnRate(),
    maxSpotreba = reaktor.getMaxBurnRate()
  }
end

-- Vyhodnotí bezpečnostné stavy a podľa potreby SCRAM/ne/alarm
local function kontrolujBezpecnost(data)
  if data.horuce >= kritickeHoruceChladivo then
    zastavReaktor()
    prehratAlarm()
    if chat then chat.sendMessage("["..reaktorMeno.."]: Prilis horuce chladivo!", "@a") end
  elseif data.chladivo <= kritickeChladivo then
    zastavReaktor()
    prehratAlarm()
    if chat then chat.sendMessage("["..reaktorMeno.."]: Nedostatok chladiva!", "@a") end
  elseif data.odpad >= kritickyOdpad then
    zastavReaktor()
    prehratAlarm()
    if chat then chat.sendMessage("["..reaktorMeno.."]: Prilis vela odpadu!", "@a") end
  else
    zastavitAlarm()
    zapniReaktor()
  end
end

-- Vykreslí informácie o stave reaktora na monitor
local function zobraz(data)
  monitor.clear()
  strednyText(1, "REKTOR - " .. string.upper(reaktorMeno), colors.green)

  strednyText(3, "Stav: " .. (data.stav and "Zapnuty" or "Vypnuty"), data.stav and colors.lime or colors.red)
  strednyText(4, string.format("Teplota: %.2f C", data.teplota - 273.15), colors.orange)
  strednyText(5, string.format("Poskodenie: %.1f%%", data.poskodenie * 100), colors.red)
  strednyText(6, string.format("Chladivo: %.1f%%", data.chladivo * 100), colors.cyan)
  strednyText(7, string.format("Horuce chladivo: %.1f%%", data.horuce * 100), colors.magenta)
  strednyText(8, string.format("Odpad: %.1f%%", data.odpad * 100), colors.yellow)
  strednyText(9, string.format("Palivo: %.1f%%", data.palivo * 100), colors.white)
  strednyText(10, string.format("Spotreba: %.2f / %.2f", data.spotreba, data.maxSpotreba), colors.lightGray)

  vykresliTlacidla(data)

  strednyText(15, "Posledna akcia: "..poslednaAkcia, colors.lightBlue)
  strednyText(17, "Prikazy: "..reaktorMeno.." on/off/status/burn set <x>", colors.gray)
end

-- Monitorovacia slučka – zobrazuje údaje a kontroluje stav
local function smyckaMonitor()
  while true do
    local d = ziskajData()
    zobraz(d)
    kontrolujBezpecnost(d)
    sleep(refreshInterval)
  end
end

-- Slučka pre udrzanie redstone signalizacie pocas alarmu
local function redstoneSmycka()
  while true do
    if povolitRedstone and alarmAktivny then
      redstone.setOutput(redstoneStrana, true)
    elseif povolitRedstone then
      redstone.setOutput(redstoneStrana, false)
    end
    sleep(0.5)
  end
end

-- Spracováva príkazy cez chatBox pre tento reaktor
local function prikazovaSmycka()
  if not chat then return function() while true do sleep(10) end end end

  return function()
    while true do
      local _, meno, sprava = os.pullEvent("chat")
      local prikaz = sprava:lower()
      local target, argument = prikaz:match("^(%S+)%s+(.*)$")

      if target == reaktorMeno then
        local cmd, param = argument:match("^(%S+)%s*(.*)$")

        if cmd == "on" then
          zapniReaktor()
          chat.sendMessage("["..reaktorMeno.."]: Zapnuty uzivatelom " .. meno, "@a")
          poslednaAkcia = "MANUALNE ZAPNUTY"
          casAkcie = os.clock()
        elseif cmd == "off" then
          zastavReaktor()
          chat.sendMessage("["..reaktorMeno.."]: SCRAM uzivatelom " .. meno, "@a")
          poslednaAkcia = "MANUALNE VYPNUTY"
          casAkcie = os.clock()
        elseif cmd == "status" then
          local d = ziskajData()
          chat.sendMessage(string.format("[%s]: Teplota: %.2f C | Chladivo: %.1f%% | Odpad: %.1f%% | Palivo: %.1f%% | Spotreba: %.2f", reaktorMeno, d.teplota - 273.15, d.chladivo * 100, d.odpad * 100, d.palivo * 100, d.spotreba), meno)
        elseif cmd == "burn" and param:match("^set%s+%d+%.?%d*$") then
          local val = tonumber(param:match("set%s+(%d+%.?%d*)"))
          if val then
            val = math.min(val, reaktor.getMaxBurnRate())
            reaktor.setBurnRate(val)
            chat.sendMessage("["..reaktorMeno.."]: Spotreba nastavena na " .. val .. " uzivatelom " .. meno, "@a")
          end
        end
      end
    end
  end
end

-- Automaticke zapnutie po starte, ak nie je chyba
zapniReaktor()

-- Spustenie
parallel.waitForAny(smyckaMonitor, prikazovaSmycka(), redstoneSmycka)
