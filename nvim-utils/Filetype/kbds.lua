local function unwrap(f)
  return function()
    local ft = Filetype(Buffer.current())
    if ft then
      return f(ft)
    end
  end
end

local function format(cmd_for)
  return unwrap(function(ft)
    return ft:format_buffer(Buffer.current(), cmd_for)
  end)
end

local function _compile(action, cmd_for)
  return unwrap(function(ft)
    return ft:compile_buffer(Buffer.current(), action, cmd_for)
  end)
end

local function compile(cmd_for)
  return _compile("compile", cmd_for)
end

local function test(cmd_for)
  return _compile("test", cmd_for)
end

local function build(cmd_for)
  return _compile("build", cmd_for)
end

local mappings = {
  workspace_test = {
    "n",
    "<leader>mt",
    test "workspace",
    {},
  },
  dir_test = {
    "n",
    "<leader>ct",
    test "dir",
    {},
  },
  buffer_test = {
    "n",
    "<localleader>ct",
    test "buffer",
    {},
  },
  workspace_build = {
    "n",
    "<leader>mb",
    build "workspace",
    {},
  },
  dir_build = {
    "n",
    "<leader>cb",
    build "dir",
    {},
  },
  buffer_build = {
    "n",
    "<localleader>cb",
    build "buffer",
    {},
  },
  workspace_compile = {
    "n",
    "<leader>mc",
    compile "workspace",
    {},
  },
  dir_compile = {
    "n",
    "<leader>cc",
    compile "dir",
    {},
  },
  buffer_compile = {
    "n",
    "<localleader>cc",
    compile "buffer",
    {},
  },
  workspace_format = {
    "n",
    "<leader>mf",
    format "workspace",
    {},
  },
  dir_format = {
    "n",
    "<leader>bF",
    format "dir",
    {},
  },
  buffer_format = {
    "n",
    "<localleader>bf",
    format "buffer",
    {},
  },
}

return mappings
