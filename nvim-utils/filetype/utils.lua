#!/usr/bin/env luajit

require 'nvim-utils.filetype.filetype'
require 'lua-utils.dump'

local path_utils = require 'lua-utils.path_utils'

---Other class methods and static methods
filetype.utils = {}
local utils = filetype.utils

---@param ... []string|string|number
---@return any
function utils.get(...)
  local ks = list.flatten { ... }
  return dict.get(user_config.filetype, ks)
end

---@param bufnr? number
---@param ... []string|string|number
---@return any
function utils.buffer_get(bufnr, ...)
  bufnr = bufnr or vim.fn.bufnr()
  local ks = list.flatten({ bufnr }, { ... })

  return buffer.get_id(bufnr, {
    ok = function(buf)
      return utils.get(buf, ks)
    end,
    err = function(msg)
      return msg
    end
  })
end

---@param ft string
---@return filetype?
function utils.exists(ft)
  return user_config.filetype[ft]
end

---@return []string
function utils.list_builtin()
  local ft_path = user_config.path.dir.filetype
  local ft_paths = path_utils.glob(ft_path .. '/*.lua')
  local res = {}

  for _, path in ipairs(ft_paths) do
    local ft = path_utils.basename(path):gsub('%.lua$', '')
    res[#res + 1] = ft
  end

  return res
end

---@return table<string,filetype>
function utils.setup_builtin()
  local res = {}

  for _, ft in ipairs(utils.list_builtin()) do
    local x = filetype(ft)
    x:setup()
    res[x.name] = x
  end

  return res
end
