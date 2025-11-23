return {
  -- Mason configuration for LSP, DAP, linters, and formatters
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = {
        -- Shell/Bash support
        "bash-language-server",
        "shellcheck",
        "shfmt",

        -- Lua (LazyVim defaults, but explicit is good)
        "lua-language-server",
        "stylua",

        -- Markdown extras
        "markdown-toc",

        -- F# support
        "fsautocomplete",
        "fantomas",

        -- XML support
        "xmlformatter",

        -- Tree-sitter CLI
        "tree-sitter-cli",
      },
    },
  },
}
