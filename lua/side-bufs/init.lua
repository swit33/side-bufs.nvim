local M = {}

local defaults = {
	side = "left",
	width = 25,
}

local config = vim.deepcopy(defaults)
local initialized = false
local rendering = false
local ns = vim.api.nvim_create_namespace("side-bufs")
local path_sep = package.config:sub(1, 1)
local ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890"

local state = {
	picking = false,
	letter_to_buf = {},
	main_wins = {},
}

M.bufnr = nil

local function theme_fg(default, ...)
	for _, name in ipairs({ ... }) do
		local hl = vim.api.nvim_get_hl(0, { name = name })
		local fg = hl.fg or hl.foreground
		if fg then
			return string.format("#%06x", fg)
		end
	end
	return default
end

local function setup_hl()
	vim.api.nvim_set_hl(0, "SideBufsPick", {
		default = true,
		fg = theme_fg("#ff0000", "DiagnosticError", "Error"),
		bold = true,
	})
	vim.api.nvim_set_hl(0, "SideBufsModified", {
		default = true,
		fg = theme_fg("#ffffff", "String", "Normal"),
	})
	vim.api.nvim_set_hl(0, "SideBufsDuplicate", { default = true, link = "Comment" })
	vim.api.nvim_set_hl(0, "SideBufsCurrent", { default = true, link = "Title" })
end

