local erlang = {}

erlang.repl = "erl"

erlang.server = "erlangls"

erlang.compile = "erl {path}"

erlang.formatter = { buffer = "rebar3 fmt -", stdin = true }

erlang.mappings = {
  compile_and_run_buffer = {
    "n",
    "<localleader>rc",
    function()
      local bufnr = buffer.bufnr()
      local x = repl(buffer.bufnr(), { buffer = true })
      if x then
        buffer.save(bufnr)
        x:send(sprintf('c("%s").', buffer.name()))
      end
    end,
    { desc = "compile and run buffer" },
  },
}

return erlang
