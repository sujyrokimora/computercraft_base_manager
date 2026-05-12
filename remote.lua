local net = require("common")
 

local cfg = nil
pcall(function()
  cfg = require("remote_config")
end)

net.openModem()

local TOKEN = manifest.token
local SERVER_ID = (cfg and cfg.serverId) or 1

local function split(text)
  local t = {}

  for word in string.gmatch(text, "%S+") do
    table.insert(t, word)
  end

  return t
end

local function pad(text, len)
  text = tostring(text or "")

  if #text > len then
    return string.sub(text, 1, len - 1) .. "."
  end

  return text .. string.rep(" ", len - #text)
end

local function pct(v)
  if type(v) ~= "number" then return "-" end
  return tostring(math.floor(v * 100)) .. "%"
end

local function receiveServerReply(timeout)
  local deadline = os.clock() + timeout

  while os.clock() < deadline do
    local id, msg = net.receive(0.5)

    if id == SERVER_ID and
       type(msg) == "table" and
       msg.type == "reply" and
       msg.auth == TOKEN then
      return msg
    end
  end

  return nil
end

local function onOff(node)
  local s = node.status or {}

  if node.online == false or s.offline then return "OFFLN" end
  if s.lockout then return "LOCK" end
  if s.on == true or s.active == true then return "ON" end
  if s.on == false or s.active == false then return "OFF" end
  return "-"
end

local function extra(node)
  local s = node.status or {}
  local parts = {}

  if type(s.battery) == "number" then table.insert(parts, "bat=" .. pct(s.battery)) end
  if type(s.tempC) == "number" then table.insert(parts, "temp=" .. math.floor(s.tempC) .. "C") end
  if type(s.coolant) == "number" then table.insert(parts, "cool=" .. pct(s.coolant)) end
  if type(s.waste) == "number" then table.insert(parts, "waste=" .. pct(s.waste)) end

  if type(s.burnRate) == "number" then
    local max = s.maxBurnRate or "?"
    table.insert(parts, "burn=" .. s.burnRate .. "/" .. max)
  end

  if s.batteryState then table.insert(parts, "state=" .. s.batteryState) end

  if type(s.assignedReactors) == "table" then
    table.insert(parts, "reactors=" .. table.concat(s.assignedReactors, ","))
  end

  if s.lockoutReason and s.lockoutReason ~= "" then
    table.insert(parts, "reason=" .. s.lockoutReason)
  end

  if #parts == 0 then return "" end
  return table.concat(parts, " ")
end

local function printNodes(nodes)
  term.clear()
  term.setCursorPos(1,1)

  print(
    pad("ID", 4) ..
    pad("STATE", 6) ..
    pad("GROUP", 10) ..
    pad("NAME", 14) ..
    pad("TYPE", 10) ..
    "INFO"
  )

  print(string.rep("-", 70))

  for id, node in pairs(nodes) do
    print(
      pad(id, 4) ..
      pad(onOff(node), 6) ..
      pad(node.group, 10) ..
      pad(node.name, 14) ..
      pad(node.nodeType or "basic", 10) ..
      extra(node)
    )
  end
end

local function printBattery(nodes)
  term.clear()
  term.setCursorPos(1,1)

  print("BATTERY STATUS")
  print(string.rep("-", 48))

  local found = false

  for id, node in pairs(nodes) do
    local s = node.status or {}

    if node.nodeType == "matrix" then
      found = true

      print(
        pad(node.name, 16) ..
        pad(pct(s.battery), 8) ..
        pad(s.batteryState or "-", 10) ..
        (type(s.assignedReactors) == "table" and table.concat(s.assignedReactors, ",") or "all")
      )
    end
  end

  if not found then
    print("No matrix nodes found")
  end
end

local function printHelp(topic)
  term.clear()
  term.setCursorPos(1,1)

  if topic == "reactor" then
    print("REACTOR COMMANDS")
    print("------------------------------")
    print("reactor <name> on")
    print("reactor <name> off")
    print("reactor <name> status")
    print("reactor <name> reset")
    print("reactor <name> burn <rate>")
    print("")
    print("Examples:")
    print("reactor main on")
    print("reactor alpha burn 2.5")
    print("reactor all status")
    print("")
    print("If auto SCRAM triggers, ON and burn")
    print("are blocked until reset.")
    return
  end

  if topic == "battery" or topic == "matrix" then
    print("BATTERY / MATRIX COMMANDS")
    print("------------------------------")
    print("battery")
    print("battery power")
    print("status power")
    print("")
    print("Matrix automation:")
    print("<= start %: reactor ON request once")
    print(">= stop %: reactor OFF request once")
    return
  end

  if topic == "update" then
    print("UPDATE COMMANDS")
    print("------------------------------")
    print("update server")
    print("update reactor")
    print("update power")
    print("update farm")
    print("update all")
    print("")
    print("Nodes download latest files")
    print("from manifest.lua and reboot.")
    return
  end

  print("COMMAND HELP")
  print("------------------------------")
  print("list")
  print("list <group>")
  print("")
  print("status")
  print("status <group>")
  print("")
  print("watch")
  print("watch <group>")
  print("")
  print("battery")
  print("battery <group>")
  print("")
  print("update server")
  print("update <group>")
  print("")
  print("<group> <target> on")
  print("<group> <target> off")
  print("<group> <target> status")
  print("<group> <target> reset")
  print("<group> <target> update")
  print("")
  print("reactor <name> burn <rate>")
  print("")
  print("Examples:")
  print("farm alloy_X on")
  print("farm all off")
  print("reactor main burn 2.5")
  print("reactor main reset")
  print("status reactor")
  print("battery")
end

local function sendCommand(args, silent)
  net.send(SERVER_ID, {
    type = "client_command",
    auth = TOKEN,
    command = args
  })

  local reply = receiveServerReply(5)

  if reply then
    if reply.nodes then
      if args[1] == "battery" then
        printBattery(reply.nodes)
      else
        printNodes(reply.nodes)
      end
    else
      if not silent then
        print(reply.message)
      end
    end
  else
    if not silent then
      print("No valid reply from server")
    end
  end
end

local function watch(group)
  while true do
    local args = {"status"}
    if group then args[2] = group end

    net.send(SERVER_ID, {
      type = "client_command",
      auth = TOKEN,
      command = args
    })

    local reply = receiveServerReply(5)

    if reply and reply.nodes then
      printNodes(reply.nodes)
      print("")
      print("Watching " .. (group or "all") .. " - CTRL+T to stop")
    else
      term.clear()
      term.setCursorPos(1,1)
      print("No valid reply from server")
      print("CTRL+T to stop")
    end

    sleep(1)
  end
end

term.clear()
term.setCursorPos(1,1)

print("Wireless terminal ready")
print("Type 'help' for commands")
print("")

while true do
  write("> ")

  local line = read()

  if line == "exit" then
    break
  end

  local args = split(line)

  if args[1] == "help" then
    printHelp(args[2])

  elseif args[1] == "battery" then
    local group = args[2] or "power"
    sendCommand({"status", group})

  elseif args[1] == "watch" then
    watch(args[2])

  elseif args[1] == "update" then
    if not args[2] then
      args[2] = "server"
    end
    sendCommand(args)

  elseif #args > 0 then
    sendCommand(args)
  end
end
