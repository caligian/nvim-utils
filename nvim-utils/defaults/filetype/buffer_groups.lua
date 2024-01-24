return {
  nvim_lua = { "BufAdd", "*.config/nvim*lua" },
  xdg_config = { "BufAdd", os.getenv "HOME" .. "/.config/*" },
  repos = { "BufAdd", os.getenv "HOME" .. "/Repos/*" },
  work = { "BufAdd", os.getenv "HOME" .. "/Work/*" },
  docs = { "BufAdd", os.getenv "HOME" .. "/Documents/*" },
}
