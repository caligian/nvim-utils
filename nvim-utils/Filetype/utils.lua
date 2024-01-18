local utils = {}
local buf = Buffer
local path = Path

function utils.resolve(name)
  assert_is_a(name, union('Filetype', 'string', 'number'))

  if typeof(name) == 'Filetype' then
    return name
  elseif is_number(name) then
    name = Buffer.get_option(name, 'filetype')
  end

  return user.filetypes[name]
end

function utils.query(ft, attrib, f)
  local obj = utils.resolve(ft)
  if not obj then
    return 'invalid filetype ' .. dump(ft)
  end

  obj = dict.get(obj, totable(attrib))
  if not obj then
    return string.format('%s: invalid attribute: %s', dump(ft), dump(attrib))
  end

  if f then
    return f(obj)
  end

  return obj
end

function utils.find_workspace(start_dir, pats, maxdepth, _depth)
  maxdepth = maxdepth or 5
  _depth = _depth or 0
  pats = totable(pats or "%.git$")

  if maxdepth == _depth then
    return false
  end

  if not path.is_dir(start_dir) then
    return false
  end

  local parent = path.dirname(start_dir)
  local children = path.getfiles(start_dir)

  for i = 1, #pats do
    local pat = pats[i]

    for j = 1, #children do
      if children[j]:match(pat) then
        return children[j]
      end
    end
  end

  return find_workspace(parent, pats, maxdepth, _depth + 1)
end

function utils.get_workspace(bufnr, pats, maxdepth, _depth)
  if not buf.exists(bufnr) then
    return
  end

  local bufname = buf.get_name(bufnr)
  local server = utils.query(buf.filetype(bufnr), "server")

  if server then
    local lspconfig = require "lspconfig"
    server = totable(server)

    local config = is_string(server) and lspconfig[server] or lspconfig[server[1]]

    local root_dir_checker = server.get_root_dir
      or config.document_config.default_config.root_dir
      or config.get_root_dir

    if root_dir_checker then
      return root_dir_checker(bufname)
    else
      return find_workspace(bufname, pats, maxdepth, _depth)
    end
  else
    return find_workspace(bufname, pats, maxdepth, _depth)
  end
end

return utils
