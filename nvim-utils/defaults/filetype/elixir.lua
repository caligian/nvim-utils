local elixir = {}

local function is_project(current_dir)
  local prev_dir = vim.fn.fnamemodify(current_dir, ":h")
  local ls = Path.ls(prev_dir)
  local check = Path.join(prev_dir, "mix.exs")

  for i = 1, #ls do
    if string.match(ls[i], check) then
      return true
    end
  end

  return false
end

elixir.repl = {
  buffer = "iex",
  root_dir = { "mix.exs" },
  workspace = {
    {
      function(ws)
        local check_path = Path.join(ws, "deps", "phoenix")

        if Path.is_dir(check_path) then
          return true
        end
      end,
      function()
        return "iex"
      end,
    },
    {
      identity,
      function()
        return "iex -S mix"
      end,
    },
  },
}

local mix = whereis("mix")[1]

if mix then
  elixir.formatter = {
    buffer = mix .. " format - ",
    stdin = true,
  }

  elixir.compile = {
    buffer = "elixir {path}",
    workspace = mix .. " run",
  }

  elixir.test = {
    workspace = mix .. " test",
  }
end

elixir.server = {
  "elixirls",
  config = {
    cmd = {
      Path.join(user.paths.data, "lsp-servers", "elixir-ls", "scripts", "language_server.sh"),
    },
    root_dir = require("lspconfig").util.root_pattern "mix.exs",
  },
}

elixir.mappings = {
  compile_and_run_buffer_in_workspace = {
    "n",
    "<leader>rc",
    function()
      local bufnr = current_buf()
      local x = REPL(bufnr(), { workspace = true })
      if x then
        x:send(sprintf('c("%s")', current_buf_name()))
      end
    end,
    { desc = "compile and run buffer" },
  },

  compile_and_run_buffer = {
    "n",
    "<localleader>rc",
    function()
      local x = REPL(current_buf(), { buffer = true })
      if x then
        x:send(sprintf('c("%s")', current_buf_name()))
      end
    end,
    { desc = "compile and run buffer" },
  },
}

return elixir
