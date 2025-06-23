---@brief Silent operations module
---
--- Provides completely silent operation handlers for keymaps.

local M = {}
local selection_utils = require('claude-tmux-neovim.lib.selection_utils')

--- Send context from normal mode silently
function M.send_normal()
  selection_utils.send_normal_context(true) -- Use --continue flag
end

--- Send context from visual mode silently
function M.send_visual()
  selection_utils.send_visual_context(true) -- Use --continue flag
end

--- Create a new Claude instance and send context from normal mode silently
function M.create_new_normal()
  selection_utils.create_new_normal_context()
end

--- Create a new Claude instance and send context from visual mode silently
function M.create_new_visual()
  selection_utils.create_new_visual_context()
end

return M