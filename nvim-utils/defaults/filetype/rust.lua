local rust = {}

rust.repl = {
  "evcxr",
  on_input = function(s)
    s[#s + 1] = "\n"
    return s
  end,
}

rust.compile = { buffer = "cargo run", workspace = "cargo run" }
rustserver = "rust_analyzer"

return rust
