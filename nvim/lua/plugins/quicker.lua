return {
  {
    "stevearc/quicker.nvim",
    ft = "qf",
    opts = {
      -- You can put configuration options here if you want
    },
    keys = {
      -- These mappings work inside the quickfix (qf) window
      {
        "<leader>qo",
        function()
          require("quicker").expand()
        end,
        ft = "qf",
        desc = "Quicker: expand item",
      },
      {
        "<leader>qc",
        function()
          require("quicker").collapse()
        end,
        ft = "qf",
        desc = "Quicker: collapse item",
      },
      {
        "<leader>qa",
        function()
          require("quicker").toggle()
        end,
        ft = "qf",
        desc = "Quicker: toggle expand/collapse",
      },

      -- Jump between entries (uses quicker’s smarter movement)
      {
        "]q",
        function()
          require("quicker").next()
        end,
        ft = "qf",
        desc = "Quicker: next item",
      },
      {
        "[q",
        function()
          require("quicker").prev()
        end,
        ft = "qf",
        desc = "Quicker: previous item",
      },

      -- Open preview window
      {
        "p",
        function()
          require("quicker").preview()
        end,
        ft = "qf",
        desc = "Quicker: preview",
      },
    },
  },
}
