if user_config == nil then
  local path = require 'lua-utils.path_utils'
  local dict = require 'lua-utils.dict'
  local root_dir = vim.fn.stdpath('config')
  local data_dir = vim.fn.stdpath('data')
  local lua_dir = root_dir .. '/lua'
  local config_dir = lua_dir .. '/config'
  local plugins_dir = config_dir .. '/plugins'
  local filetype_dir = config_dir .. '/filetype'
  local keymap_file = config_dir .. '/keymap.lua'
  local autocmd_file = config_dir .. '/autocmd.lua'
  local template_dir = root_dir .. '/templates'
  local settings_dir = root_dir .. '/settings.lua' 

  user_config = bless {
    keymap = {}, augroup = {}, autocmd = {}, filetype = {},
    buffer = { buffer_group = {}, recent = {} }, buffer_group = {},
    workspace = {}, project = {}, terminal = {}, 
    repl = {repl = {}, shell = {}, sh = false},
    path = {file = {}, dir = {}, project = {}},
    telescope = {
      theme = 'ivy', disable_devicons = true,
      previewer = false, layout_config = {height = 13} 
    },
    shell_command = 'bash',
    utils = {path = {}},
  }

  setmetatable(user_config.utils.path, user_config.utils.path)

  function user_config.utils.path:__index(path_type)
    if not path_type:match('_dir') then
      error('path_type: path key should end with _dir, using ' .. path_type)
    end

    local use = user_config.path[path_type]
    assert(use ~= nil, path_type .. ': no such path exists in user_config.path')

    return function(...)
      return path(use, ...)
    end
  end

  function user_config.utils.path:__call(...)
    return path(paths.root_dir, ...)
  end

  user_config.path = {
    root_dir = root_dir,
    data_dir = data_dir,
    lua_dir = lua_dir,
    config_dir = config_dir,
    filetype_dir = filetype_dir,
    template_dir = template_dir,
    keymap_file = keymap_file,
    autocmd_file = autocmd_file,
    settings_file = settings_file,
    plugins_dir = plugins_dir,
  }

  user_config.path.file = {
    keymap = keymap_file,
    autocmd = autocmd_file,
    settings = settings_file,
  }

  user_config.path.dir = {
    root = root_dir,
    data = data_dir,
    lua = lua_dir,
    config = config_dir,
    filetype = filetype_dir,
    template = template_dir,
    plugins = plugin_dir,
  }

  function user_config:set(keys, value, force)
    return dict.set(self, keys, value, force)
  end

  function user_config:get(keys, default)
    local value, level = dict.get(self, keys)
    if value ~= nil then
      return value, level
    elseif default then
      return default(), level
    else
      return nil, level
    end
  end
end

if user_state == nil then
  ----Just UID -> obj
  ---This is basically a reverse lookup table for objects
  user_state = {
    autocmd = {}, buffer_group = {},
    terminal = {}, repl = {},
    keymap = {},
    filetype = {},
  }

  function user_state:get(keys, default)
    local value, level = dict.get(self, keys)
    if value ~= nil then
      return value, level
    elseif default then
      return default(), level
    else
      return nil, level
    end
  end
end
