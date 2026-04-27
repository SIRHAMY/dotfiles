-- Reclaim <leader>cc from rustaceanvim's CodeLens override
vim.keymap.set("n", "<leader>cc", function()
  local path = vim.fn.expand("%:p")
  vim.fn.setreg("+", path)
  vim.notify(path, vim.log.levels.INFO, { title = "Copied path" })
end, { buffer = true, desc = "Copy file path" })
