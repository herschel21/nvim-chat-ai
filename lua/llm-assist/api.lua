local M = {}
local config = require('llm-assist.config')

-- Job handle for cancellation
local current_job = nil

-- Ask model a question
function M.ask_model(model_name, question, callback, system_prompt)
  local opts = config.options
  
  -- Use provided system prompt or default
  system_prompt = system_prompt or opts.system_prompts.default
  
  -- Prepare payload
  local payload = {
    model = model_name,
    messages = {
      { role = "system", content = system_prompt },
      { role = "user", content = question }
    },
    temperature = opts.temperature,
    max_tokens = opts.max_tokens,
    stream = opts.stream
  }
  
  -- Prepare headers
  local headers = {
    "Authorization: Bearer " .. opts.api_key,
    "Content-Type: application/json"
  }
  
  -- Expand CA bundle path
  local ca_bundle = vim.fn.expand(opts.ca_bundle_path)
  
  -- Convert payload to JSON
  local json_payload = vim.fn.json_encode(payload)
  
  -- Prepare curl command
  local url = opts.api_base .. "/api/chat/completions"
  local cmd = {
    "curl",
    "-s",
    "-X", "POST",
    url,
    "--cacert", ca_bundle,
    "--max-time", tostring(opts.timeout),
    "-H", headers[1],
    "-H", headers[2],
    "-d", json_payload
  }
  
  -- Execute curl command
  local output = {}
  local job_opts = {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(output, line)
          end
        end
      end
    end,
    on_exit = vim.schedule_wrap(function(_, exit_code)
      current_job = nil
      
      if exit_code == 0 then
        local response_body = table.concat(output, "\n")
        
        -- Parse JSON response
        local ok, data = pcall(vim.fn.json_decode, response_body)
        if ok and data.choices and data.choices[1] then
          local content = data.choices[1].message.content
          callback(content, nil)
        else
          -- Try to get error message from response
          local error_msg = "Failed to parse response"
          if ok and data.error then
            error_msg = data.error.message or vim.inspect(data.error)
          end
          callback(nil, error_msg)
        end
      else
        local error_body = table.concat(output, "\n")
        local error_msg = string.format("HTTP request failed (exit code %d)", exit_code)
        
        -- Try to extract more specific error
        if error_body:match("SSL") or error_body:match("certificate") then
          error_msg = "SSL/Certificate error. Check your CA bundle path."
        elseif error_body:match("timeout") then
          error_msg = "Request timed out after " .. opts.timeout .. "s"
        elseif error_body:match("Connection refused") then
          error_msg = "Connection refused. Check API base URL."
        elseif error_body ~= "" then
          -- Try to parse error response
          local ok, data = pcall(vim.fn.json_decode, error_body)
          if ok and data.error then
            error_msg = data.error.message or vim.inspect(data.error)
          end
        end
        
        callback(nil, error_msg)
      end
    end)
  }
  
  current_job = vim.fn.jobstart(cmd, job_opts)
  
  if current_job <= 0 then
    callback(nil, "Failed to start curl command")
  end
end

-- Test connection to API
function M.test_connection(callback)
  local opts = config.options
  local ca_bundle = vim.fn.expand(opts.ca_bundle_path)
  
  -- Simple request to check connection
  local cmd = {
    "curl",
    "-s",
    "-w", "\n%{http_code}",
    "-X", "GET",
    opts.api_base .. "/api/models",
    "--cacert", ca_bundle,
    "--max-time", "10",
    "-H", "Authorization: Bearer " .. opts.api_key
  }
  
  local output = {}
  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(output, line)
          end
        end
      end
    end,
    on_exit = vim.schedule_wrap(function(_, exit_code)
      if exit_code == 0 and #output > 0 then
        -- Last line should be HTTP status code
        local http_code = tonumber(output[#output])
        if http_code and http_code >= 200 and http_code < 300 then
          callback(true, "Connection successful! API is reachable.")
        else
          callback(false, "API returned HTTP " .. (http_code or "unknown"))
        end
      else
        local error_msg = "Connection failed"
        local error_body = table.concat(output, "\n")
        
        if error_body:match("SSL") or error_body:match("certificate") then
          error_msg = "SSL/Certificate error. Check your CA bundle path: " .. ca_bundle
        elseif error_body:match("Could not resolve host") then
          error_msg = "Could not resolve host. Check API base URL."
        elseif error_body:match("Connection refused") then
          error_msg = "Connection refused. Server may be down or unreachable."
        end
        
        callback(false, error_msg)
      end
    end)
  })
end

-- Cancel current request
function M.cancel()
  if current_job and current_job > 0 then
    vim.fn.jobstop(current_job)
    current_job = nil
    return true
  end
  return false
end

return M
