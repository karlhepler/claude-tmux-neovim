---@brief Claude instance detection utilities
---
--- Functions for detecting and verifying Claude Code instances in tmux.

local M = {}
local debug = require('claude-tmux-neovim.lib.debug')
local tmux_cmd = require('claude-tmux-neovim.lib.tmux_commands')
local constants = require('claude-tmux-neovim.lib.constants')
local config = require('claude-tmux-neovim.lib.config')

--- Detect Claude instances using process-first approach
---@param git_root string The git repository root path
---@return table[] instances Array of Claude instances found by process detection
function M.detect_claude_by_process(git_root)
  debug.log("Starting process-first Claude detection in git root: " .. git_root)
  
  local instances = {}
  local current_session = tmux_cmd.get_current_session() or ""
  
  -- Step 1: Find all Claude processes using the GUARANTEED method
  -- ps shows 'claude' as the command even though it runs via Node
  local ps_cmd = [[ps aux | awk '$11 == "claude" { print $2 }']]
  local ps_result = vim.fn.system(ps_cmd)
  
  if vim.v.shell_error ~= 0 or ps_result == "" then
    debug.log("No Claude processes found via ps")
    return instances
  end
  
  -- Step 2: For each Claude PID, find its tmux pane
  for pid in ps_result:gmatch("(%d+)") do
    debug.log("Found Claude process PID: " .. pid)
    
    -- Get parent PID (the shell that launched Claude)
    local ppid_cmd = string.format("ps -p %s -o ppid= | tr -d ' '", pid)
    local ppid = vim.trim(vim.fn.system(ppid_cmd))
    
    if ppid ~= "" then
      -- Get working directory
      local cwd_cmd = string.format("lsof -p %s 2>/dev/null | grep 'cwd' | awk '{print $NF}'", pid)
      local cwd = vim.trim(vim.fn.system(cwd_cmd))
      debug.log("Claude PID " .. pid .. " working directory: " .. cwd)
      
      -- Find tmux pane with this parent PID
      local pane_cmd = string.format(
        "tmux list-panes -a -F '%s' | awk '$2 == %s { print }'",
        constants.TMUX.PANE_FORMAT, ppid
      )
      local pane_line = vim.trim(vim.fn.system(pane_cmd))
      
      if pane_line ~= "" then
        local instance = M.parse_pane_line(pane_line)
        if instance then
          -- Add Claude-specific information
          instance.claude_pid = pid
          instance.claude_cwd = cwd
          instance.detection_method = constants.DETECTION_METHODS.PROCESS
          instance.is_current_session = (instance.session == current_session)
          
          -- Check if in target git root (either pane path or Claude's cwd)
          if cwd == git_root or instance.pane_path == git_root then
            debug.log("Claude PID " .. pid .. " is in target git root")
            
            -- Verify it has Claude prompt before including
            if tmux_cmd.has_claude_prompt(instance.pane_id) then
              debug.log("Confirmed Claude by process + prompt: " .. instance.pane_id)
              
              -- Add display info
              M.add_display_info(instance)
              
              -- Rename window if needed
              M.rename_window_if_needed(instance)
              
              table.insert(instances, instance)
            else
              debug.log("Claude process found but no prompt yet, may be starting: " .. instance.pane_id)
            end
          else
            debug.log("Claude PID " .. pid .. " is in different location: " .. cwd)
          end
        end
      else
        debug.log("Could not find tmux pane for Claude PID " .. pid)
      end
    end
  end
  
  debug.log("Process-first detection found " .. #instances .. " Claude instances")
  return instances
end

--- Detect Claude instances using standard methods
---@param git_root string The git repository root path
---@param current_session string The current tmux session name
---@return table[] instances Array of detected instances
function M.detect_standard_instances(git_root, current_session)
  debug.log("Starting standard detection for Claude instances in git root: " .. git_root)
  
  local result = tmux_cmd.list_panes(constants.TMUX.PANE_FORMAT)
  if not result.success then
    debug.log("Failed to list tmux panes", vim.log.levels.WARN)
    return {}
  end
  
  local instances = {}
  local claude_code_cmd = config.get().claude_code_cmd
  
  for _, line in ipairs(result.panes) do
    local instance = M.parse_pane_line(line)
    if instance and M.is_potential_claude_instance(instance, claude_code_cmd) then
      if M.verify_claude_instance_in_git_root(instance, git_root) then
        instance.is_current_session = (instance.session == current_session)
        table.insert(instances, instance)
      end
    end
  end
  
  return instances
end

--- Detect Claude instances using aggressive fallback methods
---@param git_root string The git repository root path
---@param current_session string The current tmux session name
---@return table[] instances Array of detected instances
function M.detect_aggressive_instances(git_root, current_session)
  debug.log("Starting aggressive fallback detection")
  
  local result = tmux_cmd.list_panes(constants.TMUX.PANE_FORMAT)
  if not result.success then
    return {}
  end
  
  local instances = {}
  
  for _, line in ipairs(result.panes) do
    local instance = M.parse_pane_line(line)
    if instance and instance.pane_path == git_root then
      if M.aggressive_claude_verification(instance) then
        instance.is_current_session = (instance.session == current_session)
        instance.detection_method = constants.DETECTION_METHODS.AUTO
        table.insert(instances, instance)
      end
    end
  end
  
  return instances
end

--- Parse a pane line into instance components
---@param line string The pane line from tmux list-panes
---@return table|nil instance Parsed instance or nil if invalid
function M.parse_pane_line(line)
  local pane_id, session, window_name, window_idx, pane_idx, command, pane_path = 
    line:match("(%%[0-9]+) ([^ ]+) ([^ ]+) ([0-9]+) ([0-9]+) ([^ ]+) (.*)")
  
  if not pane_id or not command or not pane_path then
    debug.log("Failed to parse pane information from line", vim.log.levels.WARN)
    return nil
  end
  
  return {
    pane_id = pane_id,
    session = session,
    window_name = window_name,
    window_idx = window_idx,
    pane_idx = pane_idx,
    command = command,
    pane_path = pane_path
  }
end

--- Check if instance is potentially Claude using basic criteria
---@param instance table The parsed instance
---@param claude_code_cmd string The Claude command to match
---@return boolean is_potential Whether this could be Claude
function M.is_potential_claude_instance(instance, claude_code_cmd)
  -- Method 1: Check if command is literally "claude" (most reliable!)
  -- This works because ps shows "claude" even though it runs via Node
  if instance.command == "claude" then
    debug.log("Potential Claude by exact command match: " .. instance.pane_id)
    return true
  end
  
  -- Method 2: Check command name matches claude_code_cmd
  if instance.command == claude_code_cmd then
    debug.log("Potential Claude by command name: " .. instance.pane_id)
    return true
  end
  
  -- Method 3: Check if command path ends with claude command
  if instance.command:match("/" .. claude_code_cmd .. "$") then
    debug.log("Potential Claude by command path: " .. instance.pane_id)
    return true
  end
  
  -- Method 4: For Node.js processes, verify it's actually Claude
  -- Since Claude runs as Node but ps shows "claude", this is now a fallback
  if instance.command == "node" or instance.command == "node.js" or instance.command:match("node") then
    -- Check if this is actually Claude by looking at the process
    if tmux_cmd.is_claude_process(instance.pane_id) then
      debug.log("Confirmed Node process as Claude via process check: " .. instance.pane_id)
      return true
    end
    -- Also check for Claude prompt
    if tmux_cmd.has_claude_prompt(instance.pane_id) then
      debug.log("Node process has Claude prompt, likely Claude: " .. instance.pane_id)
      return true
    end
    -- Generic Node process, not Claude
    return false
  end
  
  -- Method 5: Window name (unreliable, only as last resort)
  if instance.window_name:lower() == constants.TMUX.CLAUDE_WINDOW_NAME then
    -- Must verify it's actually Claude
    if tmux_cmd.has_claude_prompt(instance.pane_id) or tmux_cmd.is_claude_process(instance.pane_id) then
      debug.log("Window named 'claude' and verified: " .. instance.pane_id)
      return true
    end
    debug.log("Window named 'claude' but not running Claude: " .. instance.pane_id)
    return false
  end
  
  return false
end

--- Verify that an instance is actually Claude and in the correct git root
---@param instance table The instance to verify
---@param git_root string The expected git root
---@return boolean is_claude Whether this is a verified Claude instance
function M.verify_claude_instance_in_git_root(instance, git_root)
  -- Must be in exact git root
  if instance.pane_path ~= git_root then
    return false
  end
  
  return M.verify_claude_instance(instance)
end

--- Verify that an instance is actually running Claude
---@param instance table The instance to verify
---@return boolean is_claude Whether this is Claude
function M.verify_claude_instance(instance)
  debug.log("Verifying potential Claude instance: " .. instance.pane_id)
  
  -- Method 1: Check process first (most reliable)
  local process_result = tmux_cmd.get_pane_process_detailed(instance.pane_id)
  if process_result.is_claude then
    debug.log("Confirmed Claude by detailed process check: " .. instance.pane_id)
    
    -- Also check for prompt to be extra sure
    if tmux_cmd.has_claude_prompt(instance.pane_id) then
      debug.log("Confirmed Claude by process + prompt: " .. instance.pane_id)
      instance.detection_method = constants.DETECTION_METHODS.PROC
      return true
    else
      -- Process says it's Claude but no prompt yet - might be starting up
      debug.log("Claude process found but no prompt yet - may be starting: " .. instance.pane_id)
      instance.detection_method = constants.DETECTION_METHODS.PROC
      return true
    end
  end
  
  -- Method 2: Check for Claude prompt pattern
  -- This is the distinctive box with │ > pattern
  if tmux_cmd.has_claude_prompt(instance.pane_id) then
    debug.log("Confirmed Claude by prompt pattern: " .. instance.pane_id)
    instance.detection_method = constants.DETECTION_METHODS.PROMPT
    return true
  end
  
  -- Method 3: For named windows, verify it's actually Claude
  if instance.window_name:lower() == constants.TMUX.CLAUDE_WINDOW_NAME then
    -- Double-check that it's not just a renamed regular terminal
    local simple_process_result = tmux_cmd.get_pane_process(instance.pane_id)
    if simple_process_result.success then
      -- Accept if it's node (Claude runs as Node.js) or has claude/anthropic in process
      if simple_process_result.output:match("node") or simple_process_result.output:lower():match("claude") or simple_process_result.output:match("anthropic") then
        debug.log("Confirmed Claude by window name + process: " .. instance.pane_id)
        instance.detection_method = constants.DETECTION_METHODS.NAME
        return true
      end
    end
  end
  
  -- Method 4: Command-based detection (rare since Claude runs as node)
  local claude_code_cmd = config.get().claude_code_cmd
  if instance.command == claude_code_cmd then
    instance.detection_method = constants.DETECTION_METHODS.CMD
    return true
  elseif instance.command:match("/" .. claude_code_cmd .. "$") then
    instance.detection_method = constants.DETECTION_METHODS.PATH
    return true
  end
  
  debug.log("Failed to verify as Claude: " .. instance.pane_id)
  return false
end

--- Aggressive verification for fallback detection
---@param instance table The instance to verify
---@return boolean is_claude Whether this is Claude
function M.aggressive_claude_verification(instance)
  debug.log("AGGRESSIVE MODE: Checking pane: " .. instance.pane_id)
  
  -- Skip obvious non-Claude processes
  local skip_commands = {
    "nvim", "vim", "vi", "emacs", "nano",
    "bash", "zsh", "fish", "sh", "tmux",
    "git", "grep", "find", "ls", "cd",
    "python", "python3", "ruby", "perl",
    "cargo", "npm", "yarn", "pnpm",
    "make", "gcc", "clang", "ssh"
  }
  
  for _, cmd in ipairs(skip_commands) do
    if instance.command == cmd then
      debug.log("AGGRESSIVE MODE: Skipping known non-Claude command: " .. cmd)
      return false
    end
  end
  
  -- In aggressive mode, we MUST have strong evidence of Claude
  -- The prompt pattern is the most reliable indicator
  if tmux_cmd.has_claude_prompt(instance.pane_id) then
    debug.log("AGGRESSIVE MODE: Confirmed Claude by prompt")
    return true
  end
  
  -- Check process info for claude/anthropic references
  local process_result = tmux_cmd.get_pane_process(instance.pane_id)
  if process_result.success and (process_result.output:lower():match("claude") or process_result.output:match("anthropic")) then
    debug.log("AGGRESSIVE MODE: Confirmed Claude by process")
    return true
  end
  
  -- Do NOT accept generic Node.js processes without Claude evidence
  debug.log("AGGRESSIVE MODE: No Claude evidence found, rejecting")
  return false
end

--- Check if Claude instance is ready for input
---@param instance table The instance to check
---@return boolean is_ready Whether Claude is ready to accept input
---@return string|nil state Description of current state if not ready
function M.is_claude_ready(instance)
  -- Capture recent pane content
  local content_result = tmux_cmd.capture_pane(instance.pane_id, "-S -30")
  if not content_result.success then
    return false, "Failed to capture pane content"
  end
  
  local content = content_result.output
  
  -- Check for ready prompt (empty input box)
  -- The prompt can have spaces after > and before the right border
  if content:match("│ > *$") or content:match("│ > *│") then
    return true
  end
  
  -- Check for various blocking states
  if content:match("Select a workspace") or content:match("Select your project") then
    return false, "In workspace selection menu"
  elseif content:match("Choose") or content:match("Select") then
    return false, "In selection menu"
  elseif content:match("Press Enter") or content:match("Press any key") then
    return false, "Waiting for user confirmation"
  elseif content:match("Would you like to") then
    return false, "Waiting for user choice"
  elseif content:match("npm view") or content:match("Checking for updates") then
    return false, "Checking for updates"
  elseif content:match("[⢿⣯⣷⣾⣽⣻]") or content:match("Loading") or content:match("Initializing") then
    return false, "Still loading"
  elseif content:match("Error:") or content:match("Failed to") then
    return false, "Showing error message"
  elseif content:match("·.*·.*·") or content:match("Thinking") or content:match("Analyzing") then
    return false, "Generating response"
  end
  
  -- Check if prompt exists but has content
  local prompt_content = content:match("│ > (.+)│")
  if prompt_content and prompt_content:match("%S") then
    return false, "Prompt has existing content"
  end
  
  -- Check if we can find the prompt box structure
  if content:match("╭─.*╮") and content:match("╰─.*╯") then
    -- Has the box structure, likely ready unless we missed a state
    return true
  end
  
  -- Default to not ready if we can't determine state
  return false, "Cannot determine Claude state"
end

--- Add display information to an instance
---@param instance table The instance to enhance
---@return table instance The instance with display information
function M.add_display_info(instance)
  -- Get last conversation line for context
  local last_line_cmd = string.format(
    [[tmux capture-pane -p -t %s | grep -B 1 -m 1 -e '╭─\{1,\}╮' | grep -v '╭─\{1,\}╮' | grep -v '^$' | tail -n 1]],
    instance.pane_id
  )
  local last_line_result = tmux_cmd.execute(last_line_cmd, "get last conversation line")
  
  if last_line_result.success and last_line_result.output ~= "" then
    local last_line = last_line_result.output
    if #last_line > constants.LIMITS.DISPLAY_NAME_LENGTH then
      last_line = string.sub(last_line, 1, constants.LIMITS.LAST_LINE_TRUNCATE) .. "..."
    end
    instance.last_line = last_line
  end
  
  -- Determine display name
  local display_name
  if instance.last_line and instance.last_line ~= "" then
    display_name = instance.last_line
  elseif instance.window_name and instance.window_name ~= "" then
    display_name = instance.window_name
  else
    display_name = "Claude instance"
  end
  
  instance.display = string.format("%s: %s.%s (%s) %s", 
    instance.session, 
    instance.window_idx, 
    instance.pane_idx,
    display_name,
    instance.detection_method or constants.DETECTION_METHODS.OTHER
  )
  
  return instance
end

--- Rename tmux window to "claude" if needed
---@param instance table The instance to potentially rename
---@return boolean was_renamed Whether the window was renamed
function M.rename_window_if_needed(instance)
  if instance.window_name:lower() ~= constants.TMUX.CLAUDE_WINDOW_NAME then
    -- Verify this is actually Claude before renaming
    if tmux_cmd.has_claude_prompt(instance.pane_id) then
      debug.log("Renaming window from '" .. instance.window_name .. "' to 'claude' for consistency")
      local rename_result = tmux_cmd.rename_window(instance.session, instance.window_idx, constants.TMUX.CLAUDE_WINDOW_NAME)
      if rename_result.success then
        instance.window_name = constants.TMUX.CLAUDE_WINDOW_NAME
        instance.detection_method = constants.DETECTION_METHODS.RENAMED
        return true
      end
    end
  end
  return false
end

return M