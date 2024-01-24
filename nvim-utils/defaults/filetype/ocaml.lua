local ocaml = {}

ocaml.repl = {
  "utop",
  on_input = function(s)
    if not s[#s]:match ";;$" then
      s[#s] = s[#s] .. ";;"
    end

    return s
  end,
}

ocaml.server = "ocamllsp"

ocaml.formatter = {
  buffer = "ocamlformat - ",
  stdin = true,
}

ocaml.buf_opts = {
  tabstop = 4,
  shiftwidth = 4,
}

return ocaml
