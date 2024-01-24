local cpp = {}

cpp.server = {
  "ccls",
  config = {
    init_options = {
      compilationDatabaseDirectory = "build",
      index = {
        threads = 0,
      },
      clang = {
        excludeArgs = { "-frounding-math" },
      },
    },
  },
}

return cpp
