-- GitHub file manifest for the ComputerCraft network system
-- Upload this file and all listed files to your GitHub repo.
-- Then point bootstrap_config.lua manifestUrl to the raw URL for this file.

local base =
  "https://raw.githubusercontent.com/sujyrokimora/computercraft_base_manager/main/"

return {
  token = "CHANGE_ME_SECRET_123",

  files = {
    common = base .. "common.lua",

    node = base .. "node.lua",
    server = base .. "server.lua",
    remote = base .. "remote.lua",
    reactor_node = base .. "reactor_node.lua",
    matrix_node = base .. "matrix_node.lua",

    startup_node = base .. "startup_node",
    startup_server = base .. "startup_server",
    startup_reactor = base .. "startup_reactor",
    startup_matrix = base .. "startup_matrix"
  }
}
