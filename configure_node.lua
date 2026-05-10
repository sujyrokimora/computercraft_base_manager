local DEFAULT_BOOTSTRAP_URL =
  "https://raw.githubusercontent.com/YOURNAME/cc-system/main/bootstrap_config.lua"

local function writeFile(path, data)
  local h = fs.open(path, "w")
  if not h then error("Failed to write " .. path) end
  h.write(data)
  h.close()
end

local function downloadRaw(url)
  local response = http.get(url)
  if not response then return nil, "HTTP request failed" end

  local data = response.readAll()
  response.close()

  if not data or data == "" then return nil, "Empty response" end
  return data, nil
end

if not fs.exists("bootstrap_config.lua") then
  term.clear()
  term.setCursorPos(1,1)

  print("bootstrap_config.lua not found")
  print("")
  print("Press ENTER to use default URL")
  print("Or type a raw GitHub URL")
  print("")

  write("URL: ")
  local url = read()

  if url == "" then url = DEFAULT_BOOTSTRAP_URL end

  local data, err = downloadRaw(url)
  if not data then error("Failed to download bootstrap_config.lua: " .. tostring(err)) end

  writeFile("bootstrap_config.lua", data)
  print("bootstrap_config.lua installed")
  sleep(1)
end

local ok, boot = pcall(require, "bootstrap_config")
if not ok then error("Failed loading bootstrap_config.lua") end

local function ask(label, default)
  if default and default ~= "" then
    write(label .. " [" .. tostring(default) .. "]: ")
  else
    write(label .. ": ")
  end

  local value = read()
  if value == "" and default ~= nil then return default end
  return value
end

local function downloadFile(url, outFile)
  print("Downloading " .. outFile)

  local data, err = downloadRaw(url)
  if not data then error("Failed downloading " .. outFile .. ": " .. tostring(err)) end

  writeFile(outFile, data)
  print("Installed " .. outFile)
end

local function loadManifest()
  if not boot.manifestUrl or boot.manifestUrl == "" then
    error("bootstrap_config.lua missing manifestUrl")
  end

  print("Fetching manifest...")
  local data, err = downloadRaw(boot.manifestUrl)
  if not data then error("Could not fetch manifest: " .. tostring(err)) end

  writeFile("manifest.lua", data)

  local okManifest, manifest = pcall(dofile, "manifest.lua")
  if not okManifest then error("Manifest failed to load") end

  return manifest
end

local function splitCsv(text)
  local out = {}
  for item in string.gmatch(text or "", "([^,]+)") do
    item = item:gsub("^%s+", ""):gsub("%s+$", "")
    if item ~= "" then table.insert(out, item) end
  end
  return out
end

local function luaList(list)
  if #list == 0 then return "nil" end

  local parts = {}
  for _, item in ipairs(list) do
    table.insert(parts, '"' .. item .. '"')
  end

  return "{" .. table.concat(parts, ", ") .. "}"
end

local manifest = loadManifest()
local files = manifest.files
local defaultToken = manifest.token or "CHANGE_ME_SECRET_123"

term.clear()
term.setCursorPos(1,1)

print("Universal Auto Configurator")
print("==================================")
print("")
print("1 = basic node")
print("2 = server")
print("3 = remote")
print("4 = reactor node")
print("5 = matrix node")
print("")

local mode = ask("Select type", "1")

downloadFile(files.common, "common.lua")

if mode == "1" then
  downloadFile(files.node, "node.lua")
  downloadFile(files.startup_node, "startup")

  local name = ask("Node name", "node_" .. os.getComputerID())
  local group = ask("Group", "farm")
  local machine = ask("Machine/type", "alloy_X")
  local side = ask("Redstone side", "back")

  writeFile("node_config.lua", [[return {
  name = "]] .. name .. [[",
  group = "]] .. group .. [[",
  machine = "]] .. machine .. [[",
  redstoneSide = "]] .. side .. [["
}
]])

elseif mode == "2" then
  downloadFile(files.server, "server.lua")
  downloadFile(files.startup_server, "startup")

elseif mode == "3" then
  downloadFile(files.remote, "remote.lua")

  local serverId = ask("Server computer ID", "1")

  writeFile("remote_config.lua", [[return {
  serverId = ]] .. serverId .. [[
}
]])

elseif mode == "4" then
  downloadFile(files.reactor_node, "reactor_node.lua")
  downloadFile(files.startup_reactor, "startup")

  local name = ask("Reactor node name", "main_reactor")
  local group = ask("Group", "reactor")
  local machine = ask("Machine/name", "main")
  local maxTempC = tonumber(ask("Max temp C", "700")) or 700
  local minCoolant = tonumber(ask("Min coolant percent", "20")) or 20
  local maxWaste = tonumber(ask("Max waste percent", "80")) or 80

  writeFile("reactor_config.lua", [[return {
  name = "]] .. name .. [[",
  group = "]] .. group .. [[",
  machine = "]] .. machine .. [[",

  reactorPeripheralType = "fissionReactorLogicAdapter",

  maxTempC = ]] .. maxTempC .. [[,
  maxDamage = 0,
  minCoolant = ]] .. (minCoolant / 100) .. [[,
  maxWaste = ]] .. (maxWaste / 100) .. [[
}
]])

elseif mode == "5" then
  downloadFile(files.matrix_node, "matrix_node.lua")
  downloadFile(files.startup_matrix, "startup")

  local name = ask("Matrix node name", "main_matrix")
  local group = ask("Group", "power")
  local machine = ask("Machine", "matrix")
  local assignedText = ask("Assigned reactors comma list, blank = all", "")
  local startAt = tonumber(ask("Battery start reactor percent", "20")) or 20
  local stopAt = tonumber(ask("Battery stop reactor percent", "80")) or 80

  local assigned = splitCsv(assignedText)

  writeFile("matrix_config.lua", [[return {
  name = "]] .. name .. [[",
  group = "]] .. group .. [[",
  machine = "]] .. machine .. [[",

  matrixPeripheralType = "inductionPort",

  batteryStartAt = ]] .. (startAt / 100) .. [[,
  batteryStopAt = ]] .. (stopAt / 100) .. [[,

  assignedReactors = ]] .. luaList(assigned) .. [[
}
]])

else
  error("Invalid selection")
end

print("")
print("Setup complete")
print("Reboot now? y/n")

local reboot = read()
if reboot == "y" or reboot == "Y" then os.reboot() end
