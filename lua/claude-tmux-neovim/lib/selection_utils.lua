---@brief Visual selection and context utilities
---
--- Utilities for handling visual selections and creating context with selections.

local M = {}
local debug = require('claude-tmux-neovim.lib.debug')
local context = require('claude-tmux-neovim.lib.context')
local tmux = require('claude-tmux-neovim.lib.tmux')
local util = require('claude-tmux-neovim.lib.util')

--- Get visual selection text using registers (most reliable method)
---@return table selection_info { text: string, start_line: number, end_line: number }
function M.get_visual_selection_with_restore()
  -- Save current register state
  local save_reg = vim.fn.getreg('"')
  local save_regtype = vim.fn.getregtype('"')
  
  -- Yank the visual selection into the default register
  vim.api.nvim_command('normal! gvy')
  
  -- Get the yanked text and range info
  local selection_text = vim.fn.getreg('"')
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  
  debug.log("Visual selection captured: " .. selection_text)
  debug.log(string.format("Visual selection range: %d-%d", start_line, end_line))
  
  -- Restore the register state
  vim.fn.setreg('"', save_reg, save_regtype)
  
  return {
    text = selection_text,
    start_line = start_line,
    end_line = end_line
  }
end

--- Create context and send to Claude instance
---@param selection_info table|nil Selection information from get_visual_selection_with_restore()
---@param use_continue boolean Whether to use --continue flag for new instances
---@return boolean success
function M.create_context_and_send(selection_info, use_continue)
  local git_root = util.get_git_root()
  if not git_root then
    debug.log("Not in a git repository")
    return false
  end
  
  -- Create context with or without selection
  local context_opts = {}
  if selection_info then
    context_opts = {
      range = 1,
      line1 = selection_info.start_line,
      line2 = selection_info.end_line,
      selection_text = selection_info.text
    }
  end
  
  local context_data = context.create_context(context_opts)
  if not context_data then
    debug.log("Failed to create context data")
    return false
  end
  
  -- Format context as XML
  local xml = context.format_context_xml(context_data)
  debug.log("Sending context with selection: " .. (context_data.selection or ""))
  
  -- Check if we need to create a new instance
  local instances = tmux.get_claude_code_instances(git_root)
  if #instances == 0 then
    debug.log("No existing Claude instances found. Creating new instance")
    
    -- Create new instance with appropriate flags
    local args = use_continue and {"--continue"} or {}
    local new_instance = tmux.create_claude_code_instance(git_root, unpack(args))
    
    if new_instance then
      debug.log("Successfully created new Claude instance")
      tmux.send_to_claude_code(new_instance, xml)
      return true
    else
      debug.log("Failed to create new Claude instance")
      return false
    end
  else
    debug.log("Found existing Claude instances, using with_claude_code_instance flow")
    -- Use existing instances
    tmux.with_claude_code_instance(git_root, function(instance)
      if instance then
        tmux.send_to_claude_code(instance, xml)
      end
    end)
    return true
  end
end

--- Send context from normal mode silently
---@param use_continue boolean Whether to use --continue flag for new instances
function M.send_normal_context(use_continue)
  pcall(function()
    M.create_context_and_send(nil, use_continue)
  end)
  
  -- Clear command line and force redraw
  vim.cmd("echo ''")
  vim.cmd("redraw!")
end

--- Send context from visual mode silently
---@param use_continue boolean Whether to use --continue flag for new instances
function M.send_visual_context(use_continue)
  -- Get visual selection first
  local selection_info = M.get_visual_selection_with_restore()
  
  pcall(function()
    M.create_context_and_send(selection_info, use_continue)
  end)
  
  -- Clear command line, force redraw, and exit visual mode
  vim.cmd("echo ''")
  vim.cmd("redraw!")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
end

--- Create new Claude instance and send context from normal mode
function M.create_new_normal_context()
  pcall(function()
    M.create_context_and_send(nil, false) -- No --continue flag for new instances
  end)
  
  -- Clear command line and force redraw
  vim.cmd("echo ''")
  vim.cmd("redraw!")
end

--- Create new Claude instance and send context from visual mode
function M.create_new_visual_context()
  -- Get visual selection first
  local selection_info = M.get_visual_selection_with_restore()
  
  pcall(function()
    M.create_context_and_send(selection_info, false) -- No --continue flag for new instances
  end)
  
  -- Clear command line, force redraw, and exit visual mode
  vim.cmd("echo ''")
  vim.cmd("redraw!")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
end

return M