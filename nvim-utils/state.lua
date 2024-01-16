require "lua-utils"

local data_dir = vim.fn.stdpath "data"
local dir = vim.fn.stdpath "config"
local user_dir = table.concat({ os.getenv "HOME", ".nvim" }, "/")
local plugins_dir = table.concat({ data_dir, "lazy" }, "/")
local log_path = table.concat({ data_dir, "messages" }, "/")

local paths = {
  config = dir,
  user = user_dir,
  data = data_dir,
  plugins = plugins_dir,
  logs = log_path,
  servers = table.concat({ data_dir, "lsp-servers" }, "/"),
}

user = {
  plugins = { exclude = {} },
  jobs = {},
  filetypes = {},
  buffers = {},
  terminals = {},
  kbds = {},
  repls = {},
  bookmarks = {},
  autocmds = {},
  buffer_groups = {},
  paths = paths,
  user_dir = (os.getenv "HOME" .. "/.nvim/lua"),
  luarocks_dir = (os.getenv "HOME" .. "/" .. ".luarocks"),
  lazy_path = (vim.fn.stdpath "data" .. "/lazy/lazy.nvim"),
}

local winapi = {}
local bufapi = {}
local api = {}
local create = {}
local del = {}
local list = {}
local tabpage = {}
local get = {}
local set = {}

dict.each(vim.api, function(key, value)
  if key:match "^nvim_buf" then
    key = key:gsub("^nvim_buf_", "")
    bufapi[key] = value
  elseif key:match "^nvim_win" then
    key = key:gsub("^nvim_win_", "")
    winapi[key] = value
  elseif key:match "nvim_list" then
    list[(key:gsub("^nvim_list_", ""))] = value
  elseif key:match "nvim_del_" then
    del[(key:gsub("^nvim_del_", ""))] = value
  elseif key:match "^nvim_tabpage" then
    tabpage[(key:gsub("^nvim_tabpage_", ""))] = value
  elseif key:match "^nvim_get" then
    get[(key:gsub("^nvim_get_", ""))] = value
  elseif key:match "^nvim_set" then
    set[(key:gsub("^nvim_set_", ""))] = value
  elseif key:match "nvim_create" then
    create[(key:gsub("^nvim_create_", ""))] = value
  elseif key:match "^nvim_" then
    api[(key:gsub("^nvim_", ""))] = value
  end
end)

api.win = winapi
api.buf = bufapi
api.del = del
api.list = list
api.create = create
api.tabpage = tabpage
api.set = set
api.get = get

nvim = api
nvim = mtset(nvim, {
  __index = function(self, fn)
    return vim.fn[fn] or vim[fn]
  end,
})
