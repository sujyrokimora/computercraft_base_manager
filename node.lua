local net = require("common")
local config = require("node_config")
local manifest = require("manifest")
local TOKEN = manifest.token

net.openModem()

local function announce()
  net.broadcast({
    type = "announce",
    auth = TOKEN,
    name = config.name,
    group = config.group,
    machine = config.machine
  })
end

announce()
print("Node online: " .. config.name)

local lastHeartbeat = 0

while true do
  if os.clock() - lastHeartbeat > 10 then
    lastHeartbeat = os.clock()

    net.broadcast({
      type = "heartbeat",
      auth = TOKEN,
      name = config.name,
      group = config.group,
      machine = config.machine
    })
  end

  local id, msg = net.receive(1)

  if id and type(msg) == "table" then
    if msg.auth ~= TOKEN then
      print("Rejected unauth command from " .. id)
    elseif msg.type == "command" and msg.action == "redstone" then
      redstone.setOutput(config.redstoneSide, msg.value == true)

      if msg.value then
        print("Redstone ON")
      else
        print("Redstone OFF")
      end
    end
  end
end
