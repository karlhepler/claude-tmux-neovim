---@brief Silent operations module
---
--- Provides completely silent operation handlers for keymaps.

local M = {}
local main = require('claude-tmux-neovim')
local debug = require('claude-tmux-neovim.lib.debug')

--- Send context from normal mode silently
function M.send_normal()
  -- Use pcall to suppress any errors
  pcall(function()
    main.send_context({})
  end)
  
  -- Clear command line and force redraw to prevent "Press Enter" prompt
  vim.cmd("echo ''")
  vim.cmd("redraw")
end

--- Get selected text in visual mode
local function get_visual_selection()
  -- Get the start and end positions of the visual selection
  local start_line, start_col = vim.fn.line("'<"), vim.fn.col("'<")
  local end_line, end_col = vim.fn.line("'>"), vim.fn.col("'>")
  
  -- Get all lines in the selection
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  
  if #lines == 0 then
    debug.log("No lines in selection")
    return ""
  end
  
  -- If it's a single line, trim it accordingly
  if #lines == 1 then
    lines[1] = string.sub(lines[1], start_col, end_col)
  else
    -- For multiple lines, trim the first and last lines
    lines[1] = string.sub(lines[1], start_col)
    lines[#lines] = string.sub(lines[#lines], 1, end_col)
  end
  
  -- Join all lines with newlines
  local selection = table.concat(lines, '\n')
  debug.log("Visual selection text: " .. selection)
  
  return selection
end

--- Send context from visual mode silently
function M.send_visual()
  -- The most reliable way to get the visual selection text is to use registers
  local save_reg = vim.fn.getreg('"')  -- Save default register
  local save_regtype = vim.fn.getregtype('"')
  
  -- Yank the visual selection into the default register
  -- We need to execute this immediately, not schedule it
  vim.api.nvim_command('normal! gvy')
  
  -- Get the yanked text
  local selection = vim.fn.getreg('"')
  
  debug.log("Yanked selection: " .. selection)
  
  -- Get the visual range (this is backup information)
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  
  debug.log(string.format("Visual selection range: %d-%d", start_line, end_line))
  
  -- Restore default register
  vim.fn.setreg('"', save_reg, save_regtype)
  
  -- Use pcall to suppress any errors
  pcall(function()
    -- Create a custom context and send it
    local context_data = require('claude-tmux-neovim.lib.context').create_context({
      range = 1,
      line1 = start_line,
      line2 = end_line,
      selection_text = selection -- Pass the actual yanked text
    })
    
    if context_data then
      debug.log("Sending context with selection: " .. (context_data.selection or ""))
      
      -- Format and send the context
      local xml = require('claude-tmux-neovim.lib.context').format_context_xml(context_data)
      local git_root = context_data.git_root
      
      require('claude-tmux-neovim.lib.tmux').with_claude_code_instance(git_root, function(instance)
        if instance then
          require('claude-tmux-neovim.lib.tmux').send_to_claude_code(instance, xml)
        end
      end)
    end
  end)
  
  -- Clear command line, force redraw, and exit visual mode
  vim.cmd("echo ''")
  vim.cmd("redraw")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
end

return M