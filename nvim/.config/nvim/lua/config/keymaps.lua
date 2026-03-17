-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Copy current file path to clipboard (<leader>cp as backup for langs that override <leader>cc)
local function copy_file_path()
  local path = vim.fn.expand("%:p")
  vim.fn.setreg("+", path)
  vim.notify(path, vim.log.levels.INFO, { title = "Copied path" })
end
vim.keymap.set("n", "<leader>cc", copy_file_path, { desc = "Copy file path" })
vim.keymap.set("n", "<leader>cp", copy_file_path, { desc = "Copy file path" })

-- Copy current file directory to clipboard
vim.keymap.set("n", "<leader>cd", function()
  local dir = vim.fn.expand("%:p:h")
  vim.fn.setreg("+", dir)
  vim.notify(dir, vim.log.levels.INFO, { title = "Copied directory" })
end, { desc = "Copy file directory" })

-- Preview current file in default system viewer
vim.keymap.set("n", "<leader>p", function()
  local cmd = vim.fn.has("macunix") == 1 and "open" or "xdg-open"
  vim.fn.jobstart({ cmd, vim.fn.expand("%:p") })
end, { desc = "Preview file" })

-- Send deletes to black hole register so they don't clobber the clipboard
vim.keymap.set("n", "d", '"_d', { desc = "Delete to black hole" })
vim.keymap.set("n", "dd", '"_dd', { desc = "Delete line to black hole" })
vim.keymap.set("n", "D", '"_D', { desc = "Delete to end to black hole" })
vim.keymap.set("n", "x", '"_x', { desc = "Delete char to black hole" })
vim.keymap.set("x", "d", '"_d', { desc = "Delete to black hole (visual)" })
vim.keymap.set("x", "p", '"_dP', { desc = "Paste over selection without yanking" })

-- Cycle through buffers
vim.keymap.set("n", "<Tab>", ":bnext<CR>", { desc = "Next buffer" })
vim.keymap.set("n", "<S-Tab>", ":bprev<CR>", { desc = "Previous buffer" })
