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
  
  -- Clear command line
  vim.cmd("echo ''")
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
  -- Save current mode
  local mode = vim.api.nvim_get_mode().mode
  debug.log("Current mode: " .. mode)
  
  -- Force visual selection marks to be updated
  vim.cmd("normal! gv")
  
  -- Get visual selection range
  local start_line, end_line = vim.fn.line("'<"), vim.fn.line("'>") 
  debug.log(string.format("Visual selection: lines %d-%d", start_line, end_line))
  
  -- Get the actual selected text
  local selection = get_visual_selection()
  
  -- Exit visual mode first (to avoid issues with command)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'x', true)
  
  -- Use pcall to suppress any errors
  pcall(function()
    -- Create a custom context and send it
    local context_data = require('claude-tmux-neovim.lib.context').create_context({
      range = 1,
      line1 = start_line,
      line2 = end_line,
      selection_text = selection -- Pass the actual selected text
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
  
  -- Clear command line
  vim.cmd("echo ''")
end

return M