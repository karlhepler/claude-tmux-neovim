---@brief Debug module
---
--- Provides persistent logging functionality for debugging.

local M = {}

-- Debug log file path
local debug_file = vim.fn.stdpath('cache') .. '/claude-tmux-neovim-debug.log'

--- Initialize debug log file
function M.init()
  -- Force enable debug temporarily for troubleshooting
  vim.g.claude_tmux_neovim_debug = true
  
  -- Clear the log file at initialization
  local file = io.open(debug_file, "w")
  if file then
    file:write("Claude-tmux-neovim debug log started at " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
    file:write("---------------------------------------------------\n\n")
    file:close()
    
    -- Show notification about debug log location
    vim.schedule(function()
      vim.notify("Debug log enabled at: " .. debug_file, vim.log.levels.INFO)
    end)
  end
end

--- Log a debug message to both notification and file
---@param msg string Message to log
---@param level string|nil Log level (default: INFO)
function M.log(msg, level)
  -- Only log if debug is enabled
  if vim.g.claude_tmux_neovim_debug then
    level = level or vim.log.levels.INFO
    
    -- Show notification (won't stay long)
    vim.schedule(function()
      vim.notify("[claude-tmux-neovim] " .. msg, level, {
        title = "Claude-tmux-neovim Debug",
        timeout = 5000  -- Make notifications stay longer (5 seconds)
      })
    end)
    
    -- Always write to log file (persistent)
    local file = io.open(debug_file, "a")
    if file then
      file:write(os.date("%H:%M:%S") .. " [" .. 
                (level == vim.log.levels.ERROR and "ERROR" or 
                 level == vim.log.levels.WARN and "WARN" or "INFO") .. 
                "] " .. msg .. "\n")
      file:close()
    end
  end
end

--- Open the debug log file in a split
function M.show_log()
  if vim.fn.filereadable(debug_file) == 1 then
    vim.cmd("split " .. vim.fn.fnameescape(debug_file))
    vim.cmd("setlocal autoread")
    -- Set up auto-refresh every second
    vim.cmd([[
      augroup claude_debug_log
        autocmd!
        autocmd CursorHold <buffer> checktime
      augroup END
    ]])
    vim.bo.bufhidden = "wipe"
    vim.cmd("normal! G") -- Go to end of file
    
    -- Map q to close the window
    vim.api.nvim_buf_set_keymap(0, 'n', 'q', ':q<CR>', {noremap = true, silent = true})
    
    return true
  else
    vim.notify("Debug log file does not exist yet", vim.log.levels.WARN)
    return false
  end
end

--- Clear the debug log file
function M.clear_log()
  local file = io.open(debug_file, "w")
  if file then
    file:write("Claude-tmux-neovim debug log cleared at " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
    file:write("---------------------------------------------------\n\n")
    file:close()
    vim.notify("Debug log cleared", vim.log.levels.INFO)
  end
end

return M