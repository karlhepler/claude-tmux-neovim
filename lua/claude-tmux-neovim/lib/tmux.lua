---@brief Tmux interaction module
---
--- Functions for interacting with tmux and Claude Code instances.

local M = {}
local config = require('claude-tmux-neovim.lib.config')
local util = require('claude-tmux-neovim.lib.util')
local debug = require('claude-tmux-neovim.lib.debug')

--- Rename a tmux window to "claude" if it's running Claude Code but has a different name
---@param pane_id string The tmux pane ID
---@param session string The tmux session name
---@param window_idx string The tmux window index
---@param window_name string The current window name
function M.rename_to_claude_if_needed(pane_id, session, window_idx, window_name)
  -- Only rename if the window name is not already "claude"
  if window_name:lower() ~= "claude" then
    -- First check if this is actually Claude with the prompt line check
    local content_cmd = string.format(
      "tmux capture-pane -p -t %s | grep -e '╭─\\{1,\\}╮' -e '│ >'", 
      pane_id
    )
    local content_check = vim.fn.system(content_cmd):gsub("%s+$", "")
    
    -- If it has the Claude prompt, rename the window
    if content_check and content_check ~= "" then
      debug.log("Renaming window from '" .. window_name .. "' to 'claude' for consistency")
      local rename_cmd = string.format("tmux rename-window -t %s:%s claude", session, window_idx)
      vim.fn.system(rename_cmd)
      return true
    end
  end
  return false
