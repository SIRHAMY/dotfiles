return {
  {
    "saghen/blink.cmp",
    opts = {
      enabled = function()
        local disabled_filetypes = { "markdown" }
        return not vim.tbl_contains(disabled_filetypes, vim.bo.filetype)
      end,
    },
  },
}
