local package_path = vim.split(package.path, ";")
local formatter_path = Path.join(os.getenv "HOME", ".cargo", "bin", "stylua")
local formatter_cmd = formatter_path
  .. " "
  .. join({
    "--call-parentheses None",
    "--collapse-simple-statement Never",
    "--line-endings Unix",
    "--column-width 120",
    "--quote-style AutoPreferDouble",
    "--indent-type Spaces",
    "--indent-width 2",
  }, " ")

return {
  buf_opts = {
    shiftwidth = 2,
    tabstop = 2,
  },

  formatter = {
    buffer = "cat {path} | " .. formatter_cmd .. " -",
    workspace = formatter_cmd .. " {path}",
    dir = formatter_cmd .. " {path}",
  },

  compile = {
    buffer = "lua {path}",
    workspace = function(ws)
      local kids = strsplit(vim.fn.glob(ws .. "/*.rockspec"), "\n")
      local cmd = "luarocks --local build " .. (kids[1] or "")
      return cmd
    end,
  },

  repl = {
    buffer = "lua",
    workspace = "lua",
    dir = "lua",
  },

  server = {
    "lua_ls",
    config = {
      cmd = {
        Path.join(vim.fn.stdpath "data", "lsp-servers", "lua-language-server", "bin", "lua-language-server"),
      },
      settings = {
        Lua = {
          path = package_path,
          runtime = {
            version = "Lua 5.1",
          },
          workspace = {
            library = package_path,
          },
          telemetry = {
            enable = false,
          },
          diagnostics = {
            severity = { { ["undefined-global"] = false } },
            disable = {
              "lowercase-global",
              "undefined-global",
            },
          },
        },
      },
    },
  },
}
