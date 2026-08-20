require 'nvim-utils.state'
local list = require 'lua-utils.list'
local path_utils = require 'lua-utils.path_utils'
local autocmd = vim.api.nvim_create_autocmd

runtimepath = vim.opt.runtimepath

---@class user_config.pkgs.config
---@field name string
---@field defaults user_config.pkgs.config
---@field dir string
---@field repo string
user_config.pkgs = user_config.pkgs or {}
user_config.pkgs.name = 'lazy'
user_config.pkgs.repo = "https://github.com/folke/lazy.nvim"
user_config.pkgs.dir = user_config.path.dir.pkgs
user_config.pkgs.opts = {
  spec = { { import = "pkgs" }, },
  install = { colorscheme = { "habamax" } },
  checker = { enabled = false },
  lazy = false,
}

local pkgs = user_config.pkgs

---Install lazy.nvim. Will be run at startup
function pkgs:install()
  local lazypath = self.dir
  if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local lazyrepo = self.repo
    local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
    if vim.v.shell_error ~= 0 then
      vim.api.nvim_echo({
        { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
        { out,                            "WarningMsg" },
        { "\nPress any key to exit..." },
      }, true, {})
      vim.fn.getchar()
      os.exit(1)
    end
  end
end

---@class pkgs.git_clone.specs
---@field [1] string
---@field [2] string

---@class pkgs.git_clone.opts
---@field append? boolean
---@field prepend? boolean
---@field args? string[]

---@param specs table<string,pkgs.git_clone.specs>
---@param opts? pkgs.git_clone.opts
function pkgs:git_clone(specs, opts)
  opts = opts or {}
  local append = opts.append
  local prepend = opts.prepend
  local args = opts.args or {}

  if append == nil and prepend == nil then
    prepend = true
  end

  for _, spec in ipairs(specs) do
    local repo, dst = unpack(spec)
    repo = "https://www.github.com/" .. repo
    dst = self.dir .. '/' .. dst
    local cmd = list.flatten {"git", "clone", repo, args, dst}

    if not path_utils.is_dir(dst) then
      local msg = vim.fn.system(cmd)
      if vim.v.shell_error == 0 then
        nvim.msg_ok("OK: %s -> %s", repo, dst)
        if append then
          self:rtp_append({dst})
        else
          self:rtp_prepend({dst})
        end
      else
        nvim.msg_fatal("Could not clone hard dependency: %s\nError: %s", repo, msg or '')
        vim.fn.getchar()
        os.exit(1)
      end
    end
  end
end

function pkgs:rtp_append(...)
  for _, p in ipairs {...} do
    vim.opt.rtp:append(p)
  end
end

function pkgs:rtp_prepend(...)
  for _, p in ipairs {...} do
    vim.opt.rtp:prepend(p)
  end
end

pkgs.rtp_push    = pkgs.rtp_append
pkgs.rtp_unpush  = pkgs.rtp_prepend
pkgs.rtp_lappend = pkgs.rtp_prepend

function pkgs.setup(overrides)
  local self = pkgs
  self:rtp_prepend(self.dir)
  self:install()
  self:git_clone {
    { "nvim-telescope/telescope.nvim",         "nvim-telescope" },
    { "nvim-telescope/telescope-project.nvim", "nvim-telescope-project" },
    { "nvim-telescope/telescope-file-browser.nvim", "nvim-telescope-filebrowser" },
    { "nvim-lua/plenary.nvim",                 "nvim-plenary" },
  }

  local opts = vim.deepcopy(self.opts, overrides or {})
  vim.g.mapleader = " "
  vim.g.maplocalleader = '\\'

  -- autocmd(
  --   "VimEnter", 
  --   {
  --     callback = function (_)
  --       require("lazy").setup(opts)
  --     end, 
  --     pattern = "*",
  --     desc = "Setup pkgs"
  --   }
  -- )
  --
  require("lazy").setup(opts)
end

return pkgs
