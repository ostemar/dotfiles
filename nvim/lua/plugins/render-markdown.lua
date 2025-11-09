return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      render_modes = { "n", "c", "t" },
      code = {
        sign = false,
        width = "block",
        right_pad = 1,
        -- background = "red",
      },
      heading = {
        sign = false,
        icons = {},
      },
      checkbox = {
        enabled = true,
      },
    },
    config = function(_, opts)
      --     Remove the background for inline code
      -- Do this BEFORE setup so our value wins over the plugin's default link
      -- Works in GUI and terminal (cterm) UIs
      vim.api.nvim_set_hl(0, "RenderMarkdownCodeInline", { bg = "NONE", ctermbg = "NONE" })
      -- (optional) also make the inline highlight (the text itself) not force any bg
      vim.api.nvim_set_hl(0, "RenderMarkdownInlineHighlight", { bg = "NONE", ctermbg = "NONE" })

      require("render-markdown").setup(opts)
    end,
  },
}
