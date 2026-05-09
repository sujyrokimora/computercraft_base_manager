local net = require("common")
local config = require("matrix_config")
local manifest = require("manifest")
local TOKEN = manifest.token

net.openModem()

local matrix = peripheral.find(config.matrixPeripheralType or "inductionPort")
  or peripheral.find("inductionMatrix")
  or peripheral.find("inductionMatrixPort")

if not matrix then
  error("No induction matrix peripheral found")
end

local batteryState = "unknown"
local lastEvent = "none"
local lastStatus = nil

local function callIfExists(obj, names)
  for _, name in ipairs(names) do
    if obj and type(obj[name]) == "function" then
      local ok, value = pcall(obj[name])
      if ok then return value end
    end
  end
  return nil
end

local function getBatteryPercent()
  local percent = callIfExists(matrix, {
    "getEnergyFilledPercentage",
    "getEnergyFillPercentage",
    "getFilledPercentage"
  })

  if type(percent) == "number" then
    if percent > 1 then return percent / 100 end
    return percent
  end

  local amount = callIfExists(matrix, {"getEnergy", "getEnergyStored"})
  local capacity = callIfExists(matrix, {"getMaxEnergy", "getEnergyCapacity", "getMaxEnergyStored"})

  if type(amount) == "number" and type(capacity) == "number" and capacity > 0 then
    return amount / capacity
  end

  return nil
end

local function readStatus(event)
  local pct = getBatteryPercent()

  return {
    on = true,
    battery = pct,
    batteryState = batteryState,
    event = event or "none",
    assignedReactors = config.assignedReactors
  }
end

local function broadcastStatus(kind, event)
  local status = readStatus(event)
  lastStatus = status

  net.broadcast({
    type = kind or "heartbeat",
    auth = TOKEN,
    name = config.name,
    group = config.group,
    machine = config.machine,
    nodeType = "matrix",
    status = status
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

  print("Matrix: " .. config.name)
  if s.battery then
    print("Battery: " .. math.floor(s.battery * 100) .. "%")
  else
    print("Battery: unknown")
  end
  print("State: " .. batteryState)
  print("Last event: " .. lastEvent)

  if type(config.assignedReactors) == "table" then
    print("Reactors: " .. table.concat(config.assignedReactors, ", "))
  else
    print("Reactors: all")
  end
end

local function handleBattery()
  local pct = getBatteryPercent()
  local event = nil

  if not pct then return readStatus("none") end

  if pct <= config.batteryStartAt then
    if batteryState ~= "low" then
      batteryState = "low"
      event = "battery_low"
    end

  elseif pct >= config.batteryStopAt then
    if batteryState ~= "high" then
      batteryState = "high"
      event = "battery_high"
    end

  else
    batteryState = "middle"
  end

  if event then
    lastEvent = event
    broadcastStatus("node_status", event)
  end

  return readStatus(event or "none")
end

local function handleCommand(id, msg)
  if type(msg) ~= "table" then return end
  if msg.auth ~= TOKEN then return end
  if msg.type ~= "command" then return end

  if msg.action == "status" then
    ack(id, msg.commandId, true, "Status sent")
    broadcastStatus("node_status", "none")

  elseif msg.action == "update" then
    ack(id, msg.commandId, true, "Updating matrix node")
    local ok, result = net.updateFromManifest("matrix")
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

local function matrixLoop()
  while true do
    local s = handleBattery()
    lastStatus = s
    printStatus(s)
    sleep(1)
  end
end

local function heartbeatLoop()
  while true do
    broadcastStatus("heartbeat", "none")
    sleep(10)
  end
end

broadcastStatus("announce", "none")

parallel.waitForAny(
  networkLoop,
  matrixLoop,
  heartbeatLoop
)
