local M = {}

-- Default configuration
local default_config = {
  keymap = "<leader>cc", -- Default keymap to trigger sending context
  claude_code_cmd = "claude", -- Command to start Claude Code
  auto_switch_pane = true, -- Automatically switch to tmux pane after sending
  remember_choice = true, -- Remember chosen Claude Code instance per git repo
  
  -- XML template for sending context
  xml_template = [[
<context>
  <file_path>%s</file_path>
  <git_root>%s</git_root>
  <line_number>%s</line_number>
  <column_number>%s</column_number>
  <selection>
%s
  </selection>
  <file_content>
%s
  </file_content>
</context>

Please review this code context.
]],
}

-- Store config
local config = {}

-- Store remembered instances
local remembered_instances = {}

-- Utility to check if tmux is running
local function is_tmux_running()
  local result = vim.fn.system('which tmux && tmux info >/dev/null 2>&1 && echo "true" || echo "false"')
  return vim.trim(result) == "true"
end

-- Get git root of current file
local function get_git_root()
  local file_dir = vim.fn.expand('%:p:h')
  local cmd = 'cd ' .. vim.fn.shellescape(file_dir) .. ' && git rev-parse --show-toplevel 2>/dev/null'
  local git_root = vim.fn.system(cmd)
  
  if vim.v.shell_error ~= 0 then
    return nil
  end
  
  return vim.trim(git_root)
end

-- Get selection from visual mode
local function get_visual_selection()
  local start_line, start_col = unpack(vim.fn.getpos("'<"), 2, 3)
  local end_line, end_col = unpack(vim.fn.getpos("'>"), 2, 3)
  
  -- Adjust columns for correct indexing
  start_col = start_col - 1
  end_col = end_col - 1
  
  -- Get lines from buffer
  local lines = vim.fn.getline(start_line, end_line)
  
  -- Handle single line selections
  if #lines == 1 then
    lines[1] = string.sub(lines[1], start_col + 1, end_col + 1)
  else
    -- Handle multi-line selections
    lines[1] = string.sub(lines[1], start_col + 1)
    lines[#lines] = string.sub(lines[#lines], 1, end_col + 1)
  end
  
  return table.concat(lines, '\n')
end

-- Get current file's content
local function get_file_content()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
end

-- List all Claude Code instances in tmux
local function get_claude_code_instances(git_root)
  if not git_root then
    return {}
  end

  -- Find all tmux panes running Claude Code within the same git repo
  local cmd = string.format([[tmux list-panes -a -F '#{pane_id} #{session_name} #{window_name} #{window_index} #{pane_index} #{pane_current_command}' | grep -i '%s' | grep -i '%s']], 
    config.claude_code_cmd, git_root)
  
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 or result == "" then
    return {}
  end
  
  local instances = {}
  for line in result:gmatch("[^\r\n]+") do
    local pane_id, session, window_name, window_idx, pane_idx, command = line:match("(%%[0-9]+) ([^ ]+) ([^ ]+) ([0-9]+) ([0-9]+) ([^ ]+)")
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

-- Create a new Claude Code instance
local function create_claude_code_instance(git_root)
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.ERROR)
    return nil
  end
  
  -- Get current tmux session
  local current_session = vim.fn.system("tmux display-message -p '#{session_name}'")
  current_session = vim.trim(current_session)
  
  -- Create a new window for Claude Code
  local cmd = string.format("tmux new-window -d -n claude-code 'cd %s && %s'", 
    vim.fn.shellescape(git_root), config.claude_code_cmd)
  local result = vim.fn.system(cmd)
  
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to create Claude Code instance: " .. result, vim.log.levels.ERROR)
    return nil
  end
  
  -- Get the new pane id
  vim.fn.system("sleep 0.5") -- Give it time to start
  local new_window_idx = vim.fn.system("tmux list-windows -t " .. vim.fn.shellescape(current_session) .. " | grep claude-code | cut -d: -f1")
  new_window_idx = vim.trim(new_window_idx)
  
  if new_window_idx == "" then
    vim.notify("Failed to get new Claude Code window index", vim.log.levels.ERROR)
    return nil
  end
  
  -- Get the pane ID
  local pane_id = vim.fn.system("tmux list-panes -t " .. vim.fn.shellescape(current_session) .. ":" .. new_window_idx .. " -F '#{pane_id}'")
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
    command = config.claude_code_cmd,
    display = string.format("%s: %s.0 (claude-code)", current_session, new_window_idx)
  }
end

-- Send context to Claude Code instance
local function send_to_claude_code(instance, context)
  if not instance or not instance.pane_id then
    vim.notify("Invalid Claude Code instance", vim.log.levels.ERROR)
    return false
  end
  
  -- Escape context for tmux
  local escaped_context = context:gsub([[\]], [[\\]]):gsub('"', '\\"')
  
  -- Load the context into a tmux buffer
  local load_cmd = string.format('tmux load-buffer -b claude_context %s', vim.fn.shellescape(escaped_context))
  vim.fn.system(load_cmd)
  
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to load context into tmux buffer", vim.log.levels.ERROR)
    return false
  end
  
  -- Paste the buffer into the target pane
  local paste_cmd = string.format('tmux paste-buffer -b claude_context -t %s', instance.pane_id)
  vim.fn.system(paste_cmd)
  
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to paste context into Claude Code pane", vim.log.levels.ERROR)
    return false
  end
  
  -- Switch to the pane if auto_switch_pane is enabled
  if config.auto_switch_pane then
    local switch_cmd = string.format('tmux select-pane -t %s', instance.pane_id)
    vim.fn.system(switch_cmd)
    
    if vim.v.shell_error ~= 0 then
      vim.notify("Failed to switch to Claude Code pane", vim.log.levels.WARN)
    end
  end
  
  return true
