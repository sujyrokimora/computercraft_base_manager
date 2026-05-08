local M = {}

M.PROTOCOL = "stone_net"
M.FILE_PROTOCOL = "stone_files"

function M.openModem()
  for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "modem" then
      rednet.open(side)
      return side
    end
  end
  error("No modem found")
end

function M.send(id, msg, protocol)
  rednet.send(id, msg, protocol or M.PROTOCOL)
end

function M.broadcast(msg, protocol)
  rednet.broadcast(msg, protocol or M.PROTOCOL)
end

function M.receive(timeout, protocol)
  return rednet.receive(protocol or M.PROTOCOL, timeout)
end

return M
