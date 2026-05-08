local net = require("common")
local config = require("reactor_config")
local manifest = require("manifest")
local TOKEN = manifest.token

net.openModem()

local reactor =
  peripheral.find(config.reactorPeripheralType)
  or peripheral.find("fissionReactor")

if not reactor then
  error("No reactor found")
end

local lockout = false
local lockoutReason = ""

local function callIfExists(obj, names)
  for _, name in ipairs(names) do
    if obj and type(obj[name]) == "function" then
      local ok, value = pcall(obj[name])

      if ok then
        return value
      end
    end
  end

  return nil
end

local function toC(k)
  return k - 273.15
end

local function getReactorActive()
  local v = callIfExists(reactor, {
    "getStatus",
    "getActive",
    "isActive"
  })

  return v == true
end

local function getMaxBurnRate()
  local v = callIfExists(reactor, {
    "getMaxBurnRate",
    "getMaxBurn",
    "getMaxRate"
  })

  if type(v) == "number" then
    return v
  end

  return config.maxBurnRate or 0
end

local function getBurnRate()
  local v = callIfExists(reactor, {
    "getBurnRate",
    "getBurnRateLimit",
    "getActualBurnRate"
  })

  if type(v) == "number" then
    return v
  end

  return nil
end

local function setBurnRate(rate)
  if lockout then
    return false,
      "LOCKOUT active. Reset required."
  end

  local maxBurn = getMaxBurnRate()

  if maxBurn > 0 and rate > maxBurn then
    rate = maxBurn
  end

  if rate < 0 then
    rate = 0
  end

  if type(reactor.setBurnRate) == "function" then
    local ok, err =
      pcall(reactor.setBurnRate, rate)

    if ok then
      return true, "Burn rate set"
    end

    return false, tostring(err)
  end

  if type(reactor.setBurnRateLimit) == "function" then
    local ok, err =
      pcall(reactor.setBurnRateLimit, rate)

    if ok then
      return true, "Burn rate set"
    end

    return false, tostring(err)
  end

  return false, "No burn rate method"
end

local function activateReactor()
  if lockout then
    return false,
      "Locked out: " .. lockoutReason
  end

  if getReactorActive() then
    return true, "Already active"
  end

  if type(reactor.activate) == "function" then
    local ok, err = pcall(reactor.activate)

    if ok then
      return true, "Activated"
    end

    return false, tostring(err)
  end

  if type(reactor.setActive) == "function" then
    local ok, err =
      pcall(reactor.setActive, true)

    if ok then
      return true, "Activated"
    end

    return false, tostring(err)
  end

  return false, "No activate method"
end

local function scramReactor()
  if type(reactor.scram) == "function" then
    pcall(reactor.scram)
  elseif type(reactor.setActive) == "function" then
    pcall(reactor.setActive, false)
  end
end

local function readSafety()
  local tempK =
    callIfExists(reactor, {"getTemperature"}) or 0

  local damage =
    callIfExists(reactor, {"getDamagePercent"}) or 0

  return {
    active = getReactorActive(),
    on = getReactorActive(),

    lockout = lockout,
    lockoutReason = lockoutReason,

    tempC = toC(tempK),
    damage = damage,

    burnRate = getBurnRate(),
    maxBurnRate = getMaxBurnRate()
  }
end

local function checkUnsafe(s)
  if s.damage > config.maxDamage then
    return true, "Damage detected"
  end

  if s.tempC > config.maxTempC then
    return true, "Temperature too high"
  end

  return false, ""
end

local function broadcast(kind)
  net.broadcast({
    type = kind,
    auth = TOKEN,
    name = config.name,
    group = config.group,
    machine = config.machine,
    nodeType = "reactor",
    status = readSafety()
  })
end

local function handleCommand(id, msg)
  if msg.auth ~= TOKEN then
    return
  end

  if msg.type ~= "command" then
    return
  end

  if msg.action == "reset" then
    lockout = false
    lockoutReason = ""

    print("RESET COMPLETE")

  elseif msg.action == "redstone" then
    if msg.value == true then
      local ok, reason = activateReactor()
      print(reason)
    else
      scramReactor()
      print("SCRAM")
    end

  elseif msg.action == "burn" then
    local rate = tonumber(msg.value)

    if not rate then
      print("Invalid burn rate")
      return
    end

    local ok, result = setBurnRate(rate)
    print(result)

  elseif msg.action == "status" then
    net.send(id, {
      type = "node_status",
      auth = TOKEN,
      name = config.name,
      group = config.group,
      machine = config.machine,
      nodeType = "reactor",
      status = readSafety()
    })
  end
end

broadcast("announce")

while true do
  local s = readSafety()

  local unsafe, reason =
    checkUnsafe(s)

  if unsafe then
    scramReactor()

    lockout = true
    lockoutReason = reason
  end

  term.clear()
  term.setCursorPos(1,1)

  print("Reactor: " .. config.name)
  print("State: " ..
    (s.active and "ON" or "OFF"))

  print("Burn: " ..
    tostring(s.burnRate) ..
    "/" ..
    tostring(s.maxBurnRate))

  print("Temp: " ..
    math.floor(s.tempC) ..
    "C")

  print("Lockout: " ..
    tostring(lockout))

  if lockout then
    print(lockoutReason)
  end

  broadcast("heartbeat")

  local id, msg = net.receive(1)

  if id and type(msg) == "table" then
    handleCommand(id, msg)
  end
end