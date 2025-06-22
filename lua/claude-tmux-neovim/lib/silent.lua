---@brief Silent operations module
---
--- Provides completely silent operation handlers for keymaps.

local M = {}
local main = require('claude-tmux-neovim')
local debug = require('claude-tmux-neovim.lib.debug')
local tmux = require('claude-tmux-neovim.lib.tmux')
local context = require('claude-tmux-neovim.lib.context')
local util = require('claude-tmux-neovim.lib.util')
local config = require('claude-tmux-neovim.lib.config')

--- Send context from normal mode silently
function M.send_normal()
  -- Use pcall to suppress any errors
  pcall(function()
    -- First check if we have any Claude instances
    local git_root = util.get_git_root()
    if not git_root then
      debug.log("Not in a git repository")
      return
    end
    
    -- Create context payload (do this first to ensure we have valid content to send)
    local context_data = context.create_context({})
    if not context_data then
      debug.log("Failed to create context data")
      return
    end
    
    -- Format context as XML
    local xml = context.format_context_xml(context_data)
    
    -- Check if we need to create a new instance with --continue flag
    local instances = tmux.get_claude_code_instances(git_root)
    if #instances == 0 then
      debug.log("No existing Claude instances found. Creating a new one with --continue flag directly")
      
      -- Create a new instance with the --continue flag
      local new_instance = tmux.create_claude_code_instance(git_root, true)
      
      if new_instance then
        debug.log("Successfully created new Claude instance with --continue flag")
        
        -- Set as remembered instance if created successfully
        if config.get().remember_choice then
          config.set_remembered_instance(git_root, new_instance)
        end
        
        -- Send to the new Claude Code instance
        tmux.send_to_claude_code(new_instance, xml)
      else
        debug.log("Failed to create new Claude instance with --continue flag")
      end
    else
      debug.log("Found existing Claude instances, using normal send_context flow")
      -- Use the normal send_context flow if instances already exist
      main.send_context({})
    end
  end)
  
  -- Clear all command line output and force redraw to prevent "Press Enter" prompt
  vim.cmd("echo ''")
  vim.cmd("redraw!")  -- Using redraw! is more aggressive than redraw
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
    -- Create a custom context with the visual selection
    local context_data = context.create_context({
      range = 1,
      line1 = start_line,
      line2 = end_line,
      selection_text = selection -- Pass the actual yanked text
    })
    
    if not context_data then
      debug.log("Failed to create context data")
      return
    end
    
    local git_root = context_data.git_root
    if not git_root then
      debug.log("Not in a git repository")
      return
    end
    
    -- Format the context as XML
    local xml = context.format_context_xml(context_data)
    debug.log("Sending context with selection: " .. (context_data.selection or ""))
    
    -- Check if we need to create a new instance with --continue flag
    local instances = tmux.get_claude_code_instances(git_root)
    if #instances == 0 then
      debug.log("No existing Claude instances found. Creating a new one with --continue flag directly")
      
      -- Create a new instance with the --continue flag
      local new_instance = tmux.create_claude_code_instance(git_root, true)
      
      if new_instance then
        debug.log("Successfully created new Claude instance with --continue flag")
        
        -- Set as remembered instance if created successfully
        if config.get().remember_choice then
          config.set_remembered_instance(git_root, new_instance)
        end
        
        -- Send to the new Claude Code instance
        tmux.send_to_claude_code(new_instance, xml)
      else
        debug.log("Failed to create new Claude instance with --continue flag")
      end
    else
      debug.log("Found existing Claude instances, using with_claude_code_instance flow")
      -- Use existing instances if they're available
      tmux.with_claude_code_instance(git_root, function(instance)
        if instance then
          tmux.send_to_claude_code(instance, xml)
        end
      end)
    end
  end)
  
  -- Clear command line, force redraw, and exit visual mode
  vim.cmd("echo ''")
  vim.cmd("redraw!")  -- Using redraw! is more aggressive than redraw
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
end

--- Create a new Claude instance and send context from normal mode silently
function M.create_new_normal()
  -- Use pcall to suppress any errors
  pcall(function()
    -- Get git root
    local git_root = util.get_git_root()
    if not git_root then
      debug.log("Not in a git repository")
      return
    end
    
    -- Create context data for normal mode
    local context_data = context.create_context({})
    if not context_data then
      debug.log("Failed to create context")
      return
    end
    
    -- Format context as XML
    local xml = context.format_context_xml(context_data)
    
    -- Create a new Claude instance with plain "claude" command (no flags)
    local new_instance = tmux.create_claude_code_instance(git_root, false)
    
    -- Send context to the new instance and switch to it
    if new_instance then
      tmux.send_to_claude_code(new_instance, xml)
    end
  end)
  
  -- Clear all command line output and force redraw to prevent "Press Enter" prompt
  vim.cmd("echo ''")
  vim.cmd("redraw!")  -- Using redraw! is more aggressive than redraw
end

--- Create a new Claude instance and send context from visual mode silently
function M.create_new_visual()
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
    -- Get git root
    local git_root = util.get_git_root()
    if not git_root then
      debug.log("Not in a git repository")
      return
    end
    
    -- Create a custom context with the visual selection
    local context_data = context.create_context({
      range = 1,
      line1 = start_line,
      line2 = end_line,
      selection_text = selection -- Pass the actual yanked text
    })
    
    if not context_data then
      debug.log("Failed to create context")
      return
    end
    
    debug.log("Sending context with selection: " .. (context_data.selection or ""))
    
    -- Format context as XML
    local xml = context.format_context_xml(context_data)
    
    -- Create a new Claude instance with plain "claude" command (no flags)
    local new_instance = tmux.create_claude_code_instance(git_root, false)
    
    -- Set as remembered instance if created successfully
    if new_instance and config.get().remember_choice then
      config.set_remembered_instance(git_root, new_instance)
    end
    
    -- Send context to the new instance and switch to it
    if new_instance then
      tmux.send_to_claude_code(new_instance, xml)
    end
  end)
  
  -- Clear command line, force redraw, and exit visual mode
  vim.cmd("echo ''")
  vim.cmd("redraw!")  -- Using redraw! is more aggressive than redraw
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
end

return M