package = "nvim-utils"
version = "dev-1"

source = {
  url = "git+https://github.com/caligian/nvim-utils.git",
}

description = {
  homepage = "https://github.com/caligian/nvim-utils",
  license = "MIT <http://opensource.org/licenses/MIT>",
}

dependencies = {
  "lua >= 5.1",
  "lua-utils",
  "busted",
  "lualogging",
}

build = {
  type = "builtin",
  modules = {
    --- modules
    ["nvim-utils"] = "nvim-utils/init.lua",
    ["nvim-utils.state"] = "nvim-utils/state.lua",
    ["nvim-utils.telescope_utils"] = "nvim-utils/telescope_utils.lua",
    ["nvim-utils.Path"] = "nvim-utils/Path.lua",
    ["nvim-utils.logger"] = "nvim-utils/logger.lua",
    ["nvim-utils.Bookmark"] = "nvim-utils/Bookmark.lua",
    ["nvim-utils.Buffer"] = "nvim-utils/Buffer/Buffer.lua",
    ["nvim-utils.Buffer.float"] = "nvim-utils/Buffer/float.lua",
    ["nvim-utils.Win"] = "nvim-utils/Win.lua",
    ["nvim-utils.color"] = "nvim-utils/color.lua",
    ["nvim-utils.BufferGroup"] = "nvim-utils/BufferGroup.lua",
    ["nvim-utils.Filetype"] = "nvim-utils/Filetype.lua",
    ["nvim-utils.lsp"] = "nvim-utils/lsp.lua",
    ["nvim-utils.Plugin"] = "nvim-utils/Plugin.lua",
    ["nvim-utils.Autocmd"] = "nvim-utils/Autocmd.lua",
    ["nvim-utils.REPL"] = "nvim-utils/REPL.lua",
    ["nvim-utils.Kbd"] = "nvim-utils/Kbd.lua",
    ["nvim-utils.Async"] = "nvim-utils/Async.lua",
    ["nvim-utils.Terminal"] = "nvim-utils/Terminal.lua",
    ["nvim-utils.bootstrap"] = "nvim-utils/bootstrap.lua",

    --- default configs
    ["nvim-utils.defaults.autocmds"] = "nvim-utils/defaults/autocmds.lua",
    ["nvim-utils.defaults.kbds"] = "nvim-utils/defaults/kbds.lua",
    ["nvim-utils.defaults.buffer_groups"] = "nvim-utils/defaults/buffer_groups.lua",
    ["nvim-utils.defaults.commands"] = "nvim-utils/defaults/commands.lua",
    ["nvim-utils.defaults.bookmarks"] = "nvim-utils/defaults/bookmarks.lua",
  },
}   
