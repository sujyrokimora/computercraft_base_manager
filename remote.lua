local net = require("common")
local manifest = require("manifest")
local TOKEN = manifest.token

local cfg = nil

pcall(function()
  cfg = require("remote_config")
end)

net.openModem()

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
  if type(v) ~= "number" then
    return "-"
  end

  return tostring(math.floor(v * 100)) .. "%"
end

local function onOff(node)
  local s = node.status or {}

  if s.lockout then
    return "LOCK"
  end

  if s.on == true or s.active == true then
    return "ON"
  end

  if s.on == false or s.active == false then
    return "OFF"
  end

  return "-"
end

local function extra(node)
  local s = node.status or {}
  local parts = {}

  if type(s.battery) == "number" then
    table.insert(parts, "bat=" .. pct(s.battery))
  end

  if type(s.tempC) == "number" then
    table.insert(parts, "temp=" .. math.floor(s.tempC) .. "C")
  end

  if type(s.coolant) == "number" then
    table.insert(parts, "cool=" .. pct(s.coolant))
  end

  if type(s.waste) == "number" then
    table.insert(parts, "waste=" .. pct(s.waste))
  end

  if type(s.burnRate) == "number" then
    local max = s.maxBurnRate or "?"
    table.insert(parts, "burn=" .. s.burnRate .. "/" .. max)
  end

  if s.batteryState then
    table.insert(parts, "state=" .. s.batteryState)
  end

  if s.lockoutReason and s.lockoutReason ~= "" then
    table.insert(parts, "reason=" .. s.lockoutReason)
  end

  if #parts == 0 then
    return ""
  end

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
  print(string.rep("-", 40))

  local found = false

  for id, node in pairs(nodes) do
    local s = node.status or {}

    if node.nodeType == "matrix" then
      found = true

      local pctText = "-"

      if type(s.battery) == "number" then
        pctText =
          tostring(math.floor(s.battery * 100)) .. "%"
      end

      print(
        pad(node.name, 16) ..
        pad(pctText, 8) ..
        pad(s.batteryState or "-", 10)
      )
    end
  end

  if not found then
    print("No matrix nodes found")
  end
end

local function sendCommand(args)
  net.send(SERVER_ID, {
    type = "client_command",
    auth = TOKEN,
    command = args
  })

  local id, reply = net.receive(5)

  if reply and
     reply.type == "reply" and
     reply.auth == TOKEN then

    if reply.nodes then
      if args[1] == "battery" then
        printBattery(reply.nodes)
      else
        printNodes(reply.nodes)
      end
    else
      print(reply.message)
    end
  else
    print("No valid reply from server")
  end
end

term.clear()
term.setCursorPos(1,1)

print("Wireless terminal ready")
print("")
print("Commands:")
print("  list")
print("  list <group>")
print("  status")
print("  status <group>")
print("  battery")
print("  battery power")
print("  reactor main burn <rate>")
print("  <group> <target> on")
print("  <group> <target> off")
print("  <group> <target> reset")
print("  exit")
print("")

while true do
  write("> ")

  local line = read()

  if line == "exit" then
    break
  end

  local args = split(line)

  if args[1] == "battery" then
    args[1] = "status"

    if not args[2] then
      args[2] = "power"
    end
  end

  if #args > 0 then
    sendCommand(args)
  end
end