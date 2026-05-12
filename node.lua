local net = require("common")
local config = require("node_config")
 
local TOKEN = config.password

net.openModem()

local function status()
  return {
    on = redstone.getOutput(config.redstoneSide)
  }
end

local function announce(kind)
  net.broadcast({
    type = kind or "announce",
    auth = TOKEN,
    name = config.name,
    group = config.group,
    machine = config.machine,
    nodeType = "basic",
    status = status()
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

local function handleCommand(id, msg)
  if type(msg) ~= "table" or msg.auth ~= TOKEN or msg.type ~= "command" then return end

  if msg.action == "redstone" then
    redstone.setOutput(config.redstoneSide, msg.value == true)
    ack(id, msg.commandId, true, msg.value and "Redstone ON" or "Redstone OFF")
    print("OK redstone setOutput for ",config.redstoneSide, ":", msg.value)
    announce("node_status")

  elseif msg.action == "status" then
    ack(id, msg.commandId, true, status().on and "ON" or "OFF")
    announce("node_status")

  elseif msg.action == "update" then
    ack(id, msg.commandId, true, "Updating basic node")
    local ok, result = net.updateFromManifest("node")
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

local function heartbeatLoop()
  while true do
    announce("heartbeat")
    sleep(10)
  end
end

print("Node online: " .. config.name)
announce("announce")

parallel.waitForAny(networkLoop, heartbeatLoop)