local function get_buffers()
	local list = {}
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if bufnr ~= M.bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			if vim.api.nvim_get_option_value("buflisted", { buf = bufnr }) and vim.bo[bufnr].buftype == "" then
				list[#list + 1] = bufnr
			end
		end
	end
	table.sort(list)
	return list
end

local function bufname(bufnr)
	local path = vim.api.nvim_buf_get_name(bufnr)
	if path == "" then
		return "[No Name]"
	end
	return vim.fn.fnamemodify(path, ":t")
end

local function path_parts(path)
	return vim.split(path, path_sep, { trimempty = true })
end

local function relative_to_cwd(path)
	if path == "" then
		return path
	end
	local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
	if cwd:sub(-1) == path_sep then
		cwd = cwd:sub(1, -2)
	end
	local prefix = cwd .. path_sep
	if path:sub(1, #prefix) == prefix then
		return path:sub(#prefix + 1)
	end
	return path
end

local function disambiguate_names(bufs)
	local names = {}
	local by_name = {}
	for _, bufnr in ipairs(bufs) do
		local name = bufname(bufnr)
		by_name[name] = by_name[name] or {}
		by_name[name][#by_name[name] + 1] = bufnr
	end

	for name, group in pairs(by_name) do
		if #group == 1 then
			names[group[1]] = name
		else
			local paths = {}
			for _, bufnr in ipairs(group) do
				paths[bufnr] = path_parts(relative_to_cwd(vim.api.nvim_buf_get_name(bufnr)))
			end

			for _, bufnr in ipairs(group) do
				local parts = paths[bufnr]
				if #parts == 0 then
					names[bufnr] = name
				else
					local ndirs = #parts - 1
					local function shared_at(i)
						local segment = parts[i]
						for other, other_parts in pairs(paths) do
							if other ~= bufnr and other_parts[i] == segment then
								return true
							end
						end
						return false
					end

					local shown = {}
					local i = 1
					while i <= ndirs do
						if not shared_at(i) then
							shown[#shown + 1] = parts[i]
							i = i + 1
						else
							while i <= ndirs and shared_at(i) do
								i = i + 1
							end
							shown[#shown + 1] = ".."
						end
					end

					if #shown == 1 and shown[1] == ".." then
						shown = {}
						for j = 1, ndirs do
							shown[#shown + 1] = parts[j]
						end
					end

					local dir = table.concat(shown, path_sep)
					if dir ~= "" then
						dir = dir .. path_sep
					end
					names[bufnr] = dir .. name
				end
			end
		end
	end
	return names
end

local function get_icon(name)
	local ok, devicons = pcall(require, "nvim-web-devicons")
	if not ok then
		return " ", nil
	end
	local icon, hl = devicons.get_icon(name, vim.fn.fnamemodify(name, ":e"), { default = true })
	return icon or " ", hl
end

local function find_sidebar_win(tab)
	local buf = M.bufnr
	if not (buf and vim.api.nvim_buf_is_valid(buf)) then
		return nil
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab or 0)) do
		if vim.api.nvim_win_get_buf(win) == buf then
			return win
		end
	end
end

local function is_main_win(win, tab)
	if not (win and vim.api.nvim_win_is_valid(win)) then
		return false
	end
	if tab and vim.api.nvim_win_get_tabpage(win) ~= tab then
		return false
	end
	local buf = vim.api.nvim_win_get_buf(win)
	return buf ~= M.bufnr and vim.api.nvim_win_get_config(win).relative == "" and vim.bo[buf].buftype == ""
end

local function remember_main_win(win)
	win = win or vim.api.nvim_get_current_win()
	local tab = vim.api.nvim_win_get_tabpage(win)
	if is_main_win(win, tab) then
		state.main_wins[tab] = win
	end
end

local function get_main_win(tab)
	tab = tab or vim.api.nvim_get_current_tabpage()
	local remembered = state.main_wins[tab]
	if is_main_win(remembered, tab) then
		return remembered
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if is_main_win(win, tab) then
			state.main_wins[tab] = win
			return win
		end
	end
end

local function buffer_at_cursor()
	if not (M.bufnr and vim.api.nvim_buf_is_valid(M.bufnr)) then
		return nil
	end
	return get_buffers()[vim.api.nvim_win_get_cursor(0)[1]]
end

local function goto_main_with(bufnr)
	if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
		return
	end

	local current = vim.api.nvim_get_current_win()
	if is_main_win(current) then
		vim.api.nvim_set_current_buf(bufnr)
		remember_main_win(current)
		return
	end

	local target = get_main_win()
	if not target then
		vim.cmd("new")
		target = vim.api.nvim_get_current_win()
	else
		vim.api.nvim_set_current_win(target)
	end
	vim.api.nvim_win_set_buf(target, bufnr)
	remember_main_win(target)
end

local function allocate_label(name, used)
	local initial = name:sub(1, 1)
	if #initial == 1 and not used[initial] then
		local ok = false
		for char in ALPHABET:gmatch(".") do
			if char == initial then
				ok = true
				break
			end
		end
		if ok then
			used[initial] = true
			return initial
		end
	end
	for char in ALPHABET:gmatch(".") do
		if not used[char] then
			used[char] = true
			return char
		end
	end
	return nil
end

local function dispatch_key(options)
	local ok, key = pcall(options.read_key)
	if not ok then
		return
	end
	if type(key) == "number" then
		key = options.to_char(key)
	end
	local item = options.labels[key]
	if item == nil then
		return
	end
	if options.action == "switch" then
		options.on_switch(item)
	elseif options.action == "close" then
		options.on_close(item)
	end
end

local function ensure_setup()
	if not initialized then
		M.setup()
	end
end

local function render()
	local buf = M.bufnr
	if not (buf and vim.api.nvim_buf_is_valid(buf)) then
		return
	end

	local width = config.width
	local sidebar_win = find_sidebar_win()
	if sidebar_win then
		width = vim.api.nvim_win_get_width(sidebar_win)
	end

	local bufs = get_buffers()
	local names = disambiguate_names(bufs)
	local letters = {}
	local letter_to_buf = {}
	local taken = {}
	for _, bufnr in ipairs(bufs) do
		local letter = allocate_label(bufname(bufnr), taken)
		letters[bufnr] = letter
		if letter then
			letter_to_buf[letter] = bufnr
		end
	end
	state.letter_to_buf = letter_to_buf

	local main_win = get_main_win()
	local current = main_win and vim.api.nvim_win_get_buf(main_win) or vim.api.nvim_get_current_buf()
	local lines = {}
	local highlights = {}

	for i, bufnr in ipairs(bufs) do
		local base = bufname(bufnr)
		local name = names[bufnr] or base
		local is_current = bufnr == current
		local modified = vim.bo[bufnr].modified
		local icon, icon_hl = get_icon(base)
		local letter = letters[bufnr]
		local line = (is_current and "▎" or " ") .. " "
		local prefix_start = #line
		local prefix = state.picking and letter or icon
		local prefix_hl = state.picking and letter
			and (state.picking == "close" and "SideBufsPick" or "SideBufsCurrent")
			or icon_hl
		line = line .. (prefix or " ")

		local name_start = #line + 1
		line = line .. " "
		local marker = modified and " ●" or ""
		local name_max = math.max(width - vim.fn.strwidth(line .. marker) - 2, 10)
		local shown = name
		if vim.fn.strwidth(name) > name_max then
			local sep_pos = name:find(path_sep, 1, true)
			local segment = sep_pos and name:sub(1, sep_pos - 1) or nil
			if segment and segment ~= ".." then
				local keep = math.max(vim.fn.strchars(segment) - 2, 0)
				shown = ".." .. vim.fn.strcharpart(segment, keep, 2) .. name:sub(sep_pos)
			end
			if vim.fn.strwidth(shown) > name_max then
				local keep = math.max(name_max - 2, 2)
				shown = ".." .. vim.fn.strcharpart(name, math.max(vim.fn.strchars(name) - keep, 0), keep)
			end
		end
		line = line .. shown

		local marker_start = #line
		line = line .. marker
		lines[#lines + 1] = line

		local lnum = i - 1
		if is_current then
			highlights[#highlights + 1] = { lnum, "SideBufsCurrent", 0, 3 }
		end
		if prefix_hl then
			highlights[#highlights + 1] = { lnum, prefix_hl, prefix_start, prefix_start + #(prefix or " ") }
		end

		local shown_folder = math.max(#shown - #base, 0)
		local name_hl_start = name_start
		if shown_folder > 0 then
			highlights[#highlights + 1] = {
				lnum,
				"SideBufsDuplicate",
				name_start,
				name_start + shown_folder,
			}
			name_hl_start = name_start + shown_folder
		end
		if is_current then
			highlights[#highlights + 1] = { lnum, "SideBufsCurrent", name_hl_start, marker_start }
		end
		if modified then
			highlights[#highlights + 1] = { lnum, "SideBufsModified", marker_start, -1 }
		end
	end

	if #lines == 0 then
		lines[1] = "  No buffers"
	end

	local cursor = 1
	if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
		cursor = vim.api.nvim_win_get_cursor(sidebar_win)[1]
	end

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
		vim.api.nvim_win_set_cursor(sidebar_win, { math.min(math.max(cursor, 1), #lines), 0 })
	end

	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for _, hl in ipairs(highlights) do
		vim.api.nvim_buf_add_highlight(buf, ns, hl[2], hl[1], hl[3], hl[4])
	end
end

function M.render()
	ensure_setup()
	if rendering then
		return
	end
	rendering = true
	local ok, err = xpcall(render, debug.traceback)
	rendering = false
	if not ok then
		error(err, 0)
	end
end

local function set_keymaps(buf)
	local opts = { buffer = buf, silent = true }
	vim.keymap.set("n", "<CR>", function()
		goto_main_with(buffer_at_cursor())
	end, opts)
	vim.keymap.set("n", "<LeftRelease>", function()
		goto_main_with(buffer_at_cursor())
	end, opts)
	vim.keymap.set("n", "p", M.pick, opts)
	vim.keymap.set("n", "d", function()
		M.remove(buffer_at_cursor())
	end, opts)
	vim.keymap.set("n", "q", M.close, opts)
	vim.keymap.set("n", "<Esc>", M.close, opts)
end

local function ensure_buffer()
	if M.bufnr and vim.api.nvim_buf_is_valid(M.bufnr) then
		return M.bufnr
	end
	local buf = vim.api.nvim_create_buf(false, true)
	M.bufnr = buf
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "side-bufs"
	set_keymaps(buf)
	return buf
end

local function configure_window(win)
	vim.api.nvim_win_set_width(win, math.min(config.width, math.max(vim.o.columns - 1, 1)))
	vim.wo[win].winfixwidth = true
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].statuscolumn = ""
	vim.wo[win].wrap = false
	vim.wo[win].spell = false
	vim.wo[win].list = false
	vim.wo[win].cursorline = true
end

function M.open()
	ensure_setup()
	local existing = find_sidebar_win()
	if existing then
		M.render()
		return existing
	end

	remember_main_win()
	local buf = ensure_buffer()
	local win = vim.api.nvim_open_win(buf, false, {
		split = config.side,
		win = -1,
		width = config.width,
	})
	configure_window(win)
	M.render()
	return win
end

function M.close()
	ensure_setup()
	local win = find_sidebar_win()
	if win then
		vim.api.nvim_win_close(win, true)
	end
end

function M.toggle()
	ensure_setup()
	if find_sidebar_win() then
		M.close()
	else
		M.open()
	end
end

function M.pick(action)
	ensure_setup()
	M.open()
	local mode = action == "close" and "close" or "switch"
	state.picking = mode
	M.render()
	vim.cmd("redraw")

	dispatch_key({
		read_key = vim.fn.getchar,
		to_char = vim.fn.nr2char,
		labels = state.letter_to_buf,
		action = mode,
		on_switch = goto_main_with,
		on_close = M.remove,
	})
	state.picking = false
	M.render()
end

function M.pick_close()
	M.pick("close")
end

function M.remove(bufnr)
	ensure_setup()
	if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
		return false
	end
	if vim.bo[bufnr].modified then
		local choice = vim.fn.confirm("Buffer has unsaved changes. Delete it?", "&Yes\n&No", 2)
		if choice ~= 1 then
			return false
		end
	end
	local ok, err = pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
	if not ok then
		vim.notify(err, vim.log.levels.ERROR)
		return false
	end
	M.render()
	return true
end

function M.setup(opts)
	config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	if config.side ~= "left" and config.side ~= "right" then
		error("side-bufs: side must be 'left' or 'right'")
	end
	if type(config.width) ~= "number" or config.width < 1 then
		error("side-bufs: width must be a positive number")
	end

	initialized = true
	setup_hl()
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("SideBufsHighlights", { clear = true }),
		callback = setup_hl,
	})
	vim.api.nvim_create_autocmd({
		"BufAdd",
		"BufDelete",
		"BufEnter",
		"BufFilePost",
		"BufModifiedSet",
		"BufWritePost",
		"DirChanged",
		"WinEnter",
		"WinResized",
	}, {
		group = vim.api.nvim_create_augroup("SideBufs", { clear = true }),
		callback = function()
			remember_main_win()
			vim.schedule(M.render)
		end,
	})
end

return M
