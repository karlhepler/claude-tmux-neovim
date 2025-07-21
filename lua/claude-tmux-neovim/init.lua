---@brief Fast Claude-Tmux-Neovim plugin for sending code context to Claude
local M = {}

-- Get git root of current file or directory
---@param path string File path or directory path
---@return string|nil git_root
local function get_git_root(path)
  -- If path is already a directory, use it directly. Otherwise get its parent directory
  local dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ':h')
  local result = vim.fn.system(string.format('git -C %s rev-parse --show-toplevel 2>/dev/null', vim.fn.shellescape(dir)))
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(result)
end

-- Find all Claude instances in the same git repository
---@param git_root string
---@return table[] instances
local function find_claude_instances(git_root)
  local instances = {}
  
  -- Debug: log the git root we're searching for
  vim.notify(string.format("DEBUG: Searching for Claude instances in git_root: %s", git_root), vim.log.levels.INFO)
  
  -- Single pipeline to find Claude processes with their CWDs and tmux panes
  -- Pattern matches 'claude' as a standalone word (handles trailing spaces)
  -- Checks both parent PID and process PID for tmux pane mapping (handles both shell and direct execution)
  local cmd = "ps aux | grep -E '(^|[[:space:]])claude([[:space:]]|$)' | grep -v grep | awk '{print $2}' | while read pid; do " ..
              "cwd=$(lsof -p $pid 2>/dev/null | grep cwd | awk '{print $NF}'); " ..
              "ppid=$(ps -p $pid -o ppid= | tr -d ' '); " ..
              "pane_info=$(tmux list-panes -a -F \"#{pane_pid} #{pane_id} #{session_name}:#{window_index}.#{pane_index}\" 2>/dev/null | grep -E \"^($ppid|$pid) \" | awk '{print $2, $3}'); " ..
              "if [ -n \"$cwd\" ] && [ -n \"$pane_info\" ]; then echo \"$pid|$cwd|$pane_info\"; fi; " ..
              "done"
  
  local result = vim.fn.system(cmd)
  
  -- Debug: log the raw result
  vim.notify(string.format("DEBUG: Raw command result: %s", vim.inspect(result)), vim.log.levels.INFO)
  
  for line in result:gmatch("[^\r\n]+") do
    local pid, cwd, pane_id, display = line:match("^(%d+)|([^|]+)|(%S+)%s+(.+)$")
    vim.notify(string.format("DEBUG: Processing line: %s", line), vim.log.levels.INFO)
    if pid and cwd and pane_id then
      -- Check if this instance is in the same git repository
      local instance_git_root = get_git_root(cwd)
      vim.notify(string.format("DEBUG: Instance git_root: %s, target git_root: %s", instance_git_root or "nil", git_root), vim.log.levels.INFO)
      if instance_git_root == git_root then
        vim.notify(string.format("DEBUG: Adding instance - PID: %s, CWD: %s, Pane: %s", pid, cwd, pane_id), vim.log.levels.INFO)
        table.insert(instances, {
          pid = pid,
          cwd = cwd,
          pane_id = pane_id,
          display = display or pane_id,
        })
      else
        vim.notify(string.format("DEBUG: Skipping instance - different git root", pid), vim.log.levels.INFO)
      end
    else
      vim.notify(string.format("DEBUG: Failed to parse line: %s", line), vim.log.levels.INFO)
    end
  end
  
  return instances
end

-- Sort instances by closest parent to file path
---@param instances table[]
---@param filepath string
---@return table[] sorted_instances
local function sort_by_closest_parent(instances, filepath)
  local file_dir = vim.fn.fnamemodify(filepath, ':h')
  
  table.sort(instances, function(a, b)
    -- Calculate how many path components match
    local a_parts = vim.split(a.cwd, '/')
    local b_parts = vim.split(b.cwd, '/')
    local file_parts = vim.split(file_dir, '/')
    
    local a_matches = 0
    local b_matches = 0
    
    for i = 1, math.min(#a_parts, #file_parts) do
      if a_parts[i] == file_parts[i] then
        a_matches = a_matches + 1
      else
        break
      end
    end
    
    for i = 1, math.min(#b_parts, #file_parts) do
      if b_parts[i] == file_parts[i] then
        b_matches = b_matches + 1
      else
        break
      end
    end
    
    return a_matches > b_matches
  end)
  
  return instances
end

-- Check if Claude is ready (has input box visible)
---@param pane_id string
---@return boolean is_ready
---@return string|nil error_msg
local function is_claude_ready(pane_id)
  local cmd = string.format('tmux capture-pane -p -t %s -S -10 2>/dev/null', vim.fn.shellescape(pane_id))
  local content = vim.fn.system(cmd)
  
  if vim.v.shell_error ~= 0 then
    return false, "Claude instance was closed"
  end
  
  -- Check for input box boundary (│ character)
  if not content:match("│") then
    return false, nil
  end
  
  -- Check for common blocking prompts
  if content:match("Select") or content:match("Choose") or content:match("Press Enter") then
    return false, "Claude is waiting for your input and cannot receive data"
  end
  
  return true, nil
end

-- Get selection or current line
---@return table selection_info
local function get_selection()
  local mode = vim.fn.mode()
  local text, start_line, end_line
  
  if mode:match("[vV\22]") then
    -- Visual mode - get full lines
    start_line = vim.fn.line("'<")
    end_line = vim.fn.line("'>")
    
    -- Get all lines in the range
    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    text = table.concat(lines, "\n")
  else
    -- Normal mode - get current line
    start_line = vim.fn.line(".")
    end_line = start_line
    text = vim.fn.getline(".")
  end
  
  return {
    text = text,
    start_line = start_line,
    end_line = end_line,
  }
end

-- Create XML context
---@param filepath string
---@param selection table
---@return string xml
local function create_context(filepath, selection)
  return string.format([[<context>
  <file>@%s</file>
  <start_line>%d</start_line>
  <end_line>%d</end_line>
  <selection>
%s
  </selection>
</context>]], filepath, selection.start_line, selection.end_line, selection.text)
end

-- Send content to Claude and switch to pane
---@param pane_id string
---@param content string
---@return boolean success
local function send_to_claude(pane_id, content)
  -- Load content into tmux buffer
  local temp_file = os.tmpname()
  local file = io.open(temp_file, "w")
  if not file then
    vim.notify("Failed to create temporary file", vim.log.levels.ERROR)
    return false
  end
  file:write(content)
  file:close()
  
  -- Load buffer and paste
  local load_cmd = string.format('tmux load-buffer -b claude_temp %s 2>/dev/null', vim.fn.shellescape(temp_file))
  vim.fn.system(load_cmd)
  os.remove(temp_file)
  
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to load content into tmux buffer", vim.log.levels.ERROR)
    return false
  end
  
  -- Paste buffer into Claude pane
  local paste_cmd = string.format('tmux paste-buffer -b claude_temp -t %s 2>/dev/null', vim.fn.shellescape(pane_id))
  vim.fn.system(paste_cmd)
  
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to paste into Claude", vim.log.levels.ERROR)
    return false
  end
  
  -- Delete the buffer
  vim.fn.system('tmux delete-buffer -b claude_temp 2>/dev/null')
  
  -- Switch to Claude pane
  local switch_cmd = string.format('tmux switch-client -t %s 2>/dev/null || tmux select-pane -t %s 2>/dev/null', 
                                   vim.fn.shellescape(pane_id), vim.fn.shellescape(pane_id))
  vim.fn.system(switch_cmd)
  
  return true
end

-- Create new Claude instance
---@param flags string
---@param selection table
---@return boolean success
local function create_new_claude(flags, selection)
  local filepath = vim.fn.expand('%:p')
  local git_root = get_git_root(filepath)
  
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.WARN)
    return false
  end
  
  -- Create the command
  local claude_cmd = flags ~= "" and string.format("claude %s", flags) or "claude"
  
  -- Create new tmux window with Claude
  local cmd = string.format("tmux new-window -c %s -n claude -P -F '#{pane_id}' %s", 
                           vim.fn.shellescape(git_root), vim.fn.shellescape(claude_cmd))
  local pane_id = vim.trim(vim.fn.system(cmd))
  
  if vim.v.shell_error ~= 0 or pane_id == "" then
    vim.notify("Failed to create Claude instance", vim.log.levels.ERROR)
    return false
  end
  
  -- Wait for Claude to start and fully initialize
  vim.fn.system("sleep 3")
  
  -- Send context
  local xml = create_context(filepath, selection)
  return send_to_claude(pane_id, xml)
end

-- Use existing Claude instance
---@param instance table
---@param selection table
---@return boolean success
local function use_instance(instance, selection)
  local filepath = vim.fn.expand('%:p')
  
  -- Check if Claude is ready
  local is_ready, error_msg = is_claude_ready(instance.pane_id)
  if not is_ready then
    if error_msg then
      vim.notify(error_msg, vim.log.levels.ERROR)
    end
    -- Switch to Claude anyway so user can see what's blocking
    vim.fn.system(string.format('tmux switch-client -t %s 2>/dev/null || tmux select-pane -t %s 2>/dev/null', 
                               vim.fn.shellescape(instance.pane_id), vim.fn.shellescape(instance.pane_id)))
    return false
  end
  
  -- Send context
  local xml = create_context(filepath, selection)
  return send_to_claude(instance.pane_id, xml)
end

-- Show instance picker
---@param instances table[]
---@param selection table
local function show_instance_picker(instances, selection)
  local items = {}
  
  -- Add existing instances
  for _, instance in ipairs(instances) do
    table.insert(items, {
      text = string.format("%s (%s) - %s", instance.pane_id, instance.display, instance.cwd),
      instance = instance,
    })
  end
  
  -- Add "Create new" option
  table.insert(items, {
    text = "Create new Claude instance",
    create_new = true,
  })
  
  -- Show picker
  vim.ui.select(items, {
    prompt = "Select Claude instance:",
    format_item = function(item) return item.text end,
  }, function(choice)
    if not choice then
      return
    end
    
    if choice.create_new then
      create_new_claude("--continue", selection)
    else
      use_instance(choice.instance, selection)
    end
  end)
end

-- Main function for <leader>cc
function M.send_to_existing()
  local filepath = vim.fn.expand('%:p')
  if filepath == "" then
    vim.notify("No file open", vim.log.levels.WARN)
    return
  end
  
  local git_root = get_git_root(filepath)
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.WARN)
    return
  end
  
  local selection = get_selection()
  local instances = find_claude_instances(git_root)
  
  -- Debug output
  vim.notify(string.format("Found %d Claude instances in git root: %s", #instances, git_root), vim.log.levels.INFO)
  for i, instance in ipairs(instances) do
    vim.notify(string.format("  Instance %d: PID=%s, CWD=%s, Pane=%s", i, instance.pid, instance.cwd, instance.pane_id), vim.log.levels.INFO)
  end
  
  if #instances == 0 then
    -- No instances, create new with --continue
    create_new_claude("--continue", selection)
  elseif #instances == 1 then
    -- Single instance, use it
    use_instance(instances[1], selection)
  else
    -- Multiple instances, sort by closest parent and show picker
    instances = sort_by_closest_parent(instances, filepath)
    show_instance_picker(instances, selection)
  end
end

-- Main function for <leader>cn
function M.create_and_send()
  local filepath = vim.fn.expand('%:p')
  if filepath == "" then
    vim.notify("No file open", vim.log.levels.WARN)
    return
  end
  
  local selection = get_selection()
  create_new_claude("", selection)
end

-- Setup function
function M.setup(opts)
  opts = opts or {}
  
  -- Set up keymaps
  local keymap_opts = { noremap = true, silent = true }
  
  vim.keymap.set({'n', 'v'}, opts.send_keymap or '<leader>cc', function()
    -- Exit visual mode first if in visual mode
    if vim.fn.mode():match("[vV\22]") then
      vim.cmd('normal! gv')
    end
    M.send_to_existing()
  end, keymap_opts)
  
  vim.keymap.set({'n', 'v'}, opts.new_keymap or '<leader>cn', function()
    -- Exit visual mode first if in visual mode
    if vim.fn.mode():match("[vV\22]") then
      vim.cmd('normal! gv')
    end
    M.create_and_send()
  end, keymap_opts)
end

return M