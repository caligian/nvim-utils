local utils = require 'lua-utils'
local types = utils.types
local validate = utils.validate
local class = utils.class
local dict = utils.dict
local V = validate
local picker = class 'picker'
user_config.picker = picker

function picker:initialize(title)
  self.telescope = {
    finders = require 'telescope.finders',
    config = require('telescope.config').values,
    sorters = require('telescope.sorters'),
    pickers = require 'telescope.pickers',
    actions = require 'telescope.actions',
    actions_state = require 'telescope.actions.state',
  }

  local themes = require("telescope.themes")
  local theme = themes['get_' .. user_config.telescope.theme]()
  local opts = user_config.telescope or {}
  V.telescope_opts(opts, 'table')

  self.telescope.theme = dict.merge(theme, opts, true)
  self.actions = {}
  self.title = title
  self.state = self.telescope.actions_state

  V.title(title, 'string')
end


function picker:close(bufnr)
  self.telescope.actions.close(bufnr)
end

picker.hide = picker.close

function picker:call(what, method, ...)
  return self.telescope[what][method](...)
end

function picker:entry(bufnr)
  local x = self.state.get_selected_entry()
  self:close(bufnr)
  return x
end

function picker:entries(bufnr)
  local x = self.state.get_current_picker(bufnr)
  if not x then
    return
  end

  local gotten = x:get_multi_selection()
  if #gotten == 0 then
    gotten = {self:entry(bufnr)}
  else
    self:close(bufnr)
  end

  return gotten
end

function picker:table(xs, entry_maker)
  if types.dict(xs) then
    xs = dict.items(xs)
    return self.telescope.finders.new_table({
      results = xs,
      entry_maker = entry_maker or function(entry)
        return {
          display = entry[1],
          ordinal = entry[1],
          value = entry[2],
        }
      end
    })
  else
    V.choices(xs, types.list)
    return self.telescope.finders.new_table({
      results = xs,
      entry_maker = entry_maker or function (entry)
        return {
          display = entry,
          value = entry,
          ordinal = entry,
        }
      end
    })
  end
end

function picker:create(xs, default_mapping, opts)
  opts = opts or {}

  V.opts(opts, 'table')
  V.choices(xs, 'table')
  V.default_mapping(default_mapping, types.callable)

  opts = vim.deepcopy(opts)
  local choices = self:table(xs, opts.entry_maker)
  local actions = self.telescope.actions
  local mappings = opts.mappings or opts.keymaps or {}
  local sorter = opts.sorter

  opts.entry_maker = nil
  opts.keymaps = nil
  opts.mappings = nil
  opts.sorted = nil
  local args = {}

  V.keymaps(mappings, 'table')

  if #mappings > 0 then
    for i=1, #mappings do
      local cb = self.actions[mappings[i][3]]
      V.callback(cb, types.callable)
    end
  end

  opts.attach_mappings = function(prompt_bufnr, map)
    actions.select_default:replace(function()
      local selection = self:entries(prompt_bufnr)
      default_mapping(selection)
    end)

    for i=1, #mappings do
      local mode, ks, cb, o = unpack(mappings[i])
      o = o or {}
      o = types.string(o) and { desc = o } or o
      cb = self.actions[cb]
      map(mode, ks, cb, o)
    end

    return true
  end

  dict.merge(opts, self.telescope.theme)

  args.sorter = sorter or self.telescope.sorters.get_fzy_sorter()
  args.finder = choices
  args.prompt_title = self.title

  return self.telescope.pickers.new(opts, args)
end

function picker:run(xs, default_mapping, opts)
  local p = self:create(xs, default_mapping, opts)
  if p then
    p:find()
    return true
  else
    return false
  end
end

picker.find = picker.run

return picker