end

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
    
    -- Method 1: Check window name first (now the primary detection method)
    if window_name:lower() == "claude" then
      debug.log("Window name is 'claude', likely Claude Code: " .. window_name)
      is_claude = true
    -- Method 2: Check the command name directly 
    elseif command == claude_code_cmd then
      debug.log("Found exact command match: '" .. command .. "' == '" .. claude_code_cmd .. "'")
      is_claude = true
    -- Method 3: Check if the command path ends with the claude command name
    elseif command:match("/" .. claude_code_cmd .. "$") then
      debug.log("Found path-based command match: '" .. command .. "' ends with '/" .. claude_code_cmd .. "'")
      is_claude = true
    -- Method 4: For shell wrappers - check if it's a node.js process running claude code
    elseif command == "node" or command == "node.js" or command:match("node") then
      debug.log("Found Node.js process in pane " .. pane_id)
      
      -- Try to get process information for the Node.js process
      local ps_cmd = string.format("ps -o command= -p $(tmux display-message -p -t %s '#{pane_pid}')", pane_id)
      debug.log("Running ps command: " .. ps_cmd)
      local ps_output = vim.fn.system(ps_cmd):gsub("%s+$", "")
      debug.log("Process command line: " .. ps_output)
      
      -- Check for Claude Code indicators in the process command line
      if ps_output:lower():match("claude") then
        debug.log("Process command line contains 'claude', assuming Claude Code")
        is_claude = true
      end
    end
    
    -- Method 5: Always verify with content check (prompt line) regardless of other methods
    -- Even if we already think it's Claude, let's verify with content
    local content_cmd = string.format(
      "tmux capture-pane -p -t %s | grep -e '╭─\\{1,\\}╮' -e '│ >'", 
      pane_id
    )
    local content_check = vim.fn.system(content_cmd):gsub("%s+$", "")
    if content_check and content_check ~= "" then
      debug.log("Pane has distinctive Claude prompt line: " .. pane_id)
      is_claude = true
    end
    
    -- Step 4: If it's a Claude Code pane, check if it's EXACTLY in the git root
    if is_claude then
      debug.log("Found potential Claude Code pane: " .. pane_id)
      debug.log("Checking if path '" .. pane_path .. "' is exactly the git root '" .. git_root .. "'")
      
      -- Only include panes that are exactly in the git root directory
      debug.log("Comparing pane_path: '" .. pane_path .. "' with git_root: '" .. git_root .. "'")
      debug.log("String comparison result: " .. tostring(pane_path == git_root))
      
      -- Very strict exact match check for both git root AND Claude Code
      if pane_path == git_root then
        debug.log("Found pane in exact git root: " .. pane_id)
        
        -- Double-check that this is actually Claude Code
        local is_actually_claude = false
        
        -- Method 1: Check window name first (highest priority)
        if window_name:lower() == "claude" then
          is_actually_claude = true
          debug.log("Confirmed Claude Code by exact window name 'claude': " .. pane_id)
        end
        
        -- Method 2: Verify by checking for the distinctive Claude prompt line
        -- Active Claude sessions have a horizontal line with a prompt indicator below it
        local content_check_cmd = string.format(
          "tmux capture-pane -p -t %s | grep -e '╭─\\{1,\\}╮' -e '│ >'", 
          pane_id
        )
        local content_check = vim.fn.system(content_check_cmd):gsub("%s+$", "")
        if content_check and content_check ~= "" then
          is_actually_claude = true
          debug.log("Confirmed Claude Code by distinctive prompt line: " .. pane_id)
        end
        
        -- More thorough process checking with ps
        -- First, check full command line (including arguments) for claude markers
        local process_cmd = string.format(
          "ps -o command= -p $(tmux display-message -p -t %s '#{pane_pid}')", 
          pane_id
        )
        local process_check = vim.fn.system(process_cmd):gsub("%s+$", "")
        debug.log("Process command line: " .. process_check)
        
        if process_check:lower():match("claude") or 
           process_check:match("anthropic") then
          is_actually_claude = true
          debug.log("Confirmed Claude Code by process command: " .. pane_id)
        end
        
        -- Also check process environment for Claude-specific variables (more reliable)
        if not is_actually_claude then
          local env_cmd = string.format(
            "ps -o command= -e -p $(tmux display-message -p -t %s '#{pane_pid}') 2>/dev/null | grep -e 'CLAUDE\\|ANTHROPIC'", 
            pane_id
          )
          local env_check = vim.fn.system(env_cmd):gsub("%s+$", "")
          if env_check and env_check ~= "" then
            is_actually_claude = true
            debug.log("Confirmed Claude Code by process environment: " .. pane_id)
          end
        end
        
        -- Check parent processes for Claude indicators
        if not is_actually_claude then
          -- Get process tree for this pane
          local pstree_cmd = string.format(
            "pstree -p $(tmux display-message -p -t %s '#{pane_pid}') 2>/dev/null | grep -e claude -e anthropic", 
            pane_id
          )
          local pstree_check = vim.fn.system(pstree_cmd):gsub("%s+$", "")
          if pstree_check and pstree_check ~= "" then
            is_actually_claude = true
            debug.log("Confirmed Claude Code by process tree: " .. pane_id)
          end
        end
        
        -- Only proceed if this is actually Claude
        if is_actually_claude then
          debug.log("Confirmed Claude Code pane in exact git root: " .. pane_id)
          
          -- Rename the window to "claude" if needed for consistency
          local was_renamed = M.rename_to_claude_if_needed(pane_id, session, window_idx, window_name)
          if was_renamed then
            window_name = "claude" -- Update the window name if it was renamed
          end
        
          -- Step 5: Add it to our instances list with priority flag
          local is_current_session = (session == current_session)
          
          -- Add detection method to help identify how we found this instance
          local detection_method = ""
          
          -- First, identify initial detection method
          if was_renamed then
            detection_method = "[renamed]"
          elseif command == claude_code_cmd then
            detection_method = "[cmd]"
          elseif command:match("/" .. claude_code_cmd .. "$") then
            detection_method = "[path]"
          elseif command == "node" or command == "node.js" or command:match("node") then
            detection_method = "[node]"
          else
            detection_method = "[other]"
          end
          
          -- Then check which verification passed to prioritize that
          if is_actually_claude then
            -- If we verified with the Claude prompt line, show that (most reliable)
            local content_cmd = string.format(
              "tmux capture-pane -p -t %s | grep -e '╭─\\{1,\\}╮' -e '│ >'", 
              pane_id
            )
            local content_check = vim.fn.system(content_cmd):gsub("%s+$", "")
            if content_check and content_check ~= "" then
              detection_method = "[prompt]"
            end
            
            -- Or if we verified with process details
            local process_cmd = string.format(
              "ps -o command= -p $(tmux display-message -p -t %s '#{pane_pid}') | grep -e claude", 
              pane_id
            )
            local process_check = vim.fn.system(process_cmd):gsub("%s+$", "")
            if process_check and process_check ~= "" then
              detection_method = "[proc]"
            end
          end
          
          -- Get the last line of conversation before the prompt
          local last_line_cmd = string.format(
            [[tmux capture-pane -p -t %s | grep -B 1 -m 1 -e '╭─\{1,\}╮' | grep -v '╭─\{1,\}╮' | grep -v '^$' | tail -n 1]],
            pane_id
          )
          local last_line = vim.fn.system(last_line_cmd):gsub("%s+$", "")
          if last_line and last_line ~= "" then
            debug.log("Found last conversation line: " .. last_line)
          end
          
          -- Determine display name
          local display_name
          if last_line and last_line ~= "" then
            -- Truncate if needed
            if #last_line > 40 then
              display_name = string.sub(last_line, 1, 37) .. "..."
            else
              display_name = last_line
            end
          elseif window_name and window_name ~= "" then
            display_name = window_name
          else
            display_name = "Claude instance"
          end
          
          table.insert(instances, {
            pane_id = pane_id,
            session = session,
            window_name = window_name,
            window_idx = window_idx,
            pane_idx = pane_idx,
            command = command,
            is_current_session = is_current_session,
            detection_method = detection_method,
            last_line = last_line,
            display = string.format("%s: %s.%s (%s) %s", session, window_idx, pane_idx, display_name, detection_method)
          })
        else
          debug.log("Pane " .. pane_id .. " is in git root but not running Claude - skipping")
        end
      else
        debug.log("Pane " .. pane_id .. " is not in the exact git root - skipping")
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
  
  -- If no instances found, try a more aggressive approach - look for ANY process in the git repo with Claude markers
  if #instances == 0 then
    debug.log("No Claude Code instances found with standard methods, trying aggressive fallback")
    
    for line in result:gmatch("[^\r\n]+") do
      local pane_id, session, window_name, window_idx, pane_idx, command, pane_path = 
        line:match("(%%[0-9]+) ([^ ]+) ([^ ]+) ([0-9]+) ([0-9]+) ([^ ]+) (.*)")
      
      if pane_id and command and pane_path then
        -- Check if this pane is EXACTLY in the git repo root (not a subdirectory)
        if pane_path == git_root then
          debug.log("AGGRESSIVE MODE: Checking pane in git root: " .. pane_id .. " with command: " .. command)
          
          -- Double-check that this is actually Claude Code using multiple verification methods
          local is_actually_claude = false
          
          -- Method 1: Check window name first (prioritized method)
          if window_name:lower() == "claude" then
            is_actually_claude = true
            debug.log("AGGRESSIVE MODE: Window name is exactly 'claude': " .. window_name)
          end
          
          -- Method 2: Check for the distinctive Claude prompt line (always check this regardless)
          local content_cmd = string.format(
            "tmux capture-pane -p -t %s | grep -e '╭─\\{1,\\}╮' -e '│ >'", 
            pane_id
          )
          local content_check = vim.fn.system(content_cmd):gsub("%s+$", "")
          if content_check and content_check ~= "" then
            is_actually_claude = true
            debug.log("AGGRESSIVE MODE: Confirmed Claude Code by distinctive prompt line: " .. pane_id)
          end
          
          -- Method 3: Enhanced process detection (as fallback)
          if not is_actually_claude then
            -- Check full command line (including arguments) for claude markers
            local process_cmd = string.format(
              "ps -o command= -p $(tmux display-message -p -t %s '#{pane_pid}')", 
              pane_id
            )
            local process_check = vim.fn.system(process_cmd):gsub("%s+$", "")
            debug.log("AGGRESSIVE MODE: Process command line: " .. process_check)
            
            if process_check:lower():match("claude") or 
               process_check:match("anthropic") then
              is_actually_claude = true
              debug.log("AGGRESSIVE MODE: Confirmed Claude Code by process command: " .. pane_id)
            end
          end
          
          -- Method 4: Check process environment for Claude-specific variables
          if not is_actually_claude then
            local env_cmd = string.format(
              "ps -o command= -e -p $(tmux display-message -p -t %s '#{pane_pid}') 2>/dev/null | grep -e 'CLAUDE\\|ANTHROPIC'", 
              pane_id
            )
            local env_check = vim.fn.system(env_cmd):gsub("%s+$", "")
            if env_check and env_check ~= "" then
              is_actually_claude = true
              debug.log("AGGRESSIVE MODE: Confirmed Claude Code by process environment: " .. pane_id)
            end
          end
          
          -- Method 5: Check parent processes for Claude indicators
          if not is_actually_claude then
            -- Get process tree for this pane
            local pstree_cmd = string.format(
              "pstree -p $(tmux display-message -p -t %s '#{pane_pid}') 2>/dev/null | grep -e claude -e anthropic", 
              pane_id
            )
            local pstree_check = vim.fn.system(pstree_cmd):gsub("%s+$", "")
            if pstree_check and pstree_check ~= "" then
              is_actually_claude = true
              debug.log("AGGRESSIVE MODE: Confirmed Claude Code by process tree: " .. pane_id)
            end
          end
          
          -- Only add if we're confident it's actually Claude and not Neovim or another editor
          if is_actually_claude and command ~= "nvim" and command ~= "vim" and command ~= "vi" then
            -- Rename the window to "claude" if needed for consistency
            local was_renamed = M.rename_to_claude_if_needed(pane_id, session, window_idx, window_name)
            if was_renamed then
              window_name = "claude" -- Update the window name if it was renamed
            end
            
            -- Add as a Claude Code instance
            local is_current_session = (session == current_session)
            
            -- Determine detection method based on which verification passed
            local detection_method = "[auto]"
            
            -- Check if the window was renamed
            if was_renamed then
              detection_method = "[renamed]"
            -- Check if window name was the verification method
            elseif window_name:lower():match("claude") then
              detection_method = "[name]"
            end
            
            -- Store the last line of conversation before the prompt for display purposes
            local last_line_cmd = string.format(
              [[tmux capture-pane -p -t %s | grep -B 1 -m 1 -e '╭─\{1,\}╮' | grep -v '╭─\{1,\}╮' | grep -v '^$' | tail -n 1]],
              pane_id
            )
            local last_line = vim.fn.system(last_line_cmd):gsub("%s+$", "")
            if last_line and last_line ~= "" then
              -- Keep only first 40 chars for display
              if #last_line > 40 then
                last_line = string.sub(last_line, 1, 37) .. "..."
              end
              debug.log("AGGRESSIVE MODE: Found last conversation line: " .. last_line)
            end
            
            -- Check if we found it through process detection methods
            local process_cmd = string.format(
              "ps -o command= -p $(tmux display-message -p -t %s '#{pane_pid}')", 
              pane_id
            )
            local process_check = vim.fn.system(process_cmd):gsub("%s+$", "")
            
            if process_check:lower():match("claude") or 
               process_check:match("anthropic") then
              detection_method = "[proc]"
            end
            
            -- Prompt line detection gets priority since it's most reliable
            local content_cmd = string.format(
              "tmux capture-pane -p -t %s | grep -e '╭─\\{1,\\}╮' -e '│ >'", 
              pane_id
            )
            local content_check = vim.fn.system(content_cmd):gsub("%s+$", "")
            if content_check and content_check ~= "" then
              detection_method = "[prompt]"
            end
            
            -- Determine display name
            local display_name
            if last_line and last_line ~= "" then
              display_name = last_line
            elseif window_name and window_name ~= "" then
              display_name = window_name
            else
              display_name = "Claude instance"
            end
            
            table.insert(instances, {
              pane_id = pane_id,
              session = session,
              window_name = window_name,
              window_idx = window_idx,
              pane_idx = pane_idx,
              command = command,
              is_current_session = is_current_session,
              detection_method = detection_method,
              last_line = last_line,
              display = string.format("%s: %s.%s (%s) %s", session, window_idx, pane_idx, display_name, detection_method)
            })
            debug.log("AGGRESSIVE MODE: Added Claude instance: " .. pane_id)
          else
            debug.log("AGGRESSIVE MODE: Pane " .. pane_id .. " is in git root but not running Claude - skipping")
          end
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
---@param ... string Additional arguments to pass to the Claude CLI
---@return table|nil instance The new Claude Code instance or nil if failed
function M.create_claude_code_instance(git_root, ...)
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.ERROR)
    return nil
  end
  
  -- Get current tmux session
  local current_session = vim.fn.system("tmux display-message -p '#{session_name}'")
  current_session = vim.trim(current_session)
  
  -- Build the claude command with any additional arguments
  local claude_args = {...}
  local base_cmd = "claude"
  local claude_cmd = base_cmd
  
  -- Add any additional arguments
  if #claude_args > 0 then
    claude_cmd = base_cmd .. " " .. table.concat(claude_args, " ")
    debug.log("Using Claude command with args: " .. claude_cmd)
  else
    debug.log("Using Claude command without flags: " .. claude_cmd)
  end
  
  -- Create a new window for Claude Code
  -- Use a consistent window name to help with detection
  local window_name = "claude"
  debug.log("Creating new Claude window with command: " .. claude_cmd)
  
  -- Create the new window and capture its index immediately
  local create_cmd = string.format("tmux new-window -d -n %s -P -F '#{window_index}' 'cd %s && %s'", 
    window_name, vim.fn.shellescape(git_root), claude_cmd)
  
  debug.log("Running command: " .. create_cmd)
  local new_window_idx = vim.fn.system(create_cmd)
  new_window_idx = vim.trim(new_window_idx)
  
  if vim.v.shell_error ~= 0 or new_window_idx == "" then
    vim.notify("Failed to create Claude Code instance", vim.log.levels.ERROR)
    debug.log("Failed to create window, error code: " .. vim.v.shell_error)
    return nil
  end
  
  debug.log("Successfully created new window with index: " .. new_window_idx)
  
  -- Give it time to start - increased from 0.5 to 2.0 seconds for slow Claude initialization
  vim.fn.system("sleep 2.0")
  
  -- Verify the window still exists and has expected name
  local verify_window_cmd = string.format("tmux list-windows -t %s: | grep '^%s:' | grep '%s'", 
                                        vim.fn.shellescape(current_session), new_window_idx, window_name)
  local window_verify = vim.fn.system(verify_window_cmd)
  
  if vim.trim(window_verify) == "" then
    debug.log("WARNING: Could not verify new window with name '" .. window_name .. "'")
    -- Try without name check
    verify_window_cmd = string.format("tmux list-windows -t %s: | grep '^%s:'", 
                                     vim.fn.shellescape(current_session), new_window_idx)
    window_verify = vim.fn.system(verify_window_cmd)
    
    if vim.trim(window_verify) == "" then
      vim.notify("Failed to verify new Claude Code window", vim.log.levels.ERROR)
      return nil
    else
      debug.log("Window exists but may have unexpected name: " .. vim.trim(window_verify))
    end
  else
    debug.log("Successfully verified window exists with correct name")
  end
  
  -- Get the pane ID
  local pane_cmd = string.format("tmux list-panes -t %s:%s -F '#{pane_id},#{pane_active},#{pane_current_command}'", 
                               vim.fn.shellescape(current_session), new_window_idx)
  debug.log("Running pane query: " .. pane_cmd)
  local pane_output = vim.fn.system(pane_cmd)
  
  -- Log full pane details for debugging
  debug.log("Pane details: " .. vim.trim(pane_output))
  
  -- Extract the pane ID from output
  local pane_id = vim.trim(pane_output):match("(%%[0-9]+)")
  
  if not pane_id or pane_id == "" then
    vim.notify("Failed to get new Claude Code pane ID", vim.log.levels.ERROR)
    debug.log("Failed to extract pane ID from: " .. pane_output)
    return nil
  end
  
  debug.log("Using pane ID: " .. pane_id)
  
  -- Return the instance info
  return {
    pane_id = pane_id,
    session = current_session,
    window_name = window_name,
    window_idx = new_window_idx,
    pane_idx = "0",
    command = claude_cmd, -- Use the appropriate command based on use_continue
    detection_method = "[new]",
    display = string.format("%s: %s.0 (%s) [new]", current_session, new_window_idx, window_name)
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
  
  debug.log("Sending context to Claude instance: " .. vim.inspect(instance))
  
  -- For new instances, add a brief delay to ensure Claude is ready to accept input
  if instance.detection_method == "[new]" then
    debug.log("New instance detected, adding extra delay to ensure readiness")
    vim.fn.system("sleep 1.0")
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
  
  -- Paste content buffer into target pane with retry logic
  local max_retries = 3
  local success = false
  
  -- Verify the pane exists before attempting to paste
  local verify_cmd = string.format("tmux has-session -t %s 2>/dev/null && echo exists || echo missing", 
                                  instance.pane_id)
  local pane_exists = vim.trim(vim.fn.system(verify_cmd))
  
  debug.log("Verifying pane existence: " .. pane_exists .. " for pane " .. instance.pane_id)
  
  if pane_exists ~= "exists" then
    debug.log("WARNING: Pane " .. instance.pane_id .. " doesn't exist before paste! Trying to find by window index")
    
    -- Try to find by window index instead
    local find_cmd = string.format("tmux list-panes -t %s:%s -F '#{pane_id}'", 
                                  instance.session, instance.window_idx)
    local alternative_pane = vim.trim(vim.fn.system(find_cmd))
    
    if alternative_pane ~= "" then
      debug.log("Found alternative pane ID: " .. alternative_pane)
      instance.pane_id = alternative_pane
    else
      debug.log("Failed to find alternative pane ID!")
      return false
    end
  end
  
  -- Ensure the window is active before pasting
  local window_cmd = string.format('tmux select-window -t %s:%s', 
                                instance.session, instance.window_idx)
  debug.log("Activating window before paste with: " .. window_cmd)
  vim.fn.system(window_cmd)
  
  for retry = 1, max_retries do
    -- Paste content buffer into target pane (silently)
    local paste_cmd = string.format('tmux paste-buffer -b claude_context -t %s 2>/dev/null', instance.pane_id)
    debug.log("Attempting to paste with command: " .. paste_cmd)
    local result = vim.fn.system(paste_cmd)
    
    if vim.v.shell_error == 0 then
      success = true
      debug.log("Successfully pasted context on attempt " .. retry)
      break
    else
      debug.log("Paste attempt " .. retry .. " failed with error code " .. vim.v.shell_error .. ", retrying after delay...")
      debug.log("Error output: " .. (result or ""))
      -- Increase delay with each retry
      vim.fn.system("sleep " .. retry * 0.5)
    end
  end
  
  -- Clean up temp file
  os.remove(temp_file)
  
  if not success then
    vim.notify("Failed to paste context into Claude Code pane after " .. max_retries .. " attempts", vim.log.levels.ERROR)
    return false
  end
  
  -- Switch to pane if enabled
  if config.get().auto_switch_pane then
    -- Verify the pane still exists before attempting to switch
    local verify_pane_cmd = string.format('tmux has-session -t %s 2>/dev/null && echo "exists" || echo "missing"', 
                                         instance.pane_id)
    local pane_exists = vim.trim(vim.fn.system(verify_pane_cmd))
    
    if pane_exists ~= "exists" then
      debug.log("WARNING: Pane " .. instance.pane_id .. " no longer exists!")
      
      -- Try to find the pane by window index instead
      local find_pane_cmd = string.format("tmux list-panes -t %s:%s -F '#{pane_id}'", 
                                         instance.session, instance.window_idx)
      local alternative_pane = vim.trim(vim.fn.system(find_pane_cmd))
      
      if alternative_pane ~= "" then
        debug.log("Found alternative pane in same window: " .. alternative_pane)
        instance.pane_id = alternative_pane
      else
        debug.log("Could not find any pane in window " .. instance.window_idx)
        vim.notify("Cannot switch to Claude pane - pane no longer exists", vim.log.levels.WARN)
        return true -- Still return success since we sent the content
      end
    end
    
    -- For new instances, add a brief delay before switching to ensure everything is ready
    if instance.detection_method == "[new]" then
      debug.log("New instance detected, adding small delay before switching")
      vim.fn.system("sleep 0.3")
    end
    
    -- First focus the window to ensure we're in the right context
    local window_cmd = string.format('tmux select-window -t %s:%s', 
                                    instance.session, instance.window_idx)
    debug.log("Selecting window with: " .. window_cmd)
    vim.fn.system(window_cmd)
    
    -- Then select the pane
    local switch_cmd = string.format('tmux select-pane -t %s', instance.pane_id)
    debug.log("Selecting pane with: " .. switch_cmd)
    local switch_result = vim.fn.system(switch_cmd)
    
    if vim.v.shell_error ~= 0 then
      debug.log("Failed to switch to pane: " .. (switch_result or ""))
      
      -- Try alternative approach with session:window.pane format
      switch_cmd = string.format('tmux select-pane -t %s:%s.%s', 
                                instance.session, instance.window_idx, instance.pane_idx)
      debug.log("Trying alternative pane selection: " .. switch_cmd)
      vim.fn.system(switch_cmd)
    end
    
    -- For new instances, ensure the window is fully activated with a second attempt
    if instance.detection_method == "[new]" then
      debug.log("Ensuring window activation for new instance with second attempt")
      vim.fn.system(window_cmd)
    end
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
    debug.log("No existing Claude instances found. Creating a new one with --continue flag")
    
    -- Create new instance silently if none found using claude --continue flag
    -- When creating via get_claude_code_instances, we want to use the full command with flags
    -- Pass --continue flag for automatic instance creation
    local new_instance = M.create_claude_code_instance(git_root, "--continue")
    
    -- If creation fails, verify we're actually passing the correct command 
    if not new_instance then
      debug.log("Failed initial instance creation attempt. Debug command being used: " .. config.get().claude_code_cmd)
      
      -- Try again with direct command
      -- This is a fallback in case the flag parameter isn't working
      local create_cmd = string.format("tmux new-window -d -n %s -P -F '#{window_index}' 'cd %s && %s'", 
        "claude", vim.fn.shellescape(git_root), config.get().claude_code_cmd)
      
      debug.log("Trying direct command creation: " .. create_cmd)
      local new_window_idx = vim.fn.system(create_cmd)
      new_window_idx = vim.trim(new_window_idx)
      
      -- If direct creation worked, proceed with creating our instance manually
      if vim.v.shell_error == 0 and new_window_idx ~= "" then
        debug.log("Direct creation succeeded with window index: " .. new_window_idx)
        
        -- Get current session
        local current_session = vim.fn.system("tmux display-message -p '#{session_name}'")
        current_session = vim.trim(current_session)
        
        -- Give it time to start
        vim.fn.system("sleep 0.5")
        
        -- Get the pane ID
        local pane_cmd = string.format("tmux list-panes -t %s:%s -F '#{pane_id}'", 
                                     vim.fn.shellescape(current_session), new_window_idx)
        local pane_id = vim.trim(vim.fn.system(pane_cmd))
        
        if pane_id ~= "" then
          new_instance = {
            pane_id = pane_id,
            session = current_session,
            window_name = "claude",
            window_idx = new_window_idx,
            pane_idx = "0",
            command = config.get().claude_code_cmd,
            detection_method = "[new]",
            display = string.format("%s: %s.0 (claude) [new]", current_session, new_window_idx)
          }
          debug.log("Successfully created instance via direct method")
        end
      end
    end
    
    if new_instance then
      debug.log("Successfully created new Claude instance with ID: " .. new_instance.pane_id)
      
      -- Verify the pane actually exists before proceeding
      local verify_cmd = string.format("tmux has-session -t %s 2>/dev/null && echo exists || echo missing", 
                                      new_instance.pane_id)
      local pane_exists = vim.trim(vim.fn.system(verify_cmd))
      
      if pane_exists ~= "exists" then
        debug.log("WARNING: Newly created pane doesn't exist! Trying to find by window index")
        
        -- Try to find by window index instead
        local find_cmd = string.format("tmux list-panes -t %s:%s -F '#{pane_id}'", 
                                      new_instance.session, new_instance.window_idx)
        local alternative_pane = vim.trim(vim.fn.system(find_cmd))
        
        if alternative_pane ~= "" then
          debug.log("Found alternative pane ID: " .. alternative_pane)
          new_instance.pane_id = alternative_pane
        else
          debug.log("Failed to find alternative pane ID!")
          vim.notify("Warning: Created new Claude instance but couldn't verify its pane ID", vim.log.levels.WARN)
        end
      end
      
      if config.get().remember_choice then
        config.set_remembered_instance(git_root, new_instance)
      end
      
      callback(new_instance)
    else
      debug.log("Failed to create new Claude instance!")
      vim.notify("Failed to create new Claude Code instance", vim.log.levels.ERROR)
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
    
    -- Create a selection menu with a proper table view format using tmux pane information
    debug.log("Building instance selection menu with tmux pane information")
    
    -- Create a menu with header
    local menu_items = {"Select Claude Code instance:"}
    
    -- Table dimensions and formatting
    local table_width = 90
    local col_widths = {3, 12, 8, 6, 10, 45}  -- Adjust column widths here
    
    -- Create horizontal separator line
    local function make_separator()
      local line = "+"
      for _, width in ipairs(col_widths) do
        line = line .. string.rep("-", width) .. "+"
      end
      return line
    end
    
    -- Add top border
    table.insert(menu_items, make_separator())
    
    -- Add header row
    local header = string.format("| %-" .. (col_widths[1]-1) .. "s | %-" .. (col_widths[2]-1) .. "s | %-" .. 
                                (col_widths[3]-1) .. "s | %-" .. (col_widths[4]-1) .. "s | %-" .. (col_widths[5]-1) .. "s | %-" .. (col_widths[6]-1) .. "s |",
                                "#", "Session", "Window", "Pane", "Type", "Description")
    table.insert(menu_items, header)
    
    -- Add separator after header
    table.insert(menu_items, make_separator())
    
    -- Process each instance for the menu
    for i, instance in ipairs(instances) do
      -- Get detailed information about this pane
      local pane_info_cmd = string.format(
        "tmux display-message -t %s -p '#{window_name}|#{pane_title}|#{pane_current_command}|#{pane_current_path}'",
        instance.pane_id
      )
      local pane_info = vim.fn.system(pane_info_cmd):gsub("%s+$", "")
      
      -- Parse the info
      local window_name, pane_title, pane_cmd, pane_path = pane_info:match("([^|]+)|([^|]+)|([^|]+)|(.+)")
      debug.log("Pane " .. i .. " info - Window: " .. (window_name or "nil") .. 
                ", Title: " .. (pane_title or "nil") .. 
                ", Command: " .. (pane_cmd or "nil") .. 
                ", Path: " .. (pane_path or "nil"))
      
      -- Determine a good display name
      local display_name
      
      -- First priority: Use stored last line if available
      if instance.last_line and instance.last_line ~= "" then
        -- Keep only first 40 chars
        if #instance.last_line > 40 then
          display_name = string.sub(instance.last_line, 1, 37) .. "..."
        else
          display_name = instance.last_line
        end
        debug.log("Using stored last line as display name: " .. display_name)
      -- If not available, get it from the pane now
      else
        -- This is the most useful context for identifying what the Claude session is about
        local last_line_cmd = string.format(
          [[tmux capture-pane -p -t %s | grep -B 1 -m 1 -e '╭─\{1,\}╮' | grep -v '╭─\{1,\}╮' | grep -v '^$' | tail -n 1]],
          instance.pane_id
        )
        local last_line = vim.fn.system(last_line_cmd):gsub("%s+$", "")
        
        if last_line and last_line ~= "" then
          -- Keep only first 40 chars
          if #last_line > 40 then
            last_line = string.sub(last_line, 1, 37) .. "..."
          end
          
          display_name = last_line
          debug.log("Using last line before prompt as display name: " .. display_name)
        -- Second priority: Use pane title if it's set and meaningful
        elseif pane_title and pane_title ~= "" and pane_title ~= "zsh" and pane_title ~= "bash" then
          display_name = pane_title
        -- Third priority: Use window name
        elseif window_name and window_name ~= "" then
          display_name = window_name
        -- Last resort: Just use Claude
        else
          display_name = "Claude instance"
        end
      end
      
      -- Add command info for extra context if not already in the name
      if pane_cmd and pane_cmd ~= "" and pane_cmd ~= "node" and 
         not display_name:match(pane_cmd) then
        display_name = display_name .. " (" .. pane_cmd .. ")"
      end
      
      -- Format as a nice table row
      local row = string.format("| %-" .. (col_widths[1]-1) .. "d | %-" .. (col_widths[2]-1) .. "s | %-" .. 
                               (col_widths[3]-1) .. "s | %-" .. (col_widths[4]-1) .. "s | %-" .. (col_widths[5]-1) .. "s | %-" .. (col_widths[6]-1) .. "s |",
                               i, 
                               instance.session, 
                               "W:" .. instance.window_idx, 
                               "P:" .. instance.pane_idx,
                               instance.detection_method or "[unknown]",
                               display_name)
      
      table.insert(menu_items, row)
    end
    
    -- Add bottom border
    table.insert(menu_items, make_separator())
    
    -- Add a blank line before the create option
    table.insert(menu_items, "")
    
    -- Add option to create a new instance
    table.insert(menu_items, string.format("%d. Create new Claude Code instance", #instances + 1))
    
    -- Display the menu with vim.fn.inputlist
    vim.schedule(function()
      -- Save more information to make selection command silent
      local more = vim.o.more
      vim.o.more = false
      
      -- Show a numbered list of options with content previews
      local choice_idx = vim.fn.inputlist(menu_items)
      
      -- Restore 'more' option
      vim.o.more = more
      
      -- Process selection - ensure index is valid
      if choice_idx >= 1 and choice_idx <= #instances then
        -- Use selected instance
        if config.get().remember_choice then
          config.set_remembered_instance(git_root, instances[choice_idx])
        end
        callback(instances[choice_idx])
      elseif choice_idx == #instances + 1 then
        -- Create new instance
        local new_instance = M.create_claude_code_instance(git_root)
        if new_instance and config.get().remember_choice then
          config.set_remembered_instance(git_root, new_instance)
        end
        callback(new_instance)
      end
      
      -- Force redraw to clear any messages
      vim.cmd("redraw!")
    end)
  end
end

return M