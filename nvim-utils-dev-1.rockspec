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
  'busted',
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
    ["nvim-utils.Job"] = "nvim-utils/Job.lua",
    ["nvim-utils.Terminal"] = "nvim-utils/Terminal.lua",
    ["nvim-utils.bootstrap"] = "nvim-utils/bootstrap.lua",

    --- default configs
    ["nvim-utils.defaults.autocmds"] = "nvim-utils/defaults/autocmds.lua",
    ["nvim-utils.defaults.kbds"] = "nvim-utils/defaults/kbds.lua",
    ["nvim-utils.defaults.buffer_groups"] = "nvim-utils/defaults/buffer_groups.lua",
    ["nvim-utils.defaults.commands"] = "nvim-utils/defaults/commands.lua",
    ["nvim-utils.defaults.bookmarks"] = "nvim-utils/defaults/bookmarks.lua",

    --- filetype configs
    ["nvim-utils.defaults.filetype.kbds"] = "nvim-utils/defaults/filetype/kbds.lua",
    ["nvim-utils.defaults.filetype.cpp"] = "nvim-utils/defaults/filetype/cpp.lua",
    ["nvim-utils.defaults.filetype.cs"] = "nvim-utils/defaults/filetype/cs.lua",
    ["nvim-utils.defaults.filetype.elixir"] = "nvim-utils/defaults/filetype/elixir.lua",
    ["nvim-utils.defaults.filetype.erlang"] = "nvim-utils/defaults/filetype/erlang.lua",
    ["nvim-utils.defaults.filetype.fsharp"] = "nvim-utils/defaults/filetype/fsharp.lua",
    ["nvim-utils.defaults.filetype.go"] = "nvim-utils/defaults/filetype/go.lua",
    ["nvim-utils.defaults.filetype.javascript"] = "nvim-utils/defaults/filetype/javascript.lua",
    ["nvim-utils.defaults.filetype.julia"] = "nvim-utils/defaults/filetype/julia.lua",
    ["nvim-utils.defaults.filetype.lua"] = "nvim-utils/defaults/filetype/lua.lua",
    ["nvim-utils.defaults.filetype.mysql"] = "nvim-utils/defaults/filetype/mysql.lua",
    ["nvim-utils.defaults.filetype.netrw"] = "nvim-utils/defaults/filetype/netrw.lua",
    ["nvim-utils.defaults.filetype.norg"] = "nvim-utils/defaults/filetype/norg.lua",
    ["nvim-utils.defaults.filetype.ocaml"] = "nvim-utils/defaults/filetype/ocaml.lua",
    ["nvim-utils.defaults.filetype.python"] = "nvim-utils/defaults/filetype/python.lua",
    ["nvim-utils.defaults.filetype.racket"] = "nvim-utils/defaults/filetype/racket.lua",
    ["nvim-utils.defaults.filetype.r"] = "nvim-utils/defaults/filetype/r.lua",
    ["nvim-utils.defaults.filetype.ruby"] = "nvim-utils/defaults/filetype/ruby.lua",
    ["nvim-utils.defaults.filetype.rust"] = "nvim-utils/defaults/filetype/rust.lua",
    ["nvim-utils.defaults.filetype.sh"] = "nvim-utils/defaults/filetype/sh.lua",
    ["nvim-utils.defaults.filetype.sql"] = "nvim-utils/defaults/filetype/sql.lua",
    ["nvim-utils.defaults.filetype.tex"] = "nvim-utils/defaults/filetype/tex.lua",
    ["nvim-utils.defaults.filetype.text"] = "nvim-utils/defaults/filetype/text.lua",
    ["nvim-utils.defaults.filetype.zsh"] = "nvim-utils/defaults/filetype/zsh.lua",
  },
}
