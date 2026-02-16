local M = {}
local config = require('llm-assist.config')
local api = require('llm-assist.api')
local ui = require('llm-assist.ui')

-- Plugin state
M.state = {
  current_model = nil,
  last_response = nil,
  is_loading = false,
}

-- Initialize the plugin
function M.setup(user_config)
  config.setup(user_config)
  M.state.current_model = config.options.default_model
  
  -- Create user commands
  vim.api.nvim_create_user_command('LLMAsk', function(opts)
    M.ask(opts.args)
  end, { nargs = '?', desc = 'Ask LLM a question' })
  
  vim.api.nvim_create_user_command('LLMExplain', function()
    M.explain_code()
  end, { range = true, desc = 'Explain selected code' })
  
  vim.api.nvim_create_user_command('LLMQuery', function(opts)
    M.query_code(opts.args)
  end, { range = true, nargs = '?', desc = 'Ask a question about selected code' })
  
  vim.api.nvim_create_user_command('LLMModel', function(opts)
    M.switch_model(opts.args)
  end, { nargs = 1, desc = 'Switch LLM model', complete = function()
    return config.options.models
  end })
  
  vim.api.nvim_create_user_command('LLMModels', function()
    M.list_models()
  end, { desc = 'List available models' })
  
  vim.api.nvim_create_user_command('LLMCancel', function()
    M.cancel_request()
  end, { desc = 'Cancel current LLM request' })
  
  vim.api.nvim_create_user_command('LLMTest', function()
    M.test_connection()
  end, { desc = 'Test API connection' })
end

-- Ask a question
function M.ask(question)
  if not question or question == '' then
    question = vim.fn.input('Ask LLM: ')
    if question == '' then return end
  end
  
  M.state.is_loading = true
  ui.show_loading("Asking " .. M.state.current_model .. "...")
  
  api.ask_model(M.state.current_model, question, function(response, error)
    M.state.is_loading = false
    ui.hide_loading()
    
    if error then
      ui.show_error("Error: " .. error)
    else
      M.state.last_response = response
      ui.show_response(response, M.state.current_model)
    end
  end)
end

-- Explain selected code
function M.explain_code()
  local code = ui.get_visual_selection()
  if not code or code == '' then
    ui.show_error("No code selected. Please select code in visual mode first.")
    return
  end
  
  local filetype = vim.bo.filetype
  local question = string.format(
    "Explain this %s code in detail:\n\n```%s\n%s\n```",
    filetype ~= '' and filetype or 'code', 
    filetype, 
    code
  )
  
  M.state.is_loading = true
  ui.show_loading("Explaining code with " .. M.state.current_model .. "...")
  
  api.ask_model(M.state.current_model, question, function(response, error)
    M.state.is_loading = false
    ui.hide_loading()
    
    if error then
      ui.show_error("Error: " .. error)
    else
      ui.show_response(response, M.state.current_model .. " - Code Explanation")
    end
  end, config.options.system_prompts.explain)
end

-- Query selected code with custom question
function M.query_code(user_question)
  local code = ui.get_visual_selection()
  if not code or code == '' then
    ui.show_error("No code selected. Please select code in visual mode first.")
    return
  end
  
  -- If no question provided, ask for one
  if not user_question or user_question == '' then
    user_question = vim.fn.input('Ask about the selected code: ')
    if user_question == '' then return end
  end
  
  local filetype = vim.bo.filetype
  local question = string.format(
    "%s\n\n```%s\n%s\n```",
    user_question,
    filetype, 
    code
  )
  
  M.state.is_loading = true
  ui.show_loading("Querying " .. M.state.current_model .. "...")
  
  api.ask_model(M.state.current_model, question, function(response, error)
    M.state.is_loading = false
    ui.hide_loading()
    
    if error then
      ui.show_error("Error: " .. error)
    else
      ui.show_response(response, M.state.current_model .. " - Code Query")
    end
  end)
end

-- Switch model
function M.switch_model(model)
  local available_models = config.options.models
  local found = false
  
  for _, m in ipairs(available_models) do
    if m == model then
      found = true
      break
    end
  end
  
  if found then
    M.state.current_model = model
    vim.notify("✓ Switched to model: " .. model, vim.log.levels.INFO)
  else
    ui.show_error("Model not found: " .. model .. "\nAvailable models: " .. table.concat(available_models, ", "))
  end
end

-- List available models
function M.list_models()
  local models = config.options.models
  local current = M.state.current_model
  
  local lines = {"Available Models:", ""}
  for _, model in ipairs(models) do
    local marker = (model == current) and "→ " or "  "
    table.insert(lines, marker .. model)
  end
  
  ui.show_info(table.concat(lines, "\n"))
end

-- Cancel current request
function M.cancel_request()
  if M.state.is_loading then
    M.state.is_loading = false
    ui.hide_loading()
    vim.notify("Request cancelled", vim.log.levels.WARN)
  else
    vim.notify("No active request to cancel", vim.log.levels.INFO)
  end
end

-- Test API connection
function M.test_connection()
  ui.show_loading("Testing connection...")
  
  api.test_connection(function(success, message)
    ui.hide_loading()
    
    if success then
      vim.notify("✓ " .. message, vim.log.levels.INFO)
    else
      ui.show_error(message)
    end
  end)
end

return M
