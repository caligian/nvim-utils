local utils = {}
local buf = Buffer
local path = Path

function utils.resolve(name)
	assert_is_a(name, union("Filetype", "string", "number"))

	if typeof(name) == "Filetype" then
		return name
	elseif is_number(name) then
		if Buffer.exists(name) then
			name = Buffer.get_option(name, "filetype")
		else
			return
		end
	end

	return user.filetypes[name]
end

function utils.query(ft, attrib, f)
	local obj = utils.resolve(ft)

	if not obj then
		return "invalid filetype " .. dump(ft)
	end

	obj = dict.get(obj, totable(attrib))

	if not obj then
		return string.format("%s: invalid attribute: %s", dump(ft), dump(attrib))
	end

	if f then
		return f(obj)
	end

	return obj
end

function utils.find_workspace(start_dir, pats, maxdepth, _depth)
	maxdepth = maxdepth or 5
	_depth = _depth or 0
	pats = totable(pats or "%.git/$")

	if maxdepth == _depth then
		return false
	end

	if not Path.is_dir(start_dir) then
		return false
	end

	local children = Path.ls(start_dir, true)
	for i = 1, #pats do
		local pat = pats[i]
		for j = 1, #children do
			if children[j]:match(pat) then
				return start_dir
			end
		end
	end

	return utils.find_workspace(Path.dirname(start_dir), pats, maxdepth, _depth + 1)
end


function utils.get_workspace(bufnr, pats, maxdepth, _depth)
	if not buf.exists(bufnr) then
		return
	end

	local bufname = buf.get_name(bufnr)
	local ws = utils.find_workspace(Path.dirname(bufname), pats, maxdepth, _depth)
	if ws then return ws end

	local server = utils.query(buf.filetype(bufnr), "server")
	if not server then
		return
	end

	local lspconfig = require("lspconfig")
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
end

local function get_name(x)
	return Path.basename(x):gsub("%.lua", "")
end

function utils.list_configs()
	local core_dir = req2path("core.filetype"):gsub("/%.lua", "")
	local user_dir = req2path("user.filetype")
	local core_files = Path.get_files(core_dir)
	local core_names = list.map(core_files, get_name)

	if user_dir then
		user_dir = user_dir:gsub("/%.lua", "")
		local user_files = Path.get_files(user_dir)
		local user_names = list.map(user_files, get_name)

		return list.union(core_names, user_names)
	end

	return core_names
end


return utils


