--!strict
-- persistent-workspaces, window half: each Tern workspace (session) can have
-- a pinned root directory. A new tab (`new_tab`, Ctrl+Shift+T, the tab-bar +)
-- in a pinned workspace opens in that root. Unpinned workspaces keep Tern's
-- built-in behaviour.
--
-- Config: ~/.config/tern/persistent-workspaces.json (see README.md). The file
-- is read at every new tab, so an edit applies at once, with no reload.

local HOME = tern.getenv("HOME") or ""
local CONFIG = HOME .. "/.config/tern/persistent-workspaces.json"

type Workspace = { name: string, root: string }

local function expand(path: string): string
	if path == "~" then
		return HOME
	end
	if string.sub(path, 1, 2) == "~/" then
		return HOME .. string.sub(path, 2)
	end
	return path
end

-- The pinned workspaces, in file order. A missing file means none; a bad
-- file shows a toast once per distinct error and also means none.
local last_error: string? = nil
local function load(cx: WindowCx): { Workspace }
	if not tern.fs.exists(CONFIG) then
		return {}
	end
	local ok, data = pcall(function()
		return tern.json.decode(tern.fs.read(CONFIG, 65536))
	end)
	if not ok or type(data) ~= "table" or type(data.workspaces) ~= "table" then
		local why = if ok then "needs a \"workspaces\" array" else tostring(data)
		if why ~= last_error then
			last_error = why
			cx:toast("error", "persistent-workspaces: cannot read config", why)
		end
		return {}
	end
	last_error = nil
	local out: { Workspace } = {}
	for _, w in data.workspaces do
		if type(w) == "table" and type(w.name) == "string" and type(w.root) == "string" then
			table.insert(out, { name = w.name, root = expand(w.root) })
		end
	end
	return out
end

-- The pinned root of the current workspace, or nil.
local function pinned_root(cx: WindowCx): string?
	local ok, cur = pcall(function()
		return cx.sessions:current()
	end)
	if not ok or cur == nil then
		return nil
	end
	for _, w in load(cx) do
		if w.name == cur.name then
			return w.root
		end
	end
	return nil
end

-- A falsy return lets the built-in new_tab run (unpinned workspace, or a
-- root that does not exist, which gets a toast).
tern.override("new_tab", function(cx: WindowCx): boolean
	local root = pinned_root(cx)
	if root == nil then
		return false
	end
	if not tern.fs.exists(root) then
		cx:toast("error", "persistent-workspaces: pinned root missing", root)
		return false
	end
	return cx.layout:new_tab({ cwd = root }) ~= nil
end)

-- Keep at least one tab in every pinned workspace: when a pinned workspace
-- has 0 tabs (its last tab closed, or it starts empty), open one in its root.
-- `cx.layout:new_tab` acts on the current workspace only, so an empty
-- workspace that is not current is switched to, filled, and the original
-- workspace is shown again.
local busy = false
local function refill_now(cx: WindowCx)
	local ok, sessions = pcall(function()
		return cx.sessions:list()
	end)
	if not ok then
		return
	end
	local roots: { [string]: string } = {}
	for _, w in load(cx) do
		roots[w.name] = w.root
	end
	local home: number? = nil
	for _, s in sessions do
		if s.current then
			home = s.id
		end
	end
	for _, s in sessions do
		local root = roots[s.name]
		if root ~= nil and s.tabs == 0 and tern.fs.exists(root) then
			if not s.current then
				cx.sessions:switch(s.id)
			end
			cx.layout:new_tab({ cwd = root })
		end
	end
	local now = cx.sessions:current()
	if home ~= nil and now.id ~= home then
		cx.sessions:switch(home)
	end
end

-- Switching workspaces inside refill_now fires more events; the guard stops
-- a nested refill.
local function refill(cx: WindowCx)
	if busy then
		return
	end
	busy = true
	local ok, err = pcall(refill_now, cx)
	busy = false
	if not ok then
		cx:toast("error", "persistent-workspaces: refill failed", tostring(err))
	end
end

-- window_start covers a new window; focus covers a plugin reload, which does
-- not re-run window_start; tab_closed covers closing the last tab.
tern.on("window_start", refill)
for _, name in { "tab_closed", "focus" } do
	tern.on(name, function(_ev, cx: WindowCx)
		refill(cx)
	end)
end
