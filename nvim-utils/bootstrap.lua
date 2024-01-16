require "lua-utils"

local setup = {}

function setup:setup_user_dirs(dir)
  dir = dir or user.user_dir or (os.getenv "HOME" .. "/.nvim/lua")

  user.user_dirs = {
    dir .. "/lua/user/?.lua",
    dir .. "/lua/user/?/?.lua",
  }

  local dirs = user.user_dirs
  for i = 1, #dirs do
    package.path = package.path .. ";" .. dirs[i]
  end
end

function setup:setup_luarocks(dir)
  local luarocks = dir or user.luarocks_dir or (os.getenv "HOME" .. "/" .. ".luarocks")

  user.luarocks_cpaths = {
    luarocks .. "/share/lua/5.1/?.so",
    luarocks .. "/lib/lua/5.1/?.so",
  }

  user.luarocks_paths = {
    luarocks .. "/share/lua/5.1/?.lua",
    luarocks .. "/share/lua/5.1/?/?.lua",
    luarocks .. "/share/lua/5.1/?/init.lua",
  }

  local cpaths = user.luarocks_cpaths
  local paths = user.luarocks_paths

  for i = 1, #cpaths do
    package.cpath = package.cpath .. ";" .. cpaths[i]
  end

  for i = 1, #paths do
    package.path = package.path .. ";" .. paths[i]
  end
end

function setup:clone_lazy(lazypath)
  lazypath = lazypath or user.lazy_path or (vim.fn.stdpath "data" .. "/lazy/lazy.nvim")
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
  json = {
    encode = vim.fn.json_encode,
    decode = vim.fn.json_decode,
  }

  opts = opts or {}
  user = user or {}
  if opts.lazy then
    self:clone_lazy(opts.lazy_path)
  end

  if opts.setup_user_dirs then
    self:setup_user_dirs(opts.user_dir)
  end

  if opts.setup_luarocks then
    self:setup_luarocks(opts.user_dir)
  end
end

return setup
