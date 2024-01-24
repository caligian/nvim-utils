local sh = {}

sh.repl = "/bin/bash"
sh.compile = "/bin/bash {path}"
sh.server = "bashls"
sh.linters = "shellcheck"
sh.formatter = { "shfmt -i 2", stdin = true }

return sh
