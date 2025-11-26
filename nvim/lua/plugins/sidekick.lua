return {
  "folke/sidekick.nvim",
  opts = {
    cli = {
      mux = { enabled = false }, -- Windows-safe, disables zellij/tmux
    },
  },
  --   keys = {
  --     -- nes is also useful in normal mode
  --     { "<tab>", LazyVim.cmp.map({ "ai_nes" }, "<tab>"), mode = { "n" }, expr = true },
  --     { "<leader>a", "", desc = "+ai", mode = { "n", "v" } },
  --     {
  --       "<c-.>",
  --       function()
  --         require("sidekick.cli").toggle()
  --       end,
  --       desc = "Sidekick Toggle",
  --       mode = { "n", "t", "i", "x" },
  --     },
  --     {
  --       "<leader>aa",
  --       function()
  --         require("sidekick.cli").toggle()
  --       end,
  --       desc = "Sidekick Toggle CLI",
  --     },
  --   },
}
