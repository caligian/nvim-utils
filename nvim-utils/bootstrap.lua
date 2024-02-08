require "lua-utils"

local setup = {}

function setup:setup_luarocks()
  local luarocks = self.luarocks_dir
  user.luarocks_dir = luarocks
  user.luarocks_paths = {
    luarocks .. "/share/lua/5.1/?.so",
    luarocks .. "/lib/lua/5.1/?.so",
  }
  user.luarocks_cpaths = {
    luarocks .. "/share/lua/5.1/?.lua",
    luarocks .. "/share/lua/5.1/?/?.lua",
    luarocks .. "/share/lua/5.1/?/init.lua",
  }

  local paths = user.luarocks_paths
  local cpaths = user.luarocks_cpaths

  for i = 1, #cpaths do
    local cpath = cpaths[i]
    package.cpath = package.cpath .. ";" .. cpath
  end

  for i = 1, #paths do
    local path = paths[i]
    vim.opt.rtp:prepend(path)
  end
end

function setup:clone_lazy()
  local lazypath = self.lazy_path
  local exists = vim.loop.fs_stat(lazypath)

  if not exists then
    vim.fn.system {
      "git",
      "clone",
      "--filter=blob:none",
      "https://github.com/folke/lazy.nvim.git",
      "--branch=stable",
      lazypath,
    }
  end

  vim.opt.rtp:prepend(lazypath)

  local ok = pcall(require, "lazy")
  if not ok then
    error "Could not install lazy.nvim"
  end
end

function setup:setup(opts)
  opts = opts or {}
  user = user or {}

  form[{
    opt_lazy = { opt_enable = "boolean", opt_path = "string" },
    opt_luarocks = { opt_enable = "boolean", opt_path = "string" },
  }].options(opts)

  local lazy = opts.lazy
  if lazy and lazy.enable then
    self.lazy_path = lazy.path or (vim.fn.stdpath "data" .. "/lazy/lazy.nvim")
    self:clone_lazy()
  end

  local luarocks = opts.luarocks
  if luarocks and luarocks.enable then
    self.luarocks_dir = luarocks.path or (os.getenv "HOME" .. ".luarocks")
    self:setup_luarocks()
  end
end

return setup
