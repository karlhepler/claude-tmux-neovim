---@brief Tmux command utilities
---
--- Centralized utilities for executing tmux commands with consistent error handling.

local M = {}
local debug = require('claude-tmux-neovim.lib.debug')

--- Execute a tmux command and return structured result
---@param cmd string The tmux command to execute
---@param description string Optional description for debugging
---@return table result { output: string, success: boolean, error_code: number }
function M.execute(cmd, description)
  if description then
    debug.log("Executing tmux command: " .. description .. " -> " .. cmd)
  else
    debug.log("Executing tmux command: " .. cmd)
  end
  
  local output = vim.fn.system(cmd)
  local success = vim.v.shell_error == 0
  local error_code = vim.v.shell_error
  
  local result = {
    output = vim.trim(output),
    success = success,
    error_code = error_code
  }
  
  if not success then
    debug.log("Tmux command failed with error code " .. error_code .. ": " .. output, vim.log.levels.WARN)
  end
  
  return result
end

--- Get current tmux session name
---@return string|nil session_name
function M.get_current_session()
  local result = M.execute("tmux display-message -p '#{session_name}'", "get current session")
  return result.success and result.output or nil
end

--- List all tmux panes with specified format
---@param format_string string The tmux format string
---@return table result { output: string, success: boolean, panes: table[] }
function M.list_panes(format_string)
  local cmd = string.format("tmux list-panes -a -F '%s'", format_string)
  local result = M.execute(cmd, "list all panes")
  
  -- Parse panes if successful
  local panes = {}
  if result.success and result.output ~= "" then
    for line in result.output:gmatch("[^\r\n]+") do
      table.insert(panes, line)
    end
  end
  
  result.panes = panes
  return result
end

--- Capture pane content
---@param pane_id string The pane ID
---@param args string Optional additional arguments (e.g., "-S -5")
---@return table result { output: string, success: boolean }
function M.capture_pane(pane_id, args)
  local cmd_args = args or ""
  local cmd = string.format("tmux capture-pane -p -t %s %s", pane_id, cmd_args)
  return M.execute(cmd, "capture pane " .. pane_id)
end

--- Check if pane exists
---@param pane_id string The pane ID
---@return boolean exists
function M.pane_exists(pane_id)
  local cmd = string.format("tmux has-session -t %s 2>/dev/null", pane_id)
  local result = M.execute(cmd, "check pane existence")
  return result.success
end

--- Get pane information
---@param pane_id string The pane ID
---@param format_string string The format string for pane info
---@return table result { output: string, success: boolean }
function M.get_pane_info(pane_id, format_string)
  local cmd = string.format("tmux display-message -t %s -p '%s'", pane_id, format_string)
  return M.execute(cmd, "get pane info for " .. pane_id)
end

--- Create new tmux window
---@param window_name string The window name
---@param command string The command to run in the window
---@return table result { output: string, success: boolean, window_idx: string|nil }
function M.create_window(window_name, command)
  local cmd = string.format("tmux new-window -d -n '%s' -P -F '#{window_index}' '%s'", 
    window_name, command)
  local result = M.execute(cmd, "create window '" .. window_name .. "'")
  
  if result.success then
    result.window_idx = result.output
  end
  
  return result
end

--- Rename tmux window
---@param session string The session name
---@param window_idx string The window index
---@param new_name string The new window name
---@return table result { output: string, success: boolean }
function M.rename_window(session, window_idx, new_name)
  local cmd = string.format("tmux rename-window -t %s:%s '%s'", session, window_idx, new_name)
  return M.execute(cmd, "rename window to '" .. new_name .. "'")
end

--- Select tmux window
---@param session string The session name
---@param window_idx string The window index
---@return table result { output: string, success: boolean }
function M.select_window(session, window_idx)
  local cmd = string.format("tmux select-window -t %s:%s", session, window_idx)
  return M.execute(cmd, "select window " .. window_idx)
end

--- Select tmux pane
---@param pane_id string The pane ID
---@return table result { output: string, success: boolean }
function M.select_pane(pane_id)
  local cmd = string.format("tmux select-pane -t %s", pane_id)
  return M.execute(cmd, "select pane " .. pane_id)
end

--- Load content into tmux buffer
---@param buffer_name string The buffer name
---@param file_path string The file path to load
---@return table result { output: string, success: boolean }
function M.load_buffer(buffer_name, file_path)
  local cmd = string.format("tmux load-buffer -b %s %s 2>/dev/null", buffer_name, file_path)
  return M.execute(cmd, "load buffer " .. buffer_name)
end

--- Paste tmux buffer to pane
---@param buffer_name string The buffer name
---@param pane_id string The target pane ID
---@return table result { output: string, success: boolean }
function M.paste_buffer(buffer_name, pane_id)
  local cmd = string.format("tmux paste-buffer -b %s -t %s 2>/dev/null", buffer_name, pane_id)
  return M.execute(cmd, "paste buffer to " .. pane_id)
end

--- List windows in session
---@param session string The session name
---@return table result { output: string, success: boolean }
function M.list_windows(session)
  local cmd = string.format("tmux list-windows -t %s:", session)
  return M.execute(cmd, "list windows in " .. session)
end

