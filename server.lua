local net = require("common")
local manifest = require("manifest")
local TOKEN = manifest.token

net.openModem()

local nodes = {}
local pendingAcks = {}
local commandQueue = {}
local nextCommandId = 0
local STALE_AFTER = 30

local function isAuthed(msg)
  return type(msg) == "table" and msg.auth == TOKEN
end

local function shallowStatus(msg)
  if type(msg.status) == "table" then return msg.status end
  return {}
end

local function isNodeOnline(node)
  return (os.clock() - (node.lastSeen or 0)) <= STALE_AFTER
end

local function decorateNode(node)
  local copy = {}

  for k, v in pairs(node) do
    copy[k] = v
  end

  copy.online = isNodeOnline(node)

  if not copy.online then
    copy.status = copy.status or {}
    copy.status.offline = true
  end

  return copy
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

  print("Registered: " .. nodes[id].name .. " [" .. nodes[id].group .. "/" .. nodes[id].machine .. "/" .. nodes[id].nodeType .. "]")
end

local function updateNode(id, msg)
  if not nodes[id] then
    registerNode(id, msg)
    return
  end

  nodes[id].lastSeen = os.clock()
  nodes[id].name = msg.name or nodes[id].name
  nodes[id].group = msg.group or nodes[id].group
  nodes[id].machine = msg.machine or nodes[id].machine
  nodes[id].nodeType = msg.nodeType or nodes[id].nodeType

  if msg.status then
    nodes[id].status = msg.status
  end
end

local function newCommandId()
  nextCommandId = nextCommandId + 1
  return tostring(os.getComputerID()) .. "-" .. tostring(nextCommandId) .. "-" .. tostring(math.floor(os.clock() * 1000))
end

local function sendToNode(id, action, value)
  local commandId = newCommandId()

  net.send(id, {
    type = "command",
    auth = TOKEN,
    commandId = commandId,
    action = action,
    value = value
  })

  return commandId
end

local function commandGroup(group, target, action, value)
  local sent = {}

  for id, node in pairs(nodes) do
    if node.group == group and
       (target == "all" or node.machine == target or node.name == target) then
      local commandId = sendToNode(id, action, value)

      sent[commandId] = {
        nodeId = id,
        name = node.name,
        group = node.group,
        machine = node.machine,
        action = action
      }
    end
  end

  return sent
end

local function commandReactorsForMatrix(matrixNode, action, value)
  local assigned = nil
  local s = matrixNode.status or {}

  if type(s.assignedReactors) == "table" then
    assigned = {}
    for _, name in ipairs(s.assignedReactors) do
      assigned[name] = true
    end
  end

  local sent = {}

  for id, node in pairs(nodes) do
    if node.nodeType == "reactor" or node.group == "reactor" then
      local shouldSend = false

      if not assigned then
        shouldSend = true
      elseif assigned[node.machine] or assigned[node.name] then
        shouldSend = true
      end

      if shouldSend then
        local commandId = sendToNode(id, action, value)

        sent[commandId] = {
          nodeId = id,
          name = node.name,
          group = node.group,
          machine = node.machine,
          action = action
        }
      end
    end
  end

  return sent
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
    if not group or node.group == group or node.nodeType == group then
      out[id] = decorateNode(node)
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
  elseif text == "update" then
    return "update", true
  elseif text == "burn" then
    local rate = tonumber(args[4])
    if rate then
      return "burn", rate
    end
  end

  return nil, nil
end

local function waitForAcks(sent, timeout)
  local results = {}
  local deadline = os.clock() + (timeout or 3)

  local expected = 0

  for commandId, info in pairs(sent) do
    expected = expected + 1
    results[commandId] = {
      ok = false,
      message = "No acknowledgement",
      node = info
    }
  end

  if expected == 0 then
    return results
  end

  while os.clock() < deadline do
    for commandId, ack in pairs(pendingAcks) do
      if results[commandId] then
        results[commandId] = {
          ok = ack.ok == true,
          message = ack.message or "",
          node = results[commandId].node
        }

        pendingAcks[commandId] = nil
        expected = expected - 1
      end
    end

    if expected <= 0 then
      break
    end

    sleep(0.05)
  end

  return results
