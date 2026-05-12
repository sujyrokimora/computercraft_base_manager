local M = {}

M.PROTOCOL = "stone_net"
M.FILE_PROTOCOL = "stone_files"

function M.openModem()
  for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "modem" then
      if not rednet.isOpen(side) then
        rednet.open(side)
      end
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

function M.downloadRaw(url)
  local response = http.get(url)
  if not response then
    return nil, "HTTP request failed"
  end

  local data = response.readAll()
  response.close()

  if not data or data == "" then
    return nil, "Empty response"
  end

  return data, nil
end

function M.writeFile(path, data)
  local h = fs.open(path, "w")
  if not h then
    return false, "Could not write " .. path
  end

  h.write(data)
  h.close()
  return true
end

function M.updateFromManifest(role)
   
  local files = manifest.files or {}

  local roleFiles = {
    basic = {
      {"common.lua", files.common},
      {"node.lua", files.node},
      {"startup", files.startup_node}
    },

    node = {
      {"common.lua", files.common},
      {"node.lua", files.node},
      {"startup", files.startup_node}
    },

    server = {
      {"common.lua", files.common},
      {"server.lua", files.server},
      {"startup", files.startup_server}
    },

    remote = {
      {"common.lua", files.common},
      {"remote.lua", files.remote}
    },

    reactor = {
      {"common.lua", files.common},
      {"reactor_node.lua", files.reactor_node},
      {"startup", files.startup_reactor}
    },

    matrix = {
      {"common.lua", files.common},
      {"matrix_node.lua", files.matrix_node},
      {"startup", files.startup_matrix}
    }
  }

  local list = roleFiles[role]
  if not list then
    return false, "Unknown update role: " .. tostring(role)
  end

  for _, item in ipairs(list) do
    local outFile = item[1]
    local url = item[2]

    if not url or url == "" then
      return false, "No URL for " .. outFile
    end

    local data, err = M.downloadRaw(url)
    if not data then
      return false, "Failed downloading " .. outFile .. ": " .. tostring(err)
    end

    local ok, writeErr = M.writeFile(outFile, data)
    if not ok then
      return false, writeErr
    end
  end

  return true, "Update complete"
end

return M
