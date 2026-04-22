-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.opt.tabstop = 4 -- A TAB character looks like 4 spaces
vim.opt.expandtab = true -- Pressing the TAB key will insert spaces instead of a TAB character
vim.opt.softtabstop = 4 -- Number of spaces inserted instead of a TAB character
vim.opt.shiftwidth = 4 -- Number of spaces inserted when indenting

--OS detection
local mySysname = vim.loop.os_uname().sysname
local isMac = mySysname == "Darwin"
local isLinux = mySysname == "Linux"
local isWin = mySysname:find("Windows") and true or false
local isWsl = isLinux and vim.loop.os_uname().release:find("Microsoft") and true or false

--Set shell
if isWin then
  local bash_path = "C:\\Progra~1\\Git\\bin\\bash.exe"
  if vim.fn.executable(bash_path) == 1 then
    vim.opt.shell = bash_path
    vim.opt.shellcmdflag = "-c"
    vim.opt.shellxquote = '"'
    vim.opt.shellslash = false
  elseif vim.fn.executable("pwsh") == 1 then
    vim.opt.shell = "pwsh" --"pwsh" for 7.x if installed
  else
    vim.opt.shell = "powershell" --"powershell" for 5.x
  end
end
