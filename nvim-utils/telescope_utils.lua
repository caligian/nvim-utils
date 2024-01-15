user.telescope = namespace()
local T = user.telescope

function T:__call()
  if self.exists then
    return self
  end

  self.exists = require "telescope"
  self.pickers = require "telescope.pickers"
  self.actions = require "telescope.actions"
  self.action_state = require "telescope.actions.state"
  self.sorters = require "telescope.sorters"
  self.finders = require "telescope.finders"
  self.conf = require("telescope.config").values
  self.theme = dict.merge(require("telescope.themes").get_ivy(), {
    {
      disable_devicons = false,
      previewer = false,
      layout_config = { height = 10 },
    },
  }, { dict.filter(T, function(key, _)
    return key ~= "__call"
  end) })

  return self
end

function T:selected(bufnr, many)
  local picker = self.action_state.get_current_picker(bufnr)

  if picker then
    self.actions.close(bufnr)

    if many then
      local nargs = picker:get_multi_selection()
      if #nargs > 0 then
        return nargs
      end

      return { self.action_state.get_selected_entry() }
    end

    return self.action_state.get_selected_entry()
  end
end

function T:create_picker(items, mappings, opts)
  opts = opts or {}

  -- If opts.finder is missing, then only items will be used
  if not opts.finder and items then
    opts.finder = self.finders.new_table(items)
  end

  items.results = list.map(items, tostring)
  opts.sorter = opts.sorter or self.sorters.get_fzy_sorter()

  if mappings then
    assert_is_a(mappings, union("table", "function"))
    local default = mappings[1]

    opts.attach_mappings = function(prompt_bufnr, map)
      if default then
        map("n", "<CR>", default)
      end

      if #mappings < 2 then
        return true
      end

      for i = 2, #mappings do
        map(unpack(mappings[i]))
      end

      return true
    end
  end

  return self.pickers.new(self.theme, opts)
end
