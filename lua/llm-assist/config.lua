local M = {}

-- Default configuration
M.defaults = {
  -- API Configuration (from environment variables)
  api_base = os.getenv("LLM_API_BASE") or "https://open-webui.vayavyalabs.com:3000",
  api_key = os.getenv("LLM_API_KEY") or "",
  ca_bundle_path = os.getenv("LLM_CA_BUNDLE") or "",
  
  -- Available models
  models = {
    "gemma3:4b",
    "gpt-oss:120b",
    "deepseek-r1:latest",
    "gemma3:27b",
    "llama3.3:70b",
    "qwen3-coder:30b"
  },
  
  -- Default model
  default_model = "gemma3:4b",
  
  -- API Parameters
  temperature = 0.7,
  max_tokens = 1000,
  stream = false,
  timeout = 90,
  
  -- System prompts
  system_prompts = {
    default = "You are an experienced programmer. Answer concisely, accurately, and seriously.",
    explain = "You are an expert code reviewer. Explain code clearly and thoroughly.",
    refactor = "You are a senior software engineer. Suggest clean, maintainable refactorings.",
    optimize = "You are a performance optimization expert. Focus on efficiency and best practices."
  },
  
  -- UI Configuration
  window = {
    width = 80,
    height = 20,
    border = "rounded"
  },
  
  -- Keymaps (set to false to disable)
  keymaps = {
    ask = "<leader>la",
    explain = "<leader>le",
    refactor = "<leader>lr",
    optimize = "<leader>lo",
    comment = "<leader>lc",
    chat = "<leader>ll",
    model = "<leader>lm"
  }
}

-- Current options
M.options = {}

-- Setup configuration
function M.setup(user_config)
  -- Merge user config with defaults
  M.options = vim.tbl_deep_extend("force", M.defaults, user_config or {})
  
  -- Validate configuration
  M.validate()
  
  -- Set up keymaps if enabled
  if M.options.keymaps then
    M.setup_keymaps()
  end
end

-- Validate configuration
function M.validate()
  if M.options.api_key == "" then
    vim.notify(
      "⚠️  LLM-Assist: API key not set!\n" ..
      "Please set LLM_API_KEY environment variable or configure in setup().",
      vim.log.levels.WARN
    )
  end
  
  if M.options.ca_bundle_path == "" then
    vim.notify(
      "⚠️  LLM-Assist: CA bundle path not set!\n" ..
      "Please set LLM_CA_BUNDLE environment variable or configure in setup().",
      vim.log.levels.WARN
    )
  end
  
  -- Check if CA bundle exists
  if M.options.ca_bundle_path ~= "" then
    local expanded_path = vim.fn.expand(M.options.ca_bundle_path)
    local f = io.open(expanded_path, "r")
    if not f then
      vim.notify(
        "⚠️  LLM-Assist: CA bundle file not found at: " .. expanded_path,
        vim.log.levels.WARN
      )
    else
      f:close()
    end
  end
end

-- Setup keymaps
function M.setup_keymaps()
  local keymaps = M.options.keymaps
  
  if keymaps.ask then
    vim.keymap.set('n', keymaps.ask, ':LLMAsk<CR>', { desc = 'LLM: Ask question' })
  end
  
  if keymaps.explain then
    vim.keymap.set('v', keymaps.explain, ':LLMExplain<CR>', { desc = 'LLM: Explain code' })
  end
  
  if keymaps.refactor then
    vim.keymap.set('v', keymaps.refactor, ':LLMRefactor<CR>', { desc = 'LLM: Refactor code' })
  end
  
  if keymaps.optimize then
    vim.keymap.set('v', keymaps.optimize, ':LLMOptimize<CR>', { desc = 'LLM: Optimize code' })
  end
  
  if keymaps.comment then
    vim.keymap.set('v', keymaps.comment, ':LLMComment<CR>', { desc = 'LLM: Add comments' })
  end
  
  if keymaps.chat then
    vim.keymap.set('n', keymaps.chat, ':LLMChat<CR>', { desc = 'LLM: Open chat' })
  end
  
  if keymaps.model then
    vim.keymap.set('n', keymaps.model, ':LLMModels<CR>', { desc = 'LLM: List models' })
  end
end

return M
