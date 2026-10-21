-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

local opt = vim.opt

opt.relativenumber = true     -- relative line numbers (great for motions)
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.wrap = false
opt.clipboard = "unnamedplus" -- use system clipboard
opt.cursorline = true
opt.colorcolumn = "120"