end

local function summarizeAckResults(results)
  local lines = {}
  local okCount = 0
  local failCount = 0

  for _, result in pairs(results) do
    local nodeName = result.node and result.node.name or "node"

    if result.ok then
      okCount = okCount + 1
      table.insert(lines, "OK " .. nodeName .. ": " .. (result.message or "done"))
    else
      failCount = failCount + 1
      table.insert(lines, "FAILED " .. nodeName .. ": " .. (result.message or "failed"))
    end
  end

  if okCount + failCount == 0 then
    return "No matching nodes"
  end

  return table.concat(lines, "\n")
end

local function handleMatrixAutomation(matrixNode)
  local s = matrixNode.status or {}

  if s.event == "battery_low" then
    commandReactorsForMatrix(matrixNode, "redstone", true)
    print("Matrix low: requested reactor ON")

  elseif s.event == "battery_high" then
    commandReactorsForMatrix(matrixNode, "redstone", false)
    print("Matrix high: requested reactor OFF")
  end
end

local function handleUpdateCommand(clientId, args)
  local group = args[2]

  if not group or group == "server" then
    local ok, msg = net.updateFromManifest("server")
    sendReply(clientId, ok, msg .. ". Rebooting server.")
    sleep(0.5)
    os.reboot()
    return
  end

  local sent = commandGroup(group, "all", "update", true)
  local results = waitForAcks(sent, 5)
  sendReply(clientId, true, summarizeAckResults(results))
end

local function queueClientCommand(id, msg)
  table.insert(commandQueue, {
    id = id,
    msg = msg
  })
end

local function handleClientCommand(id, msg)
  local args = msg.command or {}

  if args[1] == "list" then
    sendReply(id, true, "Node list", {
      nodes = filteredNodes(args[2])
    })

  elseif args[1] == "status" then
    sendReply(id, true, "Node status", {
      nodes = filteredNodes(args[2]),
      statusOnly = true
    })

  elseif args[1] == "update" then
    handleUpdateCommand(id, args)

  elseif #args >= 3 then
    local group = args[1]
    local target = args[2]

    local action, value = parseAction(args)

    if not action then
      sendReply(id, false, "Use: <group> <target> on/off/reset/status/update/burn <rate>")
    else
      local sent = commandGroup(group, target, action, value)
      local results = waitForAcks(sent, 5)
      sendReply(id, true, summarizeAckResults(results))
    end

  else
    sendReply(id, false, "Commands: list [group], status [group], update [group/server], <group> <target> on/off/reset/status/update/burn <rate>")
  end
end

local function handleMessage(id, msg)
  if not id or type(msg) ~= "table" then return end

  if not isAuthed(msg) then
    print("Rejected unauth message from " .. tostring(id))
    return
  end

  if msg.type == "ack" then
    if msg.commandId then
      pendingAcks[msg.commandId] = msg
    end
    return
  end

  if msg.type == "announce" then
    registerNode(id, msg)

  elseif msg.type == "heartbeat" then
    updateNode(id, msg)

  elseif msg.type == "node_status" then
    updateNode(id, msg)

    if nodes[id] and nodes[id].nodeType == "matrix" then
      handleMatrixAutomation(nodes[id])
    end

  elseif msg.type == "client_command" then
    queueClientCommand(id, msg)
  end
end

local function networkLoop()
  while true do
    local id, msg = net.receive()
    handleMessage(id, msg)
  end
end

local function commandLoop()
  while true do
    if #commandQueue > 0 then
      local item = table.remove(commandQueue, 1)
      handleClientCommand(item.id, item.msg)
    else
      sleep(0.05)
    end
  end
end

local function displayHeader()

    term.clear()
    term.setCursorPos(1, 1)
    print("Central server online")
end

displayHeader()

parallel.waitForAny(
  networkLoop,
  commandLoop
)