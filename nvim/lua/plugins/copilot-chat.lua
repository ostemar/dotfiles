return {
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    enabled = false,
    -- keys = {
    --   { "<c-s>", "<CR>", ft = "copilot-chat", desc = "Submit Prompt", remap = true },
    --   { "<leader>a", "", desc = "+ai", mode = { "n", "x" } },
    --   {
    --     "<leader>ac",
    --     function()
    --       return require("CopilotChat").toggle()
    --     end,
    --     desc = "Copilot Chat",
    --     mode = { "n", "x" },
    --   },
    --   {
    --     "<leader>ax",
    --     function()
    --       return require("CopilotChat").reset()
    --     end,
    --     desc = "Copilot Clear",
    --     mode = { "n", "x" },
    --   },
    --   {
    --     "<leader>aq",
    --     function()
    --       vim.ui.input({
    --         prompt = "Quick Chat: ",
    --       }, function(input)
    --         if input ~= "" then
    --           require("CopilotChat").ask(input)
    --         end
    --       end)
    --     end,
    --     desc = "Copilot Quick Chat",
    --     mode = { "n", "x" },
    --   },
    --   {
    --     "<leader>ap",
    --     function()
    --       require("CopilotChat").select_prompt()
    --     end,
    --     desc = "Copilot Prompt Actions",
    --     mode = { "n", "x" },
    --   },
    -- },
  },
}
