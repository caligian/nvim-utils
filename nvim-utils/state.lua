require "lua-utils"
require "nvim-utils.Path"
require "nvim-utils.logger"

schedule = vim.schedule
schedule_wrap = vim.schedule_wrap

function err_writeln(...)
  local args = {...}

  for i = 1, #args do
    if is_number(args[i]) then
      args[i] = tostring(args[i])
    elseif not is_string(args[i]) then
      args[i] = dump(args[i])
    end
  end

  vim.api.nvim_err_writeln(join(args, "\n"))
end

function is_path(x)
  local x = vim.loop.fs_stat(x)
  if not x then
    return
  end

  if x.type == "directory" then
    return x, "dir"
  end

  return x, "file"
end

function is_dir(x)
  local ok, tp = is_path(x)
  if ok and tp == "dir" then
    return x
  end
end

function is_file(x)
  local ok, tp = is_path(x)
  if ok and tp == "file" then
    return x
  end
end

--------------------------------------------------
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

user = user
  or {
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

--- @param x string require path. errors will be logged
--- @param cb? function callback
--- @param on_fail? function callback on failure
--- @return any, string?
function requirex_if(x, cb, on_fail)
  local ok, msg = pcall(require, x)
  if not ok then
    if msg then
      logger:warn(msg)
    end

    if on_fail then
      return on_fail(msg)
    end

    return nil, msg
  elseif cb then
    return cb(msg)
  else
    return msg
  end
end

--- @param x string require path
--- @param cb? function callback
--- @param on_fail? function callback on failure
--- @return any?, string?
function require_if(x, cb, on_fail)
  local ok, msg = pcall(require, x)
  if not ok then
    if on_fail then
      return on_fail(msg)
    end

    return nil, msg
  elseif cb then
    return cb(msg)
  else
    return msg
  end
end

requirex = require_if

function require_config(default)
  assert_is_a.string(default)

  local utils_require_path = "nvim-utils.defaults." .. default
  local core_require_path = "core.defaults." .. default
  local user_require_path = 'user.defaults.' .. default
  local user_path = Path.join(user.paths.user, 'lua', 'user', 'defaults', default .. '.lua')
  local core_path = Path.join(user.paths.config, 'lua', 'core', 'defaults', default .. '.lua')
  local user_conf = is_file(user_path) and requirex(user_require_path)
  local core_conf = is_file(core_path) and requirex(core_require_path)
  local utils_conf = requirex(utils_require_path) or {}

  if core_conf and user_conf then
    return dict.merge(utils_conf, core_conf, user_conf)
  elseif core_conf then
    return dict.merge(utils_conf, core_conf)
  elseif user_conf then
    return dict.merge(utils_conf, user_conf)
  elseif not is_empty(utils_conf) then
    return utils_conf
  end
end

function require_plugin(plugin)
  assert_is_a.string(plugin)

  local core_require_path = "core.plugins." .. plugin
  local user_require_path = 'user.plugins.' .. plugin
  local user_path = Path.join(user.paths.user, 'lua', 'user', 'plugins', plugin .. '.lua')
  local core_path = Path.join(user.paths.config, 'lua', 'core', 'plugins', plugin .. '.lua')
  local user_conf = is_file(user_path) and requirex(user_require_path)
  local core_conf = is_file(core_path) and requirex(core_require_path)
  
  if not core_conf then
    core_conf = is_file(core_path:gsub('%.lua', '/init.lua')) and requirex(core_require_path)
  end

  if not user_conf then
    user_conf = is_file(user_path:gsub('%.lua', '/init.lua')) and requirex(user_require_path)
  end

  if core_conf and user_conf then
    return dict.merge(core_conf, user_conf)
  elseif core_conf then
    return core_conf
  end

  return user_conf
end

function require_ftconfig(ft)
  assert_is_a.string(ft)

  local core_require_path = "core.ft." .. ft
  local user_require_path = 'user.ft.' .. ft
  local user_path = Path.join(user.paths.user, 'lua', 'user', 'ft', ft .. '.lua')
  local core_path = Path.join(user.paths.config, 'lua', 'core', 'ft', ft .. '.lua')
  local user_conf = is_file(user_path) and requirex(user_require_path)
  local core_conf = is_file(core_path) and requirex(core_require_path)

  if core_conf and user_conf then
    return dict.merge(core_conf, user_conf)
  elseif core_conf then
    return core_conf
  end

  return user_conf
end

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

function loadfilex(path)
  local ok, msg = loadfile(path)
  if not ok then
    logger:warn(msg)
  end

  return ok--[[@as function]]()
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
  local req_paths = { ... }

  for i = 1, #req_paths do
    local res = requirex(req_paths[i])
    if res then
      dict.merge(out, res)
    end
  end

  return out
end

--------------------------------------------------

return user
