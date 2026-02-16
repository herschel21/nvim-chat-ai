return {
  "herschel21/llm-assist.nvim",
  config = function()
    require('llm-assist').setup()
  end
}
-- OR 

return {
    dir = '~/workspace/learning/nvim-chat-ai/',  -- Local path
    config = function()
        require('llm-assist').setup()
    end
}

