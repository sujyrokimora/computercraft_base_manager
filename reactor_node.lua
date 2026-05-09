local net = require("common")
local config = require("reactor_config")
local manifest = require("manifest")
local TOKEN = manifest.token

net.openModem()

local reactor = peripheral.find(config.reactorPeripheralType or "fissionReactorLogicAdapter")
  or peripheral.find("fissionReactor")

if not reactor then
  error("No fission reactor peripheral found")
end

local lockout = false
local lockoutReason = ""
local lastHeartbeatStatus = nil

local function toC(k)
  return k - 273.15
end

local function callIfExists(obj, names)
  for _, name in ipairs(names) do
    if obj and type(obj[name]) == "function" then
      local ok, value = pcall(obj[name])
      if ok then return value end
    end
  end
  return nil
end

local function getReactorActive()
  local v = callIfExists(reactor, {"getStatus", "getActive", "isActive"})
  return v == true
end

local function getMaxBurnRate()
  local v = callIfExists(reactor, {"getMaxBurnRate", "getMaxBurn", "getMaxRate"})
  if type(v) == "number" then return v end
  return config.maxBurnRate or 0
end

local function getBurnRate()
  local v = callIfExists(reactor, {"getBurnRate", "getBurnRateLimit", "getActualBurnRate"})
  if type(v) == "number" then return v end
  return nil
end

local function setBurnRate(rate)
  if lockout then
    return false, "LOCKOUT active. Reset required before changing burn rate."
  end

  local maxBurn = getMaxBurnRate()

  if maxBurn > 0 and rate > maxBurn then rate = maxBurn end
  if rate < 0 then rate = 0 end

  if type(reactor.setBurnRate) == "function" then
    local ok, err = pcall(reactor.setBurnRate, rate)
    if ok then return true, "Burn rate set to " .. rate end
    return false, tostring(err)
  end

  if type(reactor.setBurnRateLimit) == "function" then
    local ok, err = pcall(reactor.setBurnRateLimit, rate)
    if ok then return true, "Burn rate set to " .. rate end
    return false, tostring(err)
  end

  return false, "No burn-rate method found"
end

local function activateReactor()
  if lockout then
    return false, "LOCKOUT active. Reset required: " .. lockoutReason
  end

  if getReactorActive() then
    return true, "Already active"
  end

  if type(reactor.activate) == "function" then
    local ok, err = pcall(reactor.activate)
    if ok then return true, "Reactor activated" end
    return false, tostring(err)
  end

  if type(reactor.setActive) == "function" then
    local ok, err = pcall(reactor.setActive, true)
    if ok then return true, "Reactor activated" end
    return false, tostring(err)
  end

  return false, "No activate method"
end

local function scramReactor()
  if not getReactorActive() then return true, "Already off" end

  if type(reactor.scram) == "function" then
    local ok, err = pcall(reactor.scram)
    if ok then return true, "Reactor SCRAM/OFF" end
    return false, tostring(err)
  end

  if type(reactor.setActive) == "function" then
    local ok, err = pcall(reactor.setActive, false)
    if ok then return true, "Reactor OFF" end
    return false, tostring(err)
  end

  return false, "No scram/off method"
end

local function getFilledPercent(obj, percentMethods, amountMethods, capacityMethods)
  local percent = callIfExists(obj, percentMethods)
  if type(percent) == "number" then
    if percent > 1 then return percent / 100 end
    return percent
  end

  local amount = callIfExists(obj, amountMethods)
  local capacity = callIfExists(obj, capacityMethods)

  if type(amount) == "number" and type(capacity) == "number" and capacity > 0 then
    return amount / capacity
  end

  return nil
end

local function readSafety()
  local tempK = callIfExists(reactor, {"getTemperature"}) or 0
  local tempC = toC(tempK)

  local damage = callIfExists(reactor, {"getDamagePercent"}) or 0
  if damage > 1 then damage = damage / 100 end

  local coolant = getFilledPercent(
    reactor,
    {"getCoolantFilledPercentage", "getCoolantFillPercentage"},
    {"getCoolant", "getCoolantAmount"},
    {"getCoolantCapacity"}
  )

  local waste = getFilledPercent(
    reactor,
    {"getWasteFilledPercentage", "getWasteFillPercentage"},
    {"getWaste", "getWasteAmount"},
    {"getWasteCapacity"}
  )

  return {
    active = getReactorActive(),
    on = getReactorActive(),
    lockout = lockout,
    lockoutReason = lockoutReason,
    tempC = tempC,
    damage = damage,
    coolant = coolant,
    waste = waste,
    burnRate = getBurnRate(),
    maxBurnRate = getMaxBurnRate()
  }
