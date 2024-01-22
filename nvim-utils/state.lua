require "lua-utils"

if user and not is_empty(user) then
  return user
end

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

local _winapi = {}
local _bufapi = {}
local _api = {}
local _create = {}
local _del = {}
local _list = {}
local _tabpage = {}
local _get = {}
local _set = {}

dict.each(vim.api, function(key, value)
  if key:match "^nvim_buf" then
    key = key:gsub("^nvim_buf_", "")
    _bufapi[key] = value
  elseif key:match "^nvim_win" then
    key = key:gsub("^nvim_win_", "")
    _winapi[key] = value
  elseif key:match "nvim_list" then
    _list[(key:gsub("^nvim_list_", ""))] = value
  elseif key:match "nvim_del_" then
    _del[(key:gsub("^nvim_del_", ""))] = value
  elseif key:match "^nvim_tabpage" then
    _tabpage[(key:gsub("^nvim_tabpage_", ""))] = value
  elseif key:match "^nvim_get" then
    _get[(key:gsub("^nvim_get_", ""))] = value
  elseif key:match "^nvim_set" then
    _set[(key:gsub("^nvim_set_", ""))] = value
  elseif key:match "nvim_create" then
    _create[(key:gsub("^nvim_create_", ""))] = value
  elseif key:match "^nvim_" then
    _api[(key:gsub("^nvim_", ""))] = value
  end
end)

_api.win = _winapi
_api.buf = _bufapi
_api.del = _del
_api.list = _list
_api.create = _create
_api.tabpage = _tabpage
_api.set = _set
_api.get = _get

nvim = _api
nvim = mtset(nvim, {
  __index = function(self, fn)
    return vim.fn[fn] or vim[fn]
  end,
})

--------------------------------------------------
function vimsize()
  local scratch = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_call(scratch, function()
    vim.cmd "tabnew"
    local tabpage = vim.fn.tabpagenr()
    width = vim.fn.winwidth(0)
    height = vim.fn.winheight(0)
    vim.cmd("tabclose " .. tabpage)
  end)

  vim.cmd(":bwipeout! " .. scratch)

  return { width, height }
end

function tostderr(...)
  for _, s in ipairs { ... } do
    s = not is_string(s) and dump(s) or s
    vim.api.nvim_err_writeln(s)
  end
end

function nvimexec(s, as_string)
  local ok, res = pcall(vim.api.nvim_exec2, s, { output = true })
  if ok and res and res.output then
    return not as_string and strsplit(res.output, "\n") or res.output
  end
end

function system(...)
  return vim.fn.systemlist(...)
end

function requirex(require_string)
  local ok, msg = pcall_warn(require, require_string)

  if not ok then
    return ok, msg
  else
    return ok
  end
end

function glob(d, expr, nosuf, alllinks)
  nosuf = nosuf == nil and true or false
  return vim.fn.globpath(d, expr, nosuf, true, alllinks) or {}
end

--- Only works for user and doom dirs
function whereis(bin)
  local out = vim.fn.system("whereis " .. bin .. [[ | cut -d : -f 2- | sed -r "s/(^ *| *$)//mg"]])

  out = trim(out)
  out = strsplit(out, " ")

  if is_empty(out) then
    return false
  end

  return out
end

function req2path(s, isfile)
  local p = strsplit(s, "[./]") or { s }
  local test

  if p[1]:match "user" then
    test = Path.join(user.paths.user, "lua", unpack(p))
  else
    test = Path.join(user.paths.config, "lua", unpack(p))
  end

  local isdir = Path.exists(test)
  isfile = Path.exists(test .. ".lua")

  if isfile and isfile then
    return test .. ".lua", "file"
  elseif isdir then
    return test, "dir"
  elseif isfile then
    return test .. ".lua", "file"
  end
end

function loadfilex(path)
  local ok, msg = loadfile(path)
  if not ok then
    logger:warn(msg)
  end

  return ok--[[@as function]]()
end

function reqloadfile(path)
  path = req2path(path)

  if not path then
    return
  end

  return loadfile(path)
end

function reqloadfilex(path)
  path = req2path(path)
  if not path then
    return
  end

  return loadfilex(path)
end

function getpid(pid)
  if not is_number(pid) then
    return false
  end

  local out = system("ps --pid " .. pid .. " | grep -Ev 'PID TTY'")
  out = list.map(out, trim)
  out = list.filter(out, function(x)
    return #x ~= 0
  end)

  if #out > 0 then
    if string.match(out[1], "error") then
      return false, out
    end

    return true
  end

  return false
end

function killpid(pid, signal)
  if not is_number(pid) then
    return false
  end

  signal = signal or ""
  local out = system("kill -s " .. signal .. " " .. pid)
  if #out == 0 then
    return false
  else
    return false
  end

  return true
end

function mkcommand(name, callback, opts)
  opts = copy(opts or {})
  local use = vim.api.nvim_create_user_command
  local buf

  if opts.buffer then
    buf = opts.buffer == true and buffer.current() or opts.buffer
    use = vim.api.nvim_buf_create_user_command
  end

  opts.buffer = nil
  if buf then
    return use(buf, name, callback, opts)
  end

  return use(name, callback, opts)
end

function require_merge(...)
  local out = {}
  local req_paths = {...}

  for i = 1, #req_paths do
    local res = requirex(req_paths[i])
    if res then
      dict.merge2(out, res)
    end
  end

  return out
end

--------------------------------------------------
require "nvim-utils.logger"
--------------------------------------------------

return user
