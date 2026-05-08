local net = require("common")
local config = require("matrix_config")
local manifest = require("manifest")
local TOKEN = manifest.token

net.openModem()

local matrix = peripheral.wrap("back")

if not matrix then
  error("No induction matrix peripheral found")
end

local batteryState = "unknown"
local lastHeartbeat = 0
local lastEvent = "none"

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
    event = event or "none"
  }
end

local function broadcastStatus(kind, event)
  net.broadcast({
    type = kind or "heartbeat",
    auth = TOKEN,
    name = config.name,
    group = config.group,
    machine = config.machine,
    nodeType = "matrix",
    status = readStatus(event)
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

broadcastStatus("announce", "none")

while true do
  local s = handleBattery()
  printStatus(s)

  if os.clock() - lastHeartbeat > 10 then
    lastHeartbeat = os.clock()
    broadcastStatus("heartbeat", "none")
  end

  local id, msg = net.receive(1)
  if id and type(msg) == "table" and msg.auth == TOKEN then
    if msg.type == "command" and msg.action == "status" then
      net.send(id, {
        type = "node_status",
        auth = TOKEN,
        name = config.name,
        group = config.group,
        machine = config.machine,
        nodeType = "matrix",
        status = readStatus("none")
      })
    end
  end
end
