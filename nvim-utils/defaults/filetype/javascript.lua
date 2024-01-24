local js = {}

js.compile = "node {path}"

js.repl = "node"

js.server = "tsserver"

js.buf_opts = {
  expandtab = true,
}

return js
