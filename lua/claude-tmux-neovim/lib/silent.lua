---@brief Silent operations module
---
--- Provides completely silent operation handlers for keymaps.

local M = {}
local main = require('claude-tmux-neovim')

--- Send context from normal mode silently
function M.send_normal()
  -- Use pcall to suppress any errors
  pcall(function()
    main.send_context({})
  end)
  
  -- Clear command line
  vim.cmd("echo ''")
end

--- Send context from visual mode silently
function M.send_visual()
  -- Get visual selection range
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  
  if start_pos and end_pos then
    -- Use pcall to suppress any errors
    pcall(function()
      main.send_context({
        range = 1,
        line1 = start_pos[2],
        line2 = end_pos[2]
      })
    end)
  end
  
  -- Clear command line and exit visual mode
  vim.cmd("echo ''")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
end

return M