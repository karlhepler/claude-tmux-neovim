---@brief Tmux interaction module
---
--- Functions for interacting with tmux and Claude Code instances.

local M = {}
local config = require('claude-tmux-neovim.lib.config')

--- Find all Claude Code instances in tmux
---@param git_root string The git repository root path
---@return table[] instances Array of Claude Code instances
function M.get_claude_code_instances(git_root)
  if not git_root then
    return {}
  end

  -- Find all tmux panes running Claude Code within the same git repo
  local cmd = string.format(
    [[tmux list-panes -a -F '#{pane_id} #{session_name} #{window_name} #{window_index} #{pane_index} #{pane_current_command}' | grep -i '%s' | grep -i '%s']], 
    config.get().claude_code_cmd, 
    git_root
  )
  
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 or result == "" then
    return {}
  end
  
  local instances = {}
  for line in result:gmatch("[^\r\n]+") do
    local pane_id, session, window_name, window_idx, pane_idx, command = 
      line:match("(%%[0-9]+) ([^ ]+) ([^ ]+) ([0-9]+) ([0-9]+) ([^ ]+)")
    
    if pane_id then
      table.insert(instances, {
        pane_id = pane_id,
        session = session,
        window_name = window_name,
        window_idx = window_idx,
        pane_idx = pane_idx,
        command = command,
        display = string.format("%s: %s.%s (%s)", session, window_idx, pane_idx, window_name)
      })
    end
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
  
  -- Check for remembered instance
  if config.get().remember_choice then
    local instance = config.get_remembered_instance(git_root)
    
    if instance then
      -- Verify instance still exists (silently)
      local cmd = string.format("tmux has-session -t %s 2>/dev/null && echo true || echo false", instance.pane_id)
      local exists = vim.fn.system(cmd)
      
      if vim.trim(exists) == "true" then
        -- Use existing instance
        callback(instance)
        return
      else
        -- Clear invalid remembered instance without notification
        config.clear_remembered_instance(git_root)
      end
    end
  end
  
  -- Find available instances
  local instances = M.get_claude_code_instances(git_root)
  
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
      table.insert(choices, string.format("%d. %s", i, instance.display))
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