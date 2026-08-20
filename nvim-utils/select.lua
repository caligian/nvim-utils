local class = require 'lua-utils.class'
local is = require 'lua-utils.is'
local dict = require 'lua-utils.dict'
local param = require 'lua-utils.validate'
local list = require 'lua-utils.list'
local nvim = require 'nvim-utils.nvim'

---@class telescope.make_picker.entry
---@field display string
---@field ordinal string|number
---@field value any

---@class telescope.make_picker.keymap
---@field [1] string|string[] mode
---@field [2] string keys
---@field [3] function action
---@field [4]? table rest of the options

---@alias telescope.make_picker.keymaps telescope.make_picker.keymap[]
---@alias telescope.make_picker.entry_maker fun(x: string|number|table): telescope.make_picker.entry

---@class telescope.make_picker.opts
---@field list? boolean
---@field dict? boolean
---@field keymaps? telescope.make_picker.keymaps
---@field mappings? telescope.make_picker.keymaps
---@field entry_maker? telescope.make_picker.entry_maker
---@field prompt_prefix? string
---@field wrap_results? boolean
---@field default_text? string
---@field default_selection_index? number
---@field sorter? function
---@field finder table<string|number,any>|any[]
---@field cwd? string

---@class user_config.telescope
---@field theme table
---@field opts table
---@field finders table
---@field config table
---@field sorters table
---@field pickers table
---@field actions table
---@field state table
user_config.telescope = user_config.telescope or {}

---Default telescope options to use on a new picker
user_config.telescope.picker_opts = user_config.telescope.picker_opts or {
  layout_config = { height = 0.5 },
}

---Setup opts for telescope
user_config.telescope.opts = {
  pickers = {
    buffers = {
      show_all_buffers = true,
      sort_lastused = true,
      previewer = false,
      mappings = {
        i = {
          ["<c-d>"] = "delete_buffer",
        },
        n = {
          ["dd"] = "delete_buffer",
        }
      }
    }
  }
}

local select = bless {}
local config = user_config.telescope

---@param overrides? table
---@return table
function select.make_opts(overrides)
  overrides = vim.deepcopy(overrides or {})
  dict.mergef(overrides, config.opts or {})
  dict.mergef(overrides, config.theme or {})
  return overrides
end

---Load telescope and cache it
function select.load()
  config.finders = require 'telescope.finders'
  config.config = require('telescope.config').values
  config.sorters = require('telescope.sorters')
  config.pickers = require 'telescope.pickers'
  config.actions = require 'telescope.actions'
  config.state = require 'telescope.actions.state'
end

function select.setup(overrides)
  local opts = select.make_opts(overrides or {})
  require('telescope').setup(opts)
  require('telescope').load_extension('project')
  require("telescope").load_extension("file_browser")
end

---@param name string
---@param overrides table
---@return function
function select.get_builtin_picker(name, overrides)
  return function()
    local builtin = require('telescope.builtin')
    local fn = builtin[name]

    if fn == nil then
      nvim.msg_warn("Invalid picker name provided: " .. name)
    end

    ---@diagnostic disable-next-line
    local opts = telescope:make_opts(overrides)
    if not fn then
      return
    else
      fn(opts)
    end
  end
end

---@param bufnr number
---@param close? boolean
---@return user_config.telescope.make_picker.entry
function select.get_entry(bufnr, close)
  local entry = telescope.state.get_selected_entry()
  if close then
    telescope.actions.close(bufnr)
  end
  return entry
end

---@param bufnr number
---@param close? boolean
---@return user_config.telescope.make_picker.entry
function select.get_entries(bufnr, close)
  local p = telescope.state.get_current_picker(bufnr)
  local gotten = p:get_multi_selection()
  close = close == nil and true or false

  if #gotten == 0 then
    return { select.get_entry(bufnr, close) }
  elseif close then
    telescope.actions.close(bufnr)
  end

  return gotten
end

function select.on_entry(bufnr, close, f)
  return f(select.get_entry(bufnr, close))
end

function select.on_entries(bufnr, close, f)
  list.each(select.get_entries(bufnr, close), f)
end

function select.make_table_from_list(xs, entry_maker)
  return telescope.finders.new_table {
    results = xs,
    entry_maker = entry_maker or function(entry)
      return { display = tostring(entry), ordinal = entry, value = entry }
    end
  }
end

function select.make_table_from_dict(xs, entry_maker)
  local ks = dict.keys(xs)
  return telescope.finders.new_table {
    results = ks,
    entry_maker = entry_maker or function(entry)
      local value = xs[entry]
      return { display = tostring(entry), ordinal = tostring(entry), value = value }
    end
  }
end

---@class telescope.make_table.opts
---@field entry_maker? user_config.telescope.make_picker.entry_maker
---@field list? boolean
---@field dict? boolean

---@param xs table
---@param opts telescope.make_table.opts
function select.make_table(xs, opts)
  opts = opts or { dict = true }
  local entry_maker = opts.entry_maker
  local is_list = opts.list

  if is_list then
    return select.make_table_from_list(xs, entry_maker)
  else
    return select.make_table_from_dict(xs, entry_maker)
  end
end

---@param opts telescope.make_picker.opts
---@return table
function select.make_picker_opts(opts)
  local res = {}
  local ks = {
    'prompt_prefix', 'wrap_results',
    'default_text', 'default_selection_index',
    'sorter', 'cwd'
  }

  for _, k in ipairs(ks) do
    res[k] = opts[k]
  end

  return select.make_opts(res)
end

---@param title string
---@param xs table<string|number,any>|any[]
---@param default_action function
---@param options? user_config.telescope.make_picker.opts
function select.make_picker(title, xs, default_action, options)
  options = options or {}
  local opts = select.make_picker_opts(options)
  local choices = select.make_table(xs, {
    entry_maker = options.entry_maker,
    list = options.list,
    dict = options.dict
  })
  local actions = telescope.actions
  local mappings = options.mappings or options.keymaps or {}
  local sorter = options.sorter or telescope.sorters.get_fzy_sorter()
  local args = { finder = choices, prompt_title = title, sorter = sorter }

  if mappings then
    param.mappings(mappings, 'list')
    for i = 1, #mappings do
      param.mapping(mappings[i], 'list')
      param.callback(mappings[i][3], 'callable')
    end
  end

  opts.attach_mappings = function(prompt_bufnr, map)
    actions.select_default:replace(function()
      local selection = select.get_entries(prompt_bufnr, true)
      for _, sel in ipairs(selection) do default_action(sel) end
    end)

    for i = 1, #mappings do
      local mode, ks, cb, o = unpack(mappings[i])
      o = o or {}
      o = is.string(o) and { desc = o } or o
      map(mode, ks, cb, o)
    end

    return true
  end

  args.sorter = sorter or telescope.sorters.get_fzy_sorter()
  args.finders = choices
  args.prompt_title = title

  return config.pickers.new(opts, args)
end

---@param title string
---@param xs table<string|number,any>|any[]
---@param default_action function
---@param options? user_config.telescope.make_picker.opts
function select.make_and_run_picker(title, xs, default_action, options)
  local picker = select.make_picker(title, xs, default_action, options)
  picker:find()
end

---@param title string
---@param elements table<string|number,any>|any[]
---@param on_enter user_config.telescope.make_picker.entry
---@param opts? user_config.telescope.make_picker.opts
function select:__call(title, elements, on_enter, opts)
  return select.make_and_run_picker(title, elements, on_enter, opts)
end

return select
