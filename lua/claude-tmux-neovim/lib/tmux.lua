---@brief Tmux interaction module
---
--- Functions for interacting with tmux and Claude Code instances.

local M = {}
local config = require('claude-tmux-neovim.lib.config')
local util = require('claude-tmux-neovim.lib.util')
local debug = require('claude-tmux-neovim.lib.debug')

--- Find all Claude Code instances in tmux
---@param git_root string The git repository root path
---@return table[] instances Array of Claude Code instances
function M.get_claude_code_instances(git_root)
  if not git_root then
    return {}
  end

  debug.log("Starting search for Claude Code instances in git root: " .. git_root)
  
  -- Step 1: Get all tmux panes
  local list_panes_cmd = [[tmux list-panes -a -F '#{pane_id} #{session_name} #{window_name} #{window_index} #{pane_index} #{pane_current_command} #{pane_current_path}']]
  debug.log("Running command: " .. list_panes_cmd)
  
  local result = vim.fn.system(list_panes_cmd)
  if vim.v.shell_error ~= 0 or result == "" then
    debug.log("Failed to list tmux panes or no panes found", vim.log.levels.WARN)
    return {}
  end
  
  local instances = {}
  local claude_code_cmd = config.get().claude_code_cmd
  debug.log("Claude Code command to match: '" .. claude_code_cmd .. "'")
  
  -- Get current tmux session for priority sorting
  local current_session_cmd = [[tmux display-message -p '#{session_name}']]
  local current_session = vim.fn.system(current_session_cmd):gsub("%s+$", "")
  debug.log("Current tmux session: " .. current_session)
  
  -- Step 2: Process all panes
  for line in result:gmatch("[^\r\n]+") do
    debug.log("Processing pane line: " .. line)
    
    local pane_id, session, window_name, window_idx, pane_idx, command, pane_path = 
      line:match("(%%[0-9]+) ([^ ]+) ([^ ]+) ([0-9]+) ([0-9]+) ([^ ]+) (.*)")
    
    if not pane_id or not command or not pane_path then
      debug.log("Failed to parse pane information from line", vim.log.levels.WARN)
      goto continue
    end
    
    debug.log("Pane " .. pane_id .. " command: '" .. command .. "'")
    debug.log("Pane " .. pane_id .. " path: '" .. pane_path .. "'")
    
    -- Step 3: Check if this is potentially a Claude Code pane
    local is_claude = false
    
    -- Method 1: Check the command name directly (most reliable)
    if command == claude_code_cmd then
      debug.log("Found exact command match: '" .. command .. "' == '" .. claude_code_cmd .. "'")
      is_claude = true
    -- Method 2: Check if the command path ends with the claude command name
    elseif command:match("/" .. claude_code_cmd .. "$") then
      debug.log("Found path-based command match: '" .. command .. "' ends with '/" .. claude_code_cmd .. "'")
      is_claude = true
    -- Method 3: For shell wrappers - check if it's a node.js process running claude code
    elseif command == "node" then
      debug.log("Found Node.js process in pane " .. pane_id)
      
      -- Special case for Claude Code which often runs as a Node.js process
      -- First, check the window name (often contains "claude" for Claude Code)
      if window_name:lower():match("claude") then
        debug.log("Window name contains 'claude', assuming Claude Code: " .. window_name)
        is_claude = true
      else
        -- Try to get process information for the Node.js process
        local ps_cmd = string.format("ps -o command= -p $(tmux display-message -p -t %s '#{pane_pid}')", pane_id)
        debug.log("Running ps command: " .. ps_cmd)
        local ps_output = vim.fn.system(ps_cmd):gsub("%s+$", "")
        debug.log("Process command line: " .. ps_output)
        
        -- Check for Claude Code indicators in the process command line
        if ps_output:lower():match("claude") then
          debug.log("Process command line contains 'claude', assuming Claude Code")
          is_claude = true
        else
          -- If the Node.js process is in the git repo root, it's likely Claude Code
          if pane_path == git_root then
            debug.log("Node.js process is in git repo root, likely Claude Code")
            is_claude = true
          end
        end
      end
    end
    
    -- Step 4: If it's a Claude Code pane, check if it's in the correct git repo
    if is_claude then
      debug.log("Found potential Claude Code pane: " .. pane_id)
      debug.log("Checking if path '" .. pane_path .. "' is in git root '" .. git_root .. "'")
      
      -- Check if pane path is in the git repo (either exact match or subdirectory)
      if pane_path == git_root or pane_path:match("^" .. vim.fn.escape(git_root, "%-%.%*%+%?%[%]%^%$%(%)%{%}%,%/") .. "/") then
        debug.log("Found Claude Code pane in correct git repo: " .. pane_id)
        
        -- Step 5: Add it to our instances list with priority flag
        local is_current_session = (session == current_session)
        table.insert(instances, {
          pane_id = pane_id,
          session = session,
          window_name = window_name,
          window_idx = window_idx,
          pane_idx = pane_idx,
          command = command,
          is_current_session = is_current_session,
          display = string.format("%s: %s.%s (%s)", session, window_idx, pane_idx, window_name)
        })
      else
        debug.log("Pane " .. pane_id .. " is not in the git repo - skipping")
      end
    end
    
    ::continue::
  end
  
  -- Step 6: Sort instances with current session first
  table.sort(instances, function(a, b)
    if a.is_current_session and not b.is_current_session then
      return true
    elseif not a.is_current_session and b.is_current_session then
      return false
    else
      return a.pane_id < b.pane_id
    end
  end)
  
  debug.log("Found " .. #instances .. " Claude Code instances in git repo")
  
  -- If no instances found, try a more aggressive approach - look for ANY node process in the git repo
  if #instances == 0 then
    debug.log("No Claude Code instances found with standard methods, trying aggressive fallback")
    
    for line in result:gmatch("[^\r\n]+") do
      local pane_id, session, window_name, window_idx, pane_idx, command, pane_path = 
        line:match("(%%[0-9]+) ([^ ]+) ([^ ]+) ([0-9]+) ([0-9]+) ([^ ]+) (.*)")
      
      if pane_id and command and pane_path then
        -- Check if this pane is in the git repo root
        if pane_path == git_root and command == "node" then
          debug.log("AGGRESSIVE MODE: Found Node.js process in git repo root: " .. pane_id)
          
          -- Add as a Claude Code instance
          local is_current_session = (session == current_session)
          table.insert(instances, {
            pane_id = pane_id,
            session = session,
            window_name = window_name,
            window_idx = window_idx,
            pane_idx = pane_idx,
            command = command,
            is_current_session = is_current_session,
            display = string.format("%s: %s.%s (%s) [Auto-detected]", session, window_idx, pane_idx, window_name)
          })
        end
      end
    end
    
    debug.log("After aggressive fallback, found " .. #instances .. " potential Claude Code instances")
  end
  
  if #instances > 0 then
    debug.log("First instance: " .. instances[1].pane_id .. " in session " .. instances[1].session)
  end
  
  return instances
end

--- Create a new Claude Code instance in a new tmux window
---@param git_root string The git repository root path
---@return table|nil instance The new Claude Code instance or nil if failed
function M.create_claude_code_instance(git_root)
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.ERROR)
    return nil
  end
  
  -- Get current tmux session
  local current_session = vim.fn.system("tmux display-message -p '#{session_name}'")
  current_session = vim.trim(current_session)
  
  -- Create a new window for Claude Code
  local cmd = string.format("tmux new-window -d -n claude-code 'cd %s && %s'", 
    vim.fn.shellescape(git_root), config.get().claude_code_cmd)
  
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to create Claude Code instance", vim.log.levels.ERROR)
    return nil
  end
  
  -- Give it time to start
  vim.fn.system("sleep 0.5")
  
  -- Get the new window index
  local new_window_idx = vim.fn.system("tmux list-windows -t " .. vim.fn.shellescape(current_session) .. 
                                      " | grep claude-code | cut -d: -f1")
  new_window_idx = vim.trim(new_window_idx)
  
  if new_window_idx == "" then
    vim.notify("Failed to get new Claude Code window index", vim.log.levels.ERROR)
    return nil
  end
  
  -- Get the pane ID
  local pane_id = vim.fn.system("tmux list-panes -t " .. vim.fn.shellescape(current_session) .. 
                               ":" .. new_window_idx .. " -F '#{pane_id}'")
  pane_id = vim.trim(pane_id)
  
  if pane_id == "" then
    vim.notify("Failed to get new Claude Code pane ID", vim.log.levels.ERROR)
    return nil
  end
  
  -- Return the instance info
  return {
    pane_id = pane_id,
    session = current_session,
    window_name = "claude-code",
    window_idx = new_window_idx,
    pane_idx = "0",
    command = config.get().claude_code_cmd,
    display = string.format("%s: %s.0 (claude-code)", current_session, new_window_idx)
  }
end

--- Send context to Claude Code tmux pane
---@param instance table The Claude Code tmux instance
---@param context string The context XML to send
---@return boolean success Whether sending was successful
function M.send_to_claude_code(instance, context)
  if not instance or not instance.pane_id then
    vim.notify("Invalid Claude Code instance", vim.log.levels.ERROR)
    return false
  end
  
  -- Create temp file with context
  local temp_file = os.tmpname()
  local file = io.open(temp_file, "w")
  if not file then
    vim.notify("Could not create temporary file", vim.log.levels.ERROR)
    return false
  end
  
  -- Write context to file and close
  file:write(context)
  file:close()
  
  -- Load context into tmux buffer (silently)
  local load_cmd = string.format('tmux load-buffer -b claude_context %s 2>/dev/null', temp_file)
  vim.fn.system(load_cmd)
  
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to load context into tmux buffer", vim.log.levels.ERROR)
    os.remove(temp_file)
    return false
  end
  
  -- Paste buffer into target pane (silently)
  local paste_cmd = string.format('tmux paste-buffer -b claude_context -t %s 2>/dev/null', instance.pane_id)
  vim.fn.system(paste_cmd)
  
  -- Clean up temp file
  os.remove(temp_file)
  
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to paste context into Claude Code pane", vim.log.levels.ERROR)
    return false
  end
  
  -- Switch to pane if enabled
  if config.get().auto_switch_pane then
    local switch_cmd = string.format('tmux select-pane -t %s 2>/dev/null', instance.pane_id)
    vim.fn.system(switch_cmd)
    
    -- Also focus the tmux window to ensure switching works correctly
    local window_cmd = string.format('tmux select-window -t %s:%s 2>/dev/null', 
                                     instance.session, instance.window_idx)
    vim.fn.system(window_cmd)
  end
  
  return true
end

--- Reload all buffers to refresh content from disk
function M.reload_buffers()
  -- Check for file changes and reload all modified buffers
  vim.cmd("checktime")
  
  -- For all open buffers, force reload if they're regular files
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    -- Only reload if buffer is loaded and is a file
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" then
      -- Use edit command with bang to force reload from disk
      local bufname = vim.api.nvim_buf_get_name(buf)
      if bufname ~= "" then
        -- Silently reload the buffer if it's a file
        vim.cmd("silent! e! " .. vim.fn.fnameescape(bufname))
      end
    end
  end
end

--- Get or create a Claude Code instance and execute callback
---@param git_root string The git repository root path
---@param callback function Function to call with the instance
function M.with_claude_code_instance(git_root, callback)
  if not git_root then
    -- Schedule notification to avoid interrupting workflow
    vim.schedule(function()
      vim.notify("Not in a git repository", vim.log.levels.WARN)
    end)
    return
  end
  
  -- Find available instances
  local instances = M.get_claude_code_instances(git_root)
  
  -- Check for remembered instance only if we have exactly one instance
  -- This bypasses the remembered instance logic if we have multiple instances
  if #instances == 1 and config.get().remember_choice then
    local remembered_instance = config.get_remembered_instance(git_root)
    
    if remembered_instance then
      -- Verify instance still exists (silently)
      local cmd = string.format("tmux has-session -t %s 2>/dev/null && echo true || echo false", remembered_instance.pane_id)
      local exists = vim.fn.system(cmd)
      
      if vim.trim(exists) == "true" then
        -- Use existing instance
        callback(remembered_instance)
        return
      else
        -- Clear invalid remembered instance without notification
        config.clear_remembered_instance(git_root)
      end
    end
  end
  
  if #instances == 0 then
    -- Create new instance silently if none found
    local new_instance = M.create_claude_code_instance(git_root)
    if new_instance then
      if config.get().remember_choice then
        config.set_remembered_instance(git_root, new_instance)
      end
      callback(new_instance)
    end
  elseif #instances == 1 then
    -- Use the only instance without notification
    if config.get().remember_choice then
      config.set_remembered_instance(git_root, instances[1])
    end
    callback(instances[1])
  else
    -- Let user choose from multiple instances with a cleaner UI
    local choices = {}
    for i, instance in ipairs(instances) do
      -- Capture a brief preview of the pane content (first few visible lines)
      local preview_cmd = string.format("tmux capture-pane -p -t %s | grep -v '^$' | head -n 3 | tr '\n' ' ' | cut -c 1-60", instance.pane_id)
      local preview = vim.fn.system(preview_cmd)
      preview = vim.trim(preview)
      
      -- Limit preview length and add ellipsis if needed
      if #preview > 40 then
        preview = string.sub(preview, 1, 40) .. "..."
      end
      
      -- Add a brief preview to the display string
      if preview ~= "" then
        table.insert(choices, string.format("%d. %s - \"%s\"", i, instance.display, preview))
      else
        table.insert(choices, string.format("%d. %s", i, instance.display))
      end
    end
    table.insert(choices, string.format("%d. Create new Claude Code instance", #instances + 1))
    
    -- Use scheduled notification to not block the UI
    vim.ui.select(choices, {
      prompt = "Select Claude Code instance:",
      format_item = function(item) return item end,
    }, function(choice)
      -- Clear command line immediately
      vim.cmd("echo ''")
      
      if not choice then return end
      
      local idx = tonumber(choice:match("^(%d+)%."))
      if idx and idx <= #instances then
        -- Use selected instance
        if config.get().remember_choice then
          config.set_remembered_instance(git_root, instances[idx])
        end
        -- Ensure this happens in a separate tick to avoid UI issues
        vim.schedule(function()
          callback(instances[idx])
        end)
      elseif idx == #instances + 1 then
        -- Create new instance
        local new_instance = M.create_claude_code_instance(git_root)
        if new_instance and config.get().remember_choice then
          config.set_remembered_instance(git_root, new_instance)
        end
        -- Ensure this happens in a separate tick to avoid UI issues
        vim.schedule(function()
          callback(new_instance)
        end)
      end
    end)
  end
end

return M