--- Get process information for pane
---@param pane_id string The pane ID
---@return table result { output: string, success: boolean }
function M.get_pane_process(pane_id)
  local cmd = string.format("ps -o command= -p $(tmux display-message -p -t %s '#{pane_pid}') 2>/dev/null", pane_id)
  return M.execute(cmd, "get process for pane " .. pane_id)
end

--- Get detailed process information including arguments for pane
---@param pane_id string The pane ID
---@return table result { output: string, success: boolean, is_claude: boolean }
function M.get_pane_process_detailed(pane_id)
  local constants = require('claude-tmux-neovim.lib.constants')
  
  -- Get the PID first
  local pid_cmd = string.format("tmux display-message -p -t %s '#{pane_pid}'", pane_id)
  local pid_result = M.execute(pid_cmd, "get PID for pane " .. pane_id)
  
  if not pid_result.success or pid_result.output == "" then
    return { output = "", success = false, is_claude = false }
  end
  
  local pid = pid_result.output
  
  -- GUARANTEED METHOD: Check if any child process is named "claude"
  -- This works because ps shows "claude" as the command even when run via Node
  local claude_check_cmd = string.format("pgrep -P %s claude 2>/dev/null", pid)
  local claude_result = M.execute(claude_check_cmd, "check for claude child process")
  
  if claude_result.success and claude_result.output ~= "" then
    -- Found a claude process as child of this pane
    return { 
      output = "claude process (PID: " .. claude_result.output:gsub("%s+", "") .. ")", 
      success = true, 
      is_claude = true 
    }
  end
  
  -- Fallback Method 1: Check full command line with arguments
  local cmd = string.format("ps -o args= -p %s 2>/dev/null", pid)
  local result = M.execute(cmd, "get full process args for PID " .. pid)
  
  -- Check if this is a Claude process
  local is_claude = false
  if result.success and result.output ~= "" then
    local lower_output = result.output:lower()
    is_claude = lower_output:match("claude") or lower_output:match("anthropic") ~= nil
  end
  
  -- Fallback Method 2: Check process environment
  if not is_claude then
    cmd = string.format("ps eww -p %s 2>/dev/null | grep -E '%s' | head -1", 
      pid, constants.PATTERNS.CLAUDE_ENV_PATTERNS)
    local env_result = M.execute(cmd, "check process environment for Claude")
    if env_result.success and env_result.output ~= "" then
      is_claude = true
      result.output = result.output .. " [ENV: Claude detected]"
    end
  end
  
  -- Fallback Method 3: Check if command is literally "claude"
  local comm_cmd = string.format("ps -p %s -o comm= 2>/dev/null", pid)
  local comm_result = M.execute(comm_cmd, "get process command name")
  if comm_result.success and comm_result.output == "claude" then
    is_claude = true
    result.output = "claude"
  end
  
  result.is_claude = is_claude
  return result
end

--- Check if a pane is running Claude by examining its process
---@param pane_id string The pane ID
---@return boolean is_claude
function M.is_claude_process(pane_id)
  local result = M.get_pane_process_detailed(pane_id)
  return result.is_claude
end

--- Check for Claude prompt pattern in pane
---@param pane_id string The pane ID
---@param pattern string The pattern to search for (default: Claude prompt)
---@return boolean has_pattern
function M.has_claude_prompt(pane_id, pattern)
  local constants = require('claude-tmux-neovim.lib.constants')
  pattern = pattern or constants.PATTERNS.CLAUDE_PROMPT
  
  -- Try multiple detection methods for better Unicode handling
  -- Method 1: Standard grep with Unicode pattern
  local cmd = string.format("tmux capture-pane -p -t %s -S -10 | grep -q '%s'", pane_id, pattern)
  local result = M.execute(cmd, "check Claude prompt (standard) in " .. pane_id)
  if result.success then
    return true
  end
  
  -- Method 2: Try looking for box drawing characters directly
  -- Using printf to generate the Unicode characters for comparison
  cmd = string.format("tmux capture-pane -p -t %s -S -10 | grep -qF '╭'", pane_id)
  result = M.execute(cmd, "check Claude prompt (box char) in " .. pane_id)
  if result.success then
    -- Also check for the closing character
    cmd = string.format("tmux capture-pane -p -t %s -S -10 | grep -qF '╮'", pane_id)
    result = M.execute(cmd, "check Claude prompt (closing box) in " .. pane_id)
    if result.success then
      return true
    end
  end
  
  -- Method 3: Try alternative pattern with character class
  cmd = string.format("tmux capture-pane -p -t %s -S -10 | grep -qE '%s'", 
    pane_id, constants.PATTERNS.CLAUDE_PROMPT_ALTERNATIVE)
  result = M.execute(cmd, "check Claude prompt (alternative) in " .. pane_id)
  if result.success then
    return true
  end
  
  -- Method 4: Look for the prompt with cursor pattern as fallback
  cmd = string.format("tmux capture-pane -p -t %s -S -10 | grep -qF '%s'", 
    pane_id, constants.PATTERNS.CLAUDE_PROMPT_WITH_CURSOR)
  result = M.execute(cmd, "check Claude cursor prompt in " .. pane_id)
  
  return result.success
end

return M