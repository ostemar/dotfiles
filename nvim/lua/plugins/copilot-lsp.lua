return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        copilot = {
          cmd = { "copilot-language-server" },
          filetypes = { "*" }, -- enable everywhere (recommended for Sidekick)
        },
      },
    },
  },
}