end

local function checkUnsafe(s)
  if s.damage and s.damage > config.maxDamage then
    return true, "Damage detected"
  end

  if s.tempC and s.tempC > config.maxTempC then
    return true, "Temperature too high"
  end

  if s.coolant and s.coolant < config.minCoolant then
    return true, "Coolant too low"
  end

  if s.waste and s.waste > config.maxWaste then
    return true, "Waste too high"
  end

  return false, ""
end

local function sendStatus(kind, status)
  net.broadcast({
    type = kind or "heartbeat",
    auth = TOKEN,
    name = config.name,
    group = config.group,
    machine = config.machine,
    nodeType = "reactor",
    status = status or readSafety()
  })
end

local function ack(id, commandId, ok, message)
  if not commandId then return end

  net.send(id, {
    type = "ack",
    auth = TOKEN,
    commandId = commandId,
    ok = ok,
    message = message
  })
end

local function printStatus(s)
  term.clear()
  term.setCursorPos(1, 1)

  print("Reactor: " .. config.name)
  print("Machine: " .. config.machine)
  print("State: " .. (s.active and "ON" or "OFF"))
  print("Lockout: " .. tostring(lockout))
  if lockout then print("Reason: " .. lockoutReason) end
  print("Temp: " .. math.floor(s.tempC or 0) .. " C")
  print("Damage: " .. math.floor((s.damage or 0) * 100) .. "%")
  if s.coolant then print("Coolant: " .. math.floor(s.coolant * 100) .. "%") end
  if s.waste then print("Waste: " .. math.floor(s.waste * 100) .. "%") end
  if s.burnRate then print("Burn: " .. tostring(s.burnRate) .. "/" .. tostring(s.maxBurnRate or "?")) end
end

local function handleCommand(id, msg)
  if type(msg) ~= "table" then return end
  if msg.auth ~= TOKEN then return end
  if msg.type ~= "command" then return end

  if msg.action == "reset" then
    lockout = false
    lockoutReason = ""
    ack(id, msg.commandId, true, "Manual reset complete")
    sendStatus("node_status", readSafety())

  elseif msg.action == "status" then
    ack(id, msg.commandId, true, "Status sent")
    sendStatus("node_status", readSafety())

  elseif msg.action == "burn" then
    local rate = tonumber(msg.value)

    if not rate then
      ack(id, msg.commandId, false, "Invalid burn rate")
      return
    end

    local ok, result = setBurnRate(rate)
    ack(id, msg.commandId, ok, result)
    sendStatus("node_status", readSafety())

  elseif msg.action == "redstone" then
    local ok, result

    if msg.value == true then
      ok, result = activateReactor()
    else
      ok, result = scramReactor()
    end

    ack(id, msg.commandId, ok, result)
    sendStatus("node_status", readSafety())

  elseif msg.action == "update" then
    ack(id, msg.commandId, true, "Updating reactor node")
    local ok, result = net.updateFromManifest("reactor")
    if not ok then
      print(result)
      return
    end
    os.reboot()

  else
    ack(id, msg.commandId, false, "Unsupported action: " .. tostring(msg.action))
  end
end

local function networkLoop()
  while true do
    local id, msg = net.receive()
    handleCommand(id, msg)
  end
end

local function reactorLoop()
  while true do
    local s = readSafety()
    local unsafe, reason = checkUnsafe(s)

    if unsafe then
      scramReactor()
      lockout = true
      lockoutReason = reason
      s = readSafety()
      sendStatus("node_status", s)
    end

    printStatus(s)
    lastHeartbeatStatus = s
    sleep(1)
  end
end

local function heartbeatLoop()
  while true do
    sendStatus("heartbeat", lastHeartbeatStatus or readSafety())
    sleep(10)
  end
end

sendStatus("announce", readSafety())

parallel.waitForAny(
  networkLoop,
  reactorLoop,
  heartbeatLoop
)