end

-- Select an instance or create a new one
local function select_claude_code_instance(git_root, callback)
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.ERROR)
    return
  end
  
  -- Check if we should use a remembered instance
  if config.remember_choice and remembered_instances[git_root] then
    local instance = remembered_instances[git_root]
    
    -- Verify the instance still exists
    local cmd = string.format("tmux has-session -t %s 2>/dev/null && echo true || echo false", instance.pane_id)
    local exists = vim.fn.system(cmd)
    
    if vim.trim(exists) == "true" then
      callback(instance)
      return
    else
      -- Instance no longer exists, clear the remembered choice
      remembered_instances[git_root] = nil
    end
  end
  
  -- Get available Claude Code instances
  local instances = get_claude_code_instances(git_root)
  
  if #instances == 0 then
    -- No instances found, create a new one
    local new_instance = create_claude_code_instance(git_root)
    if new_instance then
      if config.remember_choice then
        remembered_instances[git_root] = new_instance
      end
      callback(new_instance)
    end
  elseif #instances == 1 then
    -- Only one instance found, use it
    if config.remember_choice then
      remembered_instances[git_root] = instances[1]
    end
    callback(instances[1])
  else
    -- Multiple instances found, let user choose
    local choices = {}
    for i, instance in ipairs(instances) do
      table.insert(choices, string.format("%d. %s", i, instance.display))
    end
    table.insert(choices, string.format("%d. Create new Claude Code instance", #instances + 1))
    
    vim.ui.select(choices, {
      prompt = "Select Claude Code instance:",
      format_item = function(item) return item end,
    }, function(choice)
      if not choice then return end
      
      local idx = tonumber(choice:match("^(%d+)%."))
      if idx and idx <= #instances then
        if config.remember_choice then
          remembered_instances[git_root] = instances[idx]
        end
        callback(instances[idx])
      elseif idx == #instances + 1 then
        -- Create new instance
        local new_instance = create_claude_code_instance(git_root)
        if new_instance then
          if config.remember_choice then
            remembered_instances[git_root] = new_instance
          end
          callback(new_instance)
        end
      end
    end)
  end
end

-- Reset remembered instances
function M.reset_instances()
  remembered_instances = {}
  vim.notify("Reset all remembered Claude Code instances", vim.log.levels.INFO)
end

-- Reset remembered instance for current git root
function M.reset_git_instance()
  local git_root = get_git_root()
  if git_root and remembered_instances[git_root] then
    remembered_instances[git_root] = nil
    vim.notify("Reset Claude Code instance for " .. git_root, vim.log.levels.INFO)
  else
    vim.notify("No remembered instance for current git repository", vim.log.levels.WARN)
  end
end

-- Main function to send context
function M.send_context()
  if not is_tmux_running() then
    vim.notify("tmux is not running", vim.log.levels.ERROR)
    return
  end

  -- Get current file path
  local file_path = vim.fn.expand('%:p')
  if file_path == "" then
    vim.notify("No file open", vim.log.levels.ERROR)
    return
  end
  
  -- Get git root
  local git_root = get_git_root()
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.ERROR)
    return
  end
  
  -- Get cursor position
  local cursor_pos = vim.fn.getpos('.')
  local line_num = cursor_pos[2]
  local col_num = cursor_pos[3]
  
  -- Get selection (if in visual mode)
  local selection = ""
  local mode = vim.fn.mode()
  if mode == 'v' or mode == 'V' or mode == '' then
    -- Exit visual mode to ensure we can work with the selection
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
    selection = get_visual_selection()
  end
  
  -- Get file content
  local file_content = get_file_content()
  
  -- Create the context XML
  local context = string.format(config.xml_template,
    file_path,
    git_root,
    line_num,
    col_num,
    selection,
    file_content
  )
  
  -- Select Claude Code instance and send context
  select_claude_code_instance(git_root, function(instance)
    if instance then
      send_to_claude_code(instance, context)
    end
  end)
end

-- Plugin setup function
function M.setup(user_config)
  -- Merge default config with user config
  config = vim.tbl_deep_extend("force", default_config, user_config or {})
  
  -- Create user commands
  vim.api.nvim_create_user_command("ClaudeCodeSend", M.send_context, {})
  vim.api.nvim_create_user_command("ClaudeCodeReset", M.reset_instances, {})
  vim.api.nvim_create_user_command("ClaudeCodeResetGit", M.reset_git_instance, {})
  
  -- Set up keymapping
  if config.keymap and config.keymap ~= "" then
    vim.api.nvim_set_keymap('n', config.keymap, ':ClaudeCodeSend<CR>', { noremap = true, silent = true })
    vim.api.nvim_set_keymap('v', config.keymap, ':<C-u>ClaudeCodeSend<CR>', { noremap = true, silent = true })
  end
end

return M