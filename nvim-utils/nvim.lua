local utils = require('lua-utils')
local list = utils.list
local types = utils.types
local validate = utils.validate
local nvim = {}

function nvim.normal()
  vim.cmd.normal({ vim.fn.mode(), bang = true })
end

function nvim.region(as_list)
  as_list = ifnil(as_list, false)
  local esc = vim.api.nvim_replace_termcodes("<esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "x", false)
  local vstart = vim.fn.getpos("'<")
  local vend = vim.fn.getpos("'>")
  local ok, _region = pcall(vim.fn.getregion, vstart, vend, vim.empty_dict())

  if ok and _region then
    if as_list then
      return _region
    else
      return list.concat(_region, "\n")
    end
  end
end

function nvim.mode()
  return vim.fn.mode()
end

function nvim.in_visual_mode()
  local mode = nvim.mode()
  return mode == 'v' or mode == 'V' or mode == ''
end

function nvim.in_normal_mode()
  return nvim.mode() == 'n'
end

function nvim.with_region(fn, ...)
  local _region = nvim.region()
  if _region then
    return fn(_region, ...)
  end
end

function nvim.ls(dirname, fullname)
  local res = {}
  local abspath = fullname and vim.fs.abspath(dirname)
  for f in vim.fs.dir(dirname) do
    if fullname then
      res[#res+1] = abspath .. '/' .. f
    else
      res[#res+1] = f
    end
  end
  return res
end

function nvim.loadstring(s)
  local ok, msg = loadstring(s)
  if ok then
    return ok()
  else
    return false, msg
  end
end

function nvim.loadfile(f)
  local fh = io.open(f, 'r')
  if not fh then return end
  local lines = fh:read('*a')
  return nvim.loadstring(lines)
end

function nvim.require2path(require_string, dir)
  validate.require_string(require_string, 'string')
  validate.opt_runtimepath(dir, 'string')

  dir = ifnil(dir, vim.fn.stdpath('config')) .. '/lua'
  require_string = vim.split(require_string, '[.]')
  local path = list.join(list(dir, require_string), '/')

  return path
end

function nvim.path2require(path)
  validate.path(path, 'string')

  local config_path = vim.fn.stdpath('config')
  if not path:match(config_path) then
    return false
  elseif not path:match('.lua$') then
    return false
  else
    path = path:gsub(config_path .. '/lua/', '')
    path = vim.split(path, '/')
    local len = #path
    path[len] = path[len]:gsub('[.]lua', '')
    path = list.join(path, '.')
  end

  return path
end

function nvim.file_exists(file)
  return vim.fn.filereadable(file) == 1
end

function nvim.dir_exists(file)
  return vim.fn.isdirectory(file) == 1
end

function nvim.require_path(path)
  if not (nvim.file_exists(path) or nvim.dir_exists(path)) then
    return false
  else
    return require(nvim.path2require(path))
  end
end

function nvim.require(require_path, callback)
  local path = nvim.require2path(require_path)
  local luafile = paste0(path, '.lua')
  local dirfile = paste0(path, '/init.lua')
  local mod

  if nvim.file_exists(luafile) then
    mod = require(require_path)
  elseif nvim.dir_exists(dirfile) then
    mod = require(require_path)
  end

  if mod then
    return ifelse(callback, callback(mod), mod)
  else
    return false
  end
end

function nvim.input(prompt, on_input, on_nothing)
  vim.ui.input({prompt = prompt}, function (input)
    if not input then
      return false
    elseif #input > 0 then
      on_input(input)
    elseif on_nothing then
      on_nothing()
    end
  end)
end

function nvim.select(choices, prompt, on_choice, formatter)
  vim.ui.select(choices, {prompt = prompt, format_item = formatter}, on_choice)
end



return nvim
