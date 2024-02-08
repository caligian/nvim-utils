user.telescope = ns()
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
    disable_devicons = true,
    previewer = false,
    layout_config = { height = 12 },
  })

  return self
end

function T:module()
  local mod = mtset({}, {
    __newindex = function(MOD, key, value)
      if key:match "^multi_" then
        rawset(MOD, key, function(bufnr)
          list.each(T:selected(bufnr, true), value)
        end)
      else
        rawset(MOD, key, function(bufnr)
          return value(T:selected(bufnr))
        end)
      end
    end,
  })

  return mod
end

function T:selected(bufnr, many)
  local picker = self.action_state.get_current_picker(bufnr)

  if picker then
    self.actions.close(bufnr)

    if many then
      local gotten = picker:get_multi_selection()

      if #gotten == 0 then
        return { self.action_state.get_selected_entry() }
      end

      return gotten
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
    mappings = totable(mappings)
    local default = mappings[1]

    opts.attach_mappings = function(_, map)
      for i = 1, #mappings do
        local m = mappings[i]

        if is_function(m) then
          m = { { "i", "n" }, "<CR>", m, {} }
        end

        local mode, ks, cb, opts = unpack(m)
        opts = opts or {}
        opts = is_string(opts) and { desc = opts } or opts
        map(mode, ks, cb, opts)
      end

      return true
    end
  end

  return self.pickers.new(self.theme, opts)
end
