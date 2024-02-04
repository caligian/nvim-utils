require "lua-utils.utils"
require "lua-utils.table"

local lpeg = require "lpeg"
local lfs = require "lfs"
Path = dict.merge(ns(), lfs)
Path.ln = Path.link
Path.stat = Path.attributes
Path.lnstat = Path.symlinkattributes
Path.cd = Path.chdir
Path.cwd = Path.currentdir

function Path.clean(x)
  return x:gsub("//+", "/")
end

function Path.split(x)
  return strsplit(Path.clean(x), "/", { ignore_escaped = true })
end

function Path.join(...)
  local p = { ... }
  local had_root = p[1]:match "^/"

  for i = 1, #p do
    p[i] = p[i]:gsub("^/+", "")
    p[i] = p[i]:gsub("/+$", "")
  end

  local out = join(p, "/")
  if had_root then
    return "/" .. out
  end

  return out
end

function Path.is(p, mode)
  assert_is_a.string(mode)

  local attribs, msg = Path.attributes(p)

  if not attribs then
    return false, msg
  end

  return attribs.mode == mode
end

function Path.exists(p)
  return Path.stat(p) ~= nil
end

function Path.is_namedpipe(p)
  return Path.is(p, "named pipe")
end

function Path.is_dir(p)
  return Path.is(p, "directory")
end

function Path.is_pipe(p)
  return Path.is(p, "pipe")
end

function Path.is_char(p)
  return Path.is(p, "char device")
end

function Path.is_block(p)
  return Path.is(p, "block device")
end

function Path.is_file(p)
  return Path.is(p, "file")
end

function Path.is_socket(p)
  return Path.is(p, "socket")
end

function Path.attrib(p, attrib)
  local attribs, msg = lfs.attributes(p)
  if not attribs then
    return attribs, msg
  end

  return attribs[attrib]
end

function Path.ctime(p)
  return Path.attrib(p, "change")
end

function Path.mtime(p)
  return Path.attrib(p, "modification")
end

function Path.atime(p)
  return Path.attrib(p, "access")
end

function Path.nlink(p)
  return Path.attrib(p, "nlink")
end

function Path.uid(p)
  return Path.attrib(p, "uid")
end

function Path.gid(p)
  return Path.attrib(p, "gid")
end

function Path.dev(p)
  return Path.attrib(p, "dev")
end

function Path.rdev(p)
  return Path.attrib(p, "rdev")
end

function Path.inode(p)
  return Path.attrib(p, "ino")
end

function Path.size(p)
  return Path.attrib(p, "size")
end

function Path.permissions(p)
  return Path.attrib(p, "permissions")
end

function Path.blksize(p)
  return Path.attrib(p, "blksize")
end

Path.blocksize = Path.blksize

function Path.blocks(p)
  return Path.attrib(p, "blocks")
end

--- ls [-p] <path>
--- @param p string dirpath
--- @param show_dirs? boolean add '/' at the end of dirs
--- @return string[]?
function Path.ls(p, show_dirs)
  if not Path.is_dir(p) then
    return
  end

  local out = {}
  p = p:gsub("/$", "")

  for f in Path.dir(p) do
    if f ~= "." and f ~= ".." then
      f = Path.join(p, f)

      if show_dirs then
        if Path.is_dir(f) then
          f = Path.join(f, "")
        end
      end

      out[#out + 1] = f
    end
  end

  return out
end

Path.children = Path.ls

function Path.get_files(p)
  local fs = Path.ls(p)
  if not fs then
    return
  end

  return list.filter(fs, function(x)
    if Path.is_file(x) then
      return true
    end
  end)
end

function Path.read(p)
  if not Path.is_file(p) then
    return
  end

  local fh = io.open(p, "r")
  if not fh then
    return
  end

  local lines = fh:read "*a"
  fh:close()

  return lines
end

function Path.write(p, lines)
  local fh = io.open(p, "w")
  if not fh then
    return
  end

  assert_is_a(lines, union("string", "table"))
  lines = is_table(lines) and join(lines, "\n") or lines

  fh:write(lines)
  fh:close()

  return #lines
end

function Path:__call(...)
  local p = Path.join(...)
  if not Path.exists(p) then
    return
  end

  return p
end

function Path.dirname(p)
  p = Path.split(p)

  if not p then
    return
  end

  if #p == 1 then
    return false
  end

  p[#p] = nil
  return Path.join(unpack(p))
end

function Path.basename(p)
  local last_sep
  local sep = "/"

  if not p:match(sep) then
    return p
  end

  for i = #p, 2, -1 do
    local a = p:sub(i, i)
    local b = p:sub(i - 1, i - 1)

    if a == "/" and b ~= "\\" then
      last_sep = i
      break
    end
  end

  return p:sub(last_sep + 1, #p)
end

function Path.ext(p)
  if not p:match "%." then
    return
  end

  local basename = Path.basename(p)
  if not basename then
    return
  end

  return basename:match "%.([^.]+)$"
end

Path.extension = Path.ext

function Path.abspath(p, exists)
  if not Path.exists(p) and exists then
    return
  elseif p:match "^/" or p:match "^[A-Za-z0-9_]+:\\" then
    return p
  elseif p:match("^%." .. "/") then
    p = p:sub(3)
  elseif p:match("^%.%." .. "/") then
    p = Path.dirname(p)
  end

  local cwd = Path.cwd()
  if p == "." then
    return cwd
  elseif p == ".." then
    return Path.dirname(p)
  elseif p:match(cwd) then
    return p
  end

  p = Path.clean(p)
  return Path.join(cwd, p)
end

function Path.is_abs(p, exists)
  if not Path.exists(p) and exists then
    return
  elseif p:match "^/" then
    return p
  end
end

function Path.relpath(p, exists)
  if exists and not Path.exists(p) then
    return
  elseif p:sub(1, 2) == "./" then
    return p
  end

  local cwd = Path.cwd()
  if cwd == p then
    return "./"
  else
    local pat = lpeg.P(cwd) * lpeg.C(lpeg.P(1) ^ 0)
    local found = pat:match(p)
    return "." .. found
  end
end

Path.delete = os.remove
Path.rm = Path.delete
