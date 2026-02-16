local M = {}
local config = require('llm-assist.config')

-- State
M.state = {
  response_buf = nil,
  response_win = nil,
  chat_buf = nil,
  chat_win = nil,
  loading_buf = nil,
  loading_win = nil,
  loading_timer = nil
}

-- Get visual selection
function M.get_visual_selection()
  -- Try to get from visual marks first (for range commands like :'<,'>)
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  local start_col = vim.fn.col("'<")
  local end_col = vim.fn.col("'>")
  
  -- Check if we have valid marks
  if start_line > 0 and end_line > 0 then
    local lines = vim.fn.getline(start_line, end_line)
    
    if #lines == 0 then
      return ''
    end
    
    -- Handle single line selection
    if #lines == 1 then
      lines[1] = string.sub(lines[1], start_col, end_col)
    else
      -- Handle multi-line selection
      lines[1] = string.sub(lines[1], start_col)
      lines[#lines] = string.sub(lines[#lines], 1, end_col)
    end
    
    return table.concat(lines, '\n')
  end
  
  -- Fallback: try yanking from visual mode (for keymap usage)
  local saved_reg = vim.fn.getreg('"')
  local saved_regtype = vim.fn.getregtype('"')
  
  vim.cmd('noau normal! "vy"')
  local selection = vim.fn.getreg('v')
  
  vim.fn.setreg('"', saved_reg, saved_regtype)
  
  return selection
end

-- Create floating window
function M.create_float_win(buf, opts)
  opts = opts or {}
  local width = opts.width or config.options.window.width
  local height = opts.height or config.options.window.height
  
  -- Calculate centered position
  local ui = vim.api.nvim_list_uis()[1]
  local win_width = ui.width
  local win_height = ui.height
  
  local col = math.floor((win_width - width) / 2)
  local row = math.floor((win_height - height) / 2)
  
  -- Create window
  local win_opts = {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = opts.border or config.options.window.border,
    title = opts.title,
    title_pos = opts.title and 'center' or nil
  }
  
  local win = vim.api.nvim_open_win(buf, true, win_opts)
  
  -- Set window options
  vim.api.nvim_win_set_option(win, 'wrap', true)
  vim.api.nvim_win_set_option(win, 'linebreak', true)
  
  return win
end

-- Show response in floating window
function M.show_response(response, model)
  -- Create buffer if it doesn't exist
  if not M.state.response_buf or not vim.api.nvim_buf_is_valid(M.state.response_buf) then
    M.state.response_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(M.state.response_buf, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(M.state.response_buf, 'filetype', 'markdown')
  end
  
  -- Make sure buffer is modifiable
  vim.api.nvim_buf_set_option(M.state.response_buf, 'modifiable', true)
  
  -- Parse response and extract code if present
  local lines = vim.split(response, '\n')
  
  -- Add helpful message at the top
  local all_lines = {
    "<!-- Press 'y' to copy, 'q' or <Esc> to close -->",
    ""
  }
  for _, line in ipairs(lines) do
    table.insert(all_lines, line)
  end
  
  -- Set buffer content
  vim.api.nvim_buf_set_lines(M.state.response_buf, 0, -1, false, all_lines)
  
  -- Now make buffer non-modifiable
  vim.api.nvim_buf_set_option(M.state.response_buf, 'modifiable', false)
  
  -- Calculate appropriate height
  local height = math.min(#all_lines + 2, 30)
  
  -- Create window
  M.state.response_win = M.create_float_win(M.state.response_buf, {
    title = " " .. model .. " ",
    height = height
  })
  
  -- Set keymaps for closing
  local close_keys = { 'q', '<Esc>' }
  for _, key in ipairs(close_keys) do
    vim.api.nvim_buf_set_keymap(M.state.response_buf, 'n', key, 
      ':close<CR>', { silent = true, noremap = true })
  end
  
  -- Add keymap to copy content
  vim.api.nvim_buf_set_keymap(M.state.response_buf, 'n', 'y', '', {
    silent = true,
    noremap = true,
    callback = function()
      local content = table.concat(vim.api.nvim_buf_get_lines(M.state.response_buf, 2, -1, false), "\n")
      vim.fn.setreg("+", content)
      vim.notify("✓ Copied to clipboard", vim.log.levels.INFO)
    end
  })
end

-- Show code replacement window
function M.show_code_replacement(response, original_code)
  -- Extract code from markdown code blocks
  local code = response:match("```[%w]*\n(.-)```") or response
  
  -- Remove leading/trailing whitespace
  code = code:gsub("^%s+", ""):gsub("%s+$", "")
  
  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'filetype', vim.bo.filetype)
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  
  local lines = vim.split(code, '\n')
  
  -- Add instructions at the top
  local all_lines = {
    "-- Press 'r' to replace original code, 'y' to copy, 'q' or <Esc> to close --",
    ""
  }
  for _, line in ipairs(lines) do
    table.insert(all_lines, line)
  end
  
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, all_lines)
  
  -- Make non-modifiable after adding content
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  -- Calculate height
  local height = math.min(#all_lines + 2, 30)
  
  -- Create window
  local win = M.create_float_win(buf, {
    title = " Refactored Code ",
    height = height
  })
  
  -- Keymaps
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { silent = true, noremap = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':close<CR>', { silent = true, noremap = true })
  
  -- Copy to clipboard
  vim.api.nvim_buf_set_keymap(buf, 'n', 'y', '', {
    silent = true,
    noremap = true,
    callback = function()
      vim.fn.setreg("+", code)
      vim.notify("✓ Copied to clipboard", vim.log.levels.INFO)
    end
  })
  
  -- Replace original selection
  vim.api.nvim_buf_set_keymap(buf, 'n', 'r', '', {
    silent = true,
    noremap = true,
    callback = function()
      -- Close the float window
      vim.api.nvim_win_close(win, true)
      
      -- Replace the visual selection with new code
      vim.cmd('normal! gv')
      vim.cmd('normal! "vd')
      
      -- Insert new code
      local new_lines = vim.split(code, '\n')
      local row = vim.fn.line('.')
      local col = vim.fn.col('.')
      
      vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, new_lines)
      
      vim.notify("✓ Code replaced!", vim.log.levels.INFO)
    end
  })
end

-- Show loading indicator
function M.show_loading(message)
  -- Stop any existing timer
  if M.state.loading_timer then
    if not M.state.loading_timer:is_closing() then
      M.state.loading_timer:stop()
      M.state.loading_timer:close()
    end
    M.state.loading_timer = nil
  end
  
  -- Create buffer
  M.state.loading_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.state.loading_buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(M.state.loading_buf, 'modifiable', true)
  
  local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local frame = 1
  
  local lines = {
    "",
    "  " .. spinner[frame] .. " " .. message,
    "  Please wait...",
    "",
    "  Press 'q' to cancel",
    ""
  }
  
  vim.api.nvim_buf_set_lines(M.state.loading_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.state.loading_buf, 'modifiable', false)
  
  -- Create small centered window
  M.state.loading_win = M.create_float_win(M.state.loading_buf, {
    width = math.max(50, #message + 10),
    height = 6,
    title = " Loading "
  })
  
  -- Keymap to cancel
  vim.api.nvim_buf_set_keymap(M.state.loading_buf, 'n', 'q', 
    ':LLMCancel<CR>', { silent = true, noremap = true })
  
  -- Animate spinner
  M.state.loading_timer = vim.loop.new_timer()
  M.state.loading_timer:start(0, 100, vim.schedule_wrap(function()
    -- Check if window is still valid
    if not M.state.loading_win or not vim.api.nvim_win_is_valid(M.state.loading_win) then
      if M.state.loading_timer and not M.state.loading_timer:is_closing() then
        M.state.loading_timer:stop()
        M.state.loading_timer:close()
      end
      M.state.loading_timer = nil
      return
    end
    
    -- Check if buffer is still valid
    if not M.state.loading_buf or not vim.api.nvim_buf_is_valid(M.state.loading_buf) then
      if M.state.loading_timer and not M.state.loading_timer:is_closing() then
        M.state.loading_timer:stop()
        M.state.loading_timer:close()
      end
      M.state.loading_timer = nil
      return
    end
    
    frame = (frame % #spinner) + 1
    lines[2] = "  " .. spinner[frame] .. " " .. message
    
    vim.api.nvim_buf_set_option(M.state.loading_buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(M.state.loading_buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(M.state.loading_buf, 'modifiable', false)
  end))
end

-- Hide loading indicator
function M.hide_loading()
  -- Stop timer first
  if M.state.loading_timer then
    if not M.state.loading_timer:is_closing() then
      M.state.loading_timer:stop()
      M.state.loading_timer:close()
    end
    M.state.loading_timer = nil
  end
  
  -- Close window
  if M.state.loading_win and vim.api.nvim_win_is_valid(M.state.loading_win) then
    vim.api.nvim_win_close(M.state.loading_win, true)
  end
  
  M.state.loading_win = nil
  M.state.loading_buf = nil
end

-- Open chat window
function M.open_chat_window(on_submit)
  -- Create chat buffer
  M.state.chat_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.state.chat_buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(M.state.chat_buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(M.state.chat_buf, 'buftype', 'nofile')
  
  -- Set initial content
  local lines = {
    "# LLM Chat",
    "",
    "Type your message below and press <CR> in normal mode to send.",
    "Press 'q' or <Esc> to close.",
    "",
    "---",
    "",
  }
  vim.api.nvim_buf_set_lines(M.state.chat_buf, 0, -1, false, lines)
  
  -- Create window
  M.state.chat_win = M.create_float_win(M.state.chat_buf, {
    title = " LLM Chat ",
    height = 25
  })
  
  -- Set keymaps
  vim.api.nvim_buf_set_keymap(M.state.chat_buf, 'n', 'q', ':close<CR>', { silent = true, noremap = true })
  vim.api.nvim_buf_set_keymap(M.state.chat_buf, 'n', '<Esc>', ':close<CR>', { silent = true, noremap = true })
  
  -- Submit on Enter
  vim.api.nvim_buf_set_keymap(M.state.chat_buf, 'n', '<CR>', '', {
    silent = true,
    noremap = true,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(M.state.chat_buf, 0, -1, false)
      local message_lines = {}
      local in_message = false
      
      -- Extract message after the separator
      for i, line in ipairs(lines) do
        if line == "---" then
          in_message = true
        elseif in_message and line ~= "" then
          table.insert(message_lines, line)
        end
      end
      
      local message = table.concat(message_lines, '\n'):gsub("^%s*(.-)%s*$", "%1")
      
      if message ~= "" then
        vim.api.nvim_win_close(M.state.chat_win, true)
        on_submit(message)
      else
        vim.notify("Please enter a message", vim.log.levels.WARN)
      end
    end
  })
  
  -- Move cursor to input area
  vim.api.nvim_win_set_cursor(M.state.chat_win, { 7, 0 })
  vim.cmd('startinsert')
end

-- Show error message
function M.show_error(message)
  vim.notify("❌ LLM-Assist: " .. message, vim.log.levels.ERROR)
end

-- Show info message
function M.show_info(message)
  vim.notify(message, vim.log.levels.INFO)
end

return M
