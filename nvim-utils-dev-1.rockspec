package = "nvim-utils"
version = "dev-1"

source = {
  url = "git+https://github.com/caligian/nvim-utils.git",
}

description = {
  homepage = "https://github.com/caligian/nvim-utils",
  license = "MIT <http://opensource.org/licenses/MIT>",
}

dependencies = { "lua-utils" }

build = {type = 'builtin', modules = {
  ["nvim-utils"] = 'nvim-utils/init.lua'
}}

local add_modules = function (...)
  local modules = {...}
  for i=1, #modules do
    local name = modules[i]
    build.modules['nvim-utils.' .. name] = 'nvim-utils/' .. name .. '.lua'
  end
end

add_modules(
  "autocmd", "augroup",
  "keymap",
  "buffer", "window", "tabpage",
  "nvim",
  "filetype",
  "picker",
  "terminal", "repl",
  "buffer_group"
)
