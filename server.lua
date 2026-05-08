local net = require("common")
local manifest = require("manifest")
local TOKEN = manifest.token

net.openModem()

local nodes = {}

local function isAuthed(msg)
  return type(msg) == "table" and msg.auth == TOKEN
end

local function shallowStatus(msg)
  if type(msg.status) == "table" then
    return msg.status
  end

  return {}
end

local function registerNode(id, msg)
  nodes[id] = {
    id = id,
    name = msg.name or ("node_" .. id),
    group = msg.group or "unknown",
    machine = msg.machine or "unknown",
    nodeType = msg.nodeType or "basic",
    lastSeen = os.clock(),
    status = shallowStatus(msg)
  }

  print("Registered: " ..
    nodes[id].name ..
    " [" ..
    nodes[id].group ..
    "/" ..
    nodes[id].machine ..
    "/" ..
    nodes[id].nodeType ..
    "]")
end

local function updateNode(id, msg)
  if not nodes[id] then
    registerNode(id, msg)
    return
  end

  nodes[id].lastSeen = os.clock()

  if msg.status then
    nodes[id].status = msg.status
  end
end

local function sendToNode(id, action, value)
  net.send(id, {
    type = "command",
    auth = TOKEN,
    action = action,
    value = value
  })
end

local function commandGroup(group, target, action, value)
  local count = 0

  for id, node in pairs(nodes) do
    if node.group == group and
       (target == "all" or
        node.machine == target or
        node.name == target) then

      sendToNode(id, action, value)
      count = count + 1
    end
  end

  return count
end

local function commandReactors(action, value)
  local count = 0

  for id, node in pairs(nodes) do
    if node.nodeType == "reactor" then
      sendToNode(id, action, value)
      count = count + 1
    end
  end

  return count
end

local function sendReply(id, ok, message, extra)
  local reply = {
    type = "reply",
    auth = TOKEN,
    ok = ok,
    message = message
  }

  if extra then
    for k, v in pairs(extra) do
      reply[k] = v
    end
  end

  net.send(id, reply)
end

local function filteredNodes(group)
  local out = {}

  for id, node in pairs(nodes) do
    if not group or
       node.group == group or
       node.nodeType == group then
      out[id] = node
    end
  end

  return out
end

local function parseAction(args)
  local text = args[3]

  if text == "on" then
    return "redstone", true

  elseif text == "off" then
    return "redstone", false

  elseif text == "reset" then
    return "reset", true

  elseif text == "status" then
    return "status", true

  elseif text == "burn" then
    local rate = tonumber(args[4])

    if rate then
      return "burn", rate
    end
  end

  return nil, nil
end

local function handleMatrixAutomation(matrixNode)
  local s = matrixNode.status or {}

  if s.event == "battery_low" then
    commandReactors("redstone", true)

  elseif s.event == "battery_high" then
    commandReactors("redstone", false)
  end
end

print("Central server online")

while true do
  local id, msg = net.receive(5)

  if id and type(msg) == "table" then
    if not isAuthed(msg) then
      print("Rejected unauth message")

    elseif msg.type == "announce" then
      registerNode(id, msg)

    elseif msg.type == "heartbeat" then
      updateNode(id, msg)

    elseif msg.type == "node_status" then
      updateNode(id, msg)

      if nodes[id] and nodes[id].nodeType == "matrix" then
        handleMatrixAutomation(nodes[id])
      end

    elseif msg.type == "client_command" then
      local args = msg.command or {}

      if args[1] == "list" then
        sendReply(id, true, "Node list", {
          nodes = filteredNodes(args[2])
        })

      elseif args[1] == "status" then
        sendReply(id, true, "Node status", {
          nodes = filteredNodes(args[2])
        })

      elseif #args >= 3 then
        local group = args[1]
        local target = args[2]

        local action, value = parseAction(args)

        if not action then
          sendReply(
            id,
            false,
            "Use: <group> <target> on/off/reset/status/burn <rate>"
          )
        else
          local count = commandGroup(
            group,
            target,
            action,
            value
          )

          sendReply(
            id,
            true,
            "Sent command to " .. count .. " node(s)"
          )
        end
      end
    end
  end
end