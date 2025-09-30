---@brief Fast Claude-Tmux-Neovim plugin for sending code context to Claude
local M = {}

-- Configuration constants
local MAX_CONTENT_SIZE = 100 * 1024   -- Maximum content size to prevent memory issues (100KB)
local CLAUDE_STARTUP_TIMEOUT = 30     -- Maximum seconds to wait for Claude startup

-- Get git root of current file or directory
---@param path string File path or directory path
---@return string|nil git_root Returns git root path or nil if not in a git repository
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
  
  -- Single pipeline to find Claude processes with their CWDs and tmux panes
  -- Pattern matches 'claude' as a standalone word (handles trailing spaces)
  -- Checks both parent PID and process PID for tmux pane mapping (handles both shell and direct execution)
  local cmd = "ps aux | grep -E '(^|[[:space:]])claude([[:space:]]|$)' | grep -v grep | awk '{print $2}' | while read pid; do " ..
              "cwd=$(lsof -p $pid 2>/dev/null | grep cwd | head -1 | awk '{print $NF}'); " ..
              "ppid=$(ps -p $pid -o ppid= | tr -d ' '); " ..
              "pane_info=$(tmux list-panes -a -F \"#{pane_pid} #{pane_id} #{session_name}:#{window_index}.#{pane_index}\" 2>/dev/null | grep -E \"^($ppid|$pid) \" | awk '{print $2, $3}'); " ..
              "if [ -n \"$cwd\" ] && [ -n \"$pane_info\" ]; then echo \"$pid|$cwd|$pane_info\"; fi; " ..
              "done"
  
  local result = vim.fn.system(cmd)
  
  for line in result:gmatch("[^\r\n]+") do
    local pid, cwd, pane_id, display = line:match("^(%d+)|([^|]+)|(%S+)%s+(.+)$")
    if pid and cwd and pane_id then
      -- Check if this instance is in the same git repository
      local instance_git_root = get_git_root(cwd)
      if instance_git_root == git_root then
        table.insert(instances, {
          pid = pid,
          cwd = cwd,
          pane_id = pane_id,
          display = display or pane_id,
        })
      end
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
-- Captures last 20 lines of pane and checks for Claude prompt pattern
---@param pane_id string Tmux pane ID to check
---@return boolean is_ready True if Claude is ready to receive input
---@return string|nil error_msg Error message if Claude is not ready, nil if no specific error
local function is_claude_ready(pane_id)
  local cmd = string.format('tmux capture-pane -p -t %s -S -20 2>/dev/null', vim.fn.shellescape(pane_id))
  local content = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return false, "Claude instance was closed"
  end

  -- Check for Claude prompt pattern: line of dashes followed by ">" on next line
  local has_claude_prompt = content:match("─+\n>") or content:match("─+\r\n>")

  if not has_claude_prompt then
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
    -- Visual mode - use vim.fn.getpos to get current selection
    local vstart = vim.fn.getpos("v")
    local vend = vim.fn.getpos(".")
    
    -- Ensure start comes before end
    if vstart[2] > vend[2] then
      vstart, vend = vend, vstart
    end
    
    start_line = vstart[2]
    end_line = vend[2]
    
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
---@param cwd string|nil Claude instance working directory
---@return string xml
local function create_context(filepath, selection, cwd)
  -- Make filepath relative to cwd if provided
  local display_path = filepath
  if cwd then
    -- Remove trailing slash from cwd if present
    cwd = cwd:gsub("/$", "")
    -- Make path relative if it starts with cwd
    if filepath:sub(1, #cwd) == cwd then
      display_path = filepath:sub(#cwd + 2) -- +2 to skip the directory and slash
    end
  end
  
  return string.format([[<context>
  <file>@%s</file>
  <start_line>%d</start_line>
  <end_line>%d</end_line>
  <selection>
%s
  </selection>
</context>]], display_path, selection.start_line, selection.end_line, selection.text)
end

-- Send content to Claude and switch to pane
-- Uses tmux send-keys in literal mode to avoid paste event issues
---@param pane_id string Tmux pane ID (format: %n)
---@param content string Content to send (max 100KB)
---@return boolean success Returns true if content was sent successfully
local function send_to_claude(pane_id, content)
  -- Validate pane_id format (should start with %)
  if not pane_id or not pane_id:match("^%%") then
    vim.notify("Invalid pane ID format", vim.log.levels.ERROR)
    return false
  end

  -- Validate content
  if not content or content == "" then
    vim.notify("No content to send", vim.log.levels.WARN)
    return false
  end

  local content_size = #content

  -- Check for maximum content size
  if content_size > MAX_CONTENT_SIZE then
    vim.notify(string.format("Content too large (%d KB). Maximum is %d KB.",
                             math.floor(content_size / 1024),
                             math.floor(MAX_CONTENT_SIZE / 1024)),
               vim.log.levels.WARN)
    return false
  end

  -- Use send-keys -l (literal mode) for all content to avoid paste event interpretation
  -- Break into chunks to avoid command-line length limits (use 4KB chunks for safety)
  local CHUNK_SIZE = 4096
  local pos = 1
  local success = true

  while pos <= content_size do
    local chunk = content:sub(pos, pos + CHUNK_SIZE - 1)
    local escaped_chunk = vim.fn.shellescape(chunk)
    local send_keys_cmd = string.format('tmux send-keys -l -t %s %s 2>/dev/null',
                                        vim.fn.shellescape(pane_id), escaped_chunk)
    vim.fn.system(send_keys_cmd)

    if vim.v.shell_error ~= 0 then
      vim.notify("Failed to send content to Claude", vim.log.levels.ERROR)
      success = false
      break
    end

    pos = pos + CHUNK_SIZE
  end

  if not success then
    return false
  end

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
  
  -- Wait for Claude to start and fully initialize with retry loop
  local start_time = vim.loop.hrtime() / 1000000  -- Convert to milliseconds
  local ready = false

  while not ready and (vim.loop.hrtime() / 1000000 - start_time) < (CLAUDE_STARTUP_TIMEOUT * 1000) do
    vim.fn.system("sleep 0.5")  -- Short sleep between checks
    local is_ready, _ = is_claude_ready(pane_id)
    if is_ready then
      ready = true
      break
    end
  end

  if not ready then
    vim.notify("Claude instance took too long to initialize", vim.log.levels.WARN)
    -- Continue anyway, but user should know
  end

  -- Send context
  local xml = create_context(filepath, selection, git_root)
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
  local xml = create_context(filepath, selection, instance.cwd)
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

  -- Validate file exists
  if vim.fn.filereadable(filepath) ~= 1 then
    vim.notify("File does not exist or is not readable: " .. filepath, vim.log.levels.ERROR)
    return
  end
  
  local git_root = get_git_root(filepath)
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.WARN)
    return
  end
  
  local selection = get_selection()
  local instances = find_claude_instances(git_root)
  
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

  -- Validate file exists
  if vim.fn.filereadable(filepath) ~= 1 then
    vim.notify("File does not exist or is not readable: " .. filepath, vim.log.levels.ERROR)
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
    M.send_to_existing()
  end, keymap_opts)
  
  vim.keymap.set({'n', 'v'}, opts.new_keymap or '<leader>cn', function()
    M.create_and_send()
  end, keymap_opts)
  
  -- Set up autocmds for auto-refresh when returning to Neovim
  local group = vim.api.nvim_create_augroup('ClaudeTmuxNeovim', { clear = true })
  
  vim.api.nvim_create_autocmd({'BufEnter', 'FocusGained'}, {
    group = group,
    callback = function()
      -- Check if the file has been modified externally and reload if needed
      vim.cmd('checktime')
    end,
  })
end

return M
