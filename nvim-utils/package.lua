-- local toml = require 'nvim-utils.toml'
local template = require 'lua-utils.template'

t = template(python_template, {
  name = "laudutech",
  author = "caligian",
})

print(t:parse())

local package = {
  defaults = {
    python = {
      -- can be 'toml', 'json', 'lua'
      format = 'toml',
      marker_files = { 'pyproject.toml' },
      copy_defaults = true,
      template = {
      }
    }
  }
}
