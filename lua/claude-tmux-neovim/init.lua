---@brief Claude-Tmux-Neovim - Send context from Neovim to Claude Code in tmux
---
--- A Neovim plugin for sending code context to Claude Code AI assistant 
--- in a tmux session. Uses XML format to provide structured context.
---
--- Author: Karl Hepler (karlhepler)
--- License: MIT

-- Import modules
local config = require('claude-tmux-neovim.lib.config')
local util = require('claude-tmux-neovim.lib.util')
local tmux = require('claude-tmux-neovim.lib.tmux')
local context = require('claude-tmux-neovim.lib.context')
local debug = require('claude-tmux-neovim.lib.debug')

-- Define module
local M = {}

-- Set up autocommand for buffer reloading
local function setup_buffer_reload()
  -- Create autocommand for buffer reloading when focus returns to Neovim
  vim.cmd([[
    augroup claude_tmux_buffer_reload
      autocmd!
      autocmd FocusGained * lua require('claude-tmux-neovim.lib.tmux').reload_buffers()
    augroup END
  ]])
end

--- Reset all remembered instances
function M.reset_instances()
  config.reset_instances()
  
  -- Clear command line
  vim.schedule(function()
    vim.cmd("echo ''")
  end)
end

--- Create a new Claude Code instance
function M.create_new_instance()
  -- Get git root
  local git_root = util.get_git_root()
  if not git_root then
    vim.schedule(function()
      vim.notify("Not in a git repository", vim.log.levels.WARN)
    end)
    return
  end
  
  -- Create a new instance with plain "claude" command (no flags)
  local new_instance = tmux.create_claude_code_instance(git_root, false)
  
  -- Set as remembered instance if created successfully
  if new_instance and config.get().remember_choice then
    config.set_remembered_instance(git_root, new_instance)
  end
end

--- Reset remembered instance for current git root
function M.reset_git_instance()
  local git_root = util.get_git_root()
  if git_root and config.get_remembered_instance(git_root) then
    config.clear_remembered_instance(git_root)
    -- Use scheduled notification to avoid disrupting workflow
    vim.schedule(function()
      vim.notify("Reset Claude Code instance for " .. git_root, vim.log.levels.INFO)
      -- Clear command line after notification
      vim.cmd("echo ''")
    end)
  else
    vim.schedule(function()
      vim.notify("No remembered instance for current git repository", vim.log.levels.WARN)
      -- Clear command line after notification
      vim.cmd("echo ''")
    end)
  end
end

--- Toggle debug mode
function M.toggle_debug()
  vim.g.claude_tmux_neovim_debug = not vim.g.claude_tmux_neovim_debug
  vim.notify("Claude Code debug mode: " .. (vim.g.claude_tmux_neovim_debug and "ON" or "OFF"), vim.log.levels.INFO)
  
  if vim.g.claude_tmux_neovim_debug then
    debug.init() -- Initialize debug log file
    vim.notify("Debug log file created at: " .. vim.fn.stdpath('cache') .. '/claude-tmux-neovim-debug.log', vim.log.levels.INFO)
  end
end

--- Show debug log in a split window
function M.show_debug_log()
  debug.show_log()
end

--- Clear debug log file
function M.clear_debug_log()
  debug.clear_log()
end

--- Manually reload buffers to reflect changes from Claude Code
function M.reload_buffers()
  tmux.reload_buffers()
  vim.notify("All buffers reloaded", vim.log.levels.INFO)
end

--- Main function to send context
---@param opts table|nil Command options including range information
function M.send_context(opts)
  -- Create context payload
  local context_data = context.create_context(opts)
  if not context_data then
    return
  end
  
  -- Format context as XML
  local xml = context.format_context_xml(context_data)
  
  -- Send to Claude Code instance
  tmux.with_claude_code_instance(context_data.git_root, function(instance)
    if instance then
      tmux.send_to_claude_code(instance, xml)
    end
  end)
end

--- Plugin setup function
---@param user_config table|nil User configuration options
function M.setup(user_config)
  -- Initialize configuration
  config.setup(user_config)
  
  -- Set global debug flag based on config
  vim.g.claude_tmux_neovim_debug = config.get().debug
  
  -- Initialize debug log if debug mode is enabled
  if vim.g.claude_tmux_neovim_debug then
    debug.init()
  end
  
  -- Set up buffer reloading if enabled
  if config.get().auto_reload_buffers then
    setup_buffer_reload()
  end
  
  -- Create wrapper function to silently send context
  local function silent_send_context(opts)
    -- Use pcall to suppress errors
    local ok, err = pcall(function()
      M.send_context(opts)
    end)
    
    -- Only show critical errors
    if not ok and err then
      vim.notify("Claude Code error: " .. err, vim.log.levels.ERROR)
    end
    
    -- Clear command line
    vim.cmd("echo ''")
  end
  
  -- Create user commands with {silent=true}
  vim.api.nvim_create_user_command("ClaudeCodeSend", silent_send_context, { range = true, bang = true })
  vim.api.nvim_create_user_command("ClaudeCodeNew", M.create_new_instance, { bang = true })
  vim.api.nvim_create_user_command("ClaudeCodeReset", M.reset_instances, { bang = true })
  vim.api.nvim_create_user_command("ClaudeCodeResetGit", M.reset_git_instance, { bang = true })
  vim.api.nvim_create_user_command("ClaudeCodeDebug", M.toggle_debug, { bang = true })
  vim.api.nvim_create_user_command("ClaudeCodeShowLog", M.show_debug_log, { bang = true })
  vim.api.nvim_create_user_command("ClaudeCodeClearLog", M.clear_debug_log, { bang = true })
  vim.api.nvim_create_user_command("ClaudeCodeReload", M.reload_buffers, { bang = true })
  
  -- Set up keymapping using a Lua function callback for complete silence
  if config.get().keymap and config.get().keymap ~= "" then
    -- Normal mode - use Lua function directly instead of command
    vim.api.nvim_set_keymap('n', config.get().keymap, 
      [[<cmd>lua require('claude-tmux-neovim.lib.silent').send_normal()<CR>]], 
      { noremap = true, silent = true })
    
    -- For visual mode, use a more direct approach with :xnoremap to ensure it works properly
    vim.api.nvim_set_keymap('x', config.get().keymap, 
      [[<ESC>:lua require('claude-tmux-neovim.lib.silent').send_visual()<CR>]], 
      { noremap = true, silent = true })
  end
  
  -- Set up create new instance keymap
  if config.get().keymap_new and config.get().keymap_new ~= "" then
    vim.api.nvim_set_keymap('n', config.get().keymap_new,
      [[<cmd>lua require('claude-tmux-neovim').create_new_instance()<CR>]],
      { noremap = true, silent = true })
  end
end

return M