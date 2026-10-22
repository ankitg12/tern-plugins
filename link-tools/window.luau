-- External-first opens: file clicks (origin "link") open in the OS default
-- program via `open(1)` — no Tern pane, no vim tab. skill://, local://,
-- omp:// resolve to paths and open the same way.
--
-- Web links pass through to Tern's built-in handling (link_target=Browser).
-- origin "cli"/"carly" (tern open from scripts, OMP/agent) pass through —
-- we only claim origin "link" (clicked paths in panes).
--
-- NOTE: search-URL bases are placeholders. Copy this plugin and set your own
-- internal tracker/wiki hosts before linking.

-- `open(1)` on macOS. Callback form: fire-and-forget, click returns immediately.
local function os_open(target)
  tern.process.run({ "open", target }, function(_res) end)
end

-- Percent-decode a URI component.
local function url_decode(s)
  return (s:gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end))
end

-- skill://name/path -> ~/.omp/agent/skills/name/path (managed-skills first).
local function skill_path(url)
  local name, rest = url:match("^skill://([%w_.-]+)/*(.*)$")
  if not name then
    return nil
  end
  local home = os.getenv("HOME") or ""
  local roots = {
    home .. "/.omp/agent/managed-skills/",
    home .. "/.omp/agent/skills/",
  }
  for _, root in ipairs(roots) do
    local p = root .. name
    if rest and rest ~= "" then
      p = p .. "/" .. rest
    end
    local f = io.open(p, "r")
    if f then
      f:close()
      return p
    end
  end
  return nil
end

-- local://path -> absolute path (relative to pane cwd when needed).
local function local_path(url)
  local p = url:match("^local://(.*)$")
  if not p then
    return nil
  end
  return url_decode(p)
end

-- omp://path -> oh-my-pi checkout docs (adjust root to your checkout).
local function omp_path(url)
  local rel = url:match("^omp://(.*)$")
  if not rel then
    return nil
  end
  local home = os.getenv("HOME") or ""
  local candidates = {
    home .. "/ghq/github.com/ankitg12/oh-my-pi/" .. rel,
    home .. "/ghq/github.com/ankitg12/oh-my-pi/docs/" .. rel,
  }
  for _, p in ipairs(candidates) do
    local f = io.open(p, "r")
    if f then
      f:close()
      return p
    end
  end
  return nil
end

-- Expand ~ and split trailing :line[:col] the terminal passes through.
local function split_location(p)
  local home = os.getenv("HOME") or ""
  if p:sub(1, 2) == "~/" then
    p = home .. p:sub(2)
  elseif p == "~" then
    p = home
  end
  local path, line, col = p:match("^(.-):(%d+):?(%d*)$")
  if path and path ~= "" then
    local f = io.open(path, "r")
    if f then
      f:close()
      return path, tonumber(line), col ~= "" and tonumber(col) or nil
    end
  end
  return p, nil, nil
end

tern.route.link(function(link, cx)
  local url = link.url or ""

  -- Shift-click copies a web link instead of following it.
  if link.mods and link.mods.shift and url:match("^https?://") then
    cx:copy(url)
    cx:toast("success", "Link copied", url)
    return { handled = true }
  end

  -- skill:// / local:// / omp:// -> resolve and open externally.
  local sp = skill_path(url)
  if sp then
    os_open(sp)
    return { handled = true }
  end
  local lp = local_path(url)
  if lp then
    os_open(lp)
    return { handled = true }
  end
  local op = omp_path(url)
  if op then
    os_open(op)
    return { handled = true }
  end

  return nil
end)

-- Palette: open clipboard text as URL (cx:open with no `how` follows links).
tern.command({
  id = "open-clipboard-url",
  title = "Open clipboard text as URL",
  icon = "globe",
  run = function(cx)
    -- No cx:paste in the window API; type into a scratch read via run is
    -- overkill — instruct instead. Kept minimal on purpose.
    cx:toast("info", "Link Tools", "Copy a URL first, then click it in a pane")
  end,
})

-- External-first file opens: claim origin "link" (clicked paths) and open in
-- the OS default program. Everything else (palette/files/drop/system/cli/carly)
-- passes through, so `tern open` from scripts and OMP/agent keeps working.
tern.route.open(function(req, cx)
  if req.origin ~= "link" then
    return nil
  end
  local path, _line, _col = split_location(req.path)
  os_open(path)
  return { handled = true }
end)

-- Open URLs visible in the focused pane (WezTerm-style safety net).
-- Terminal panes already get clickable links from Tern's own detectors, but
-- native tool-output code blocks (e.g. omp Bash cards) carry no link element
-- for any route to claim — so harvest http(s) URLs from pane text instead.
local function clean_url(raw)
  local u = raw:gsub("[.,;:!?]+$", "")
  u = u:gsub("[%)%]%}]+$", "")
  u = u:gsub("['\"]+$", "")
  u = u:gsub(">$", "")
  return u
end

local function harvest_urls(lines)
  local out, seen = {}, {}
  for _, line in ipairs(lines) do
    if type(line) == "string" and line:find("http", 1, true) then
      for raw in line:gmatch("https?://[^%s\"'<>%[%]{}|%^`]+") do
        local u = clean_url(raw)
        if #u > 10 and not seen[u] then
          seen[u] = true
          local ctx = line:gsub("^%s+", ""):gsub("%s+", " ")
          if #ctx > 90 then ctx = ctx:sub(1, 87) .. "..." end
          table.insert(out, { url = u, context = ctx })
        end
      end
    end
  end
  return out
end

local function pane_text_lines(cx, pane)
  local lines = {}
  local ok, res = pcall(function()
    return cx.session:read(pane, { lines = 2000, scrollback = true, max_chars = 64000 })
  end)
  if ok then
    if type(res) == "string" then
      table.insert(lines, res)
    elseif type(res) == "table" and type(res.lines) == "table" then
      for _, l in ipairs(res.lines) do
        table.insert(lines, l)
      end
    end
  end
  local ok2, msgs = pcall(function()
    return cx.agents:transcript(pane, { last = 50 })
  end)
  if ok2 and type(msgs) == "table" then
    for _, m in ipairs(msgs) do
      if type(m) == "table" then
        if type(m.text) == "string" and #m.text > 0 then
          table.insert(lines, m.text)
        end
        if type(m.tools) == "table" then
          for _, t in pairs(m.tools) do
            if type(t) == "string" then
              table.insert(lines, t)
            elseif type(t) == "table" then
              for _, v in pairs(t) do
                if type(v) == "string" and #v > 0 then
                  table.insert(lines, v)
                end
              end
            end
          end
        end
      end
    end
  end
  return lines
end

tern.command({
  id = "open-pane-url",
  title = "Open URL from focused pane",
  icon = "globe",
  -- No default chord: runs from the palette ("Open URL from focused pane") or
  -- a user binding of action plugin.link-tools.open-pane-url.
  run = function(cx)
    local pane = cx.session:focused()
    if not pane then
      cx:toast("warn", "Link Tools", "No focused pane")
      return
    end
    local found = harvest_urls(pane_text_lines(cx, pane))
    if #found == 0 then
      cx:toast("info", "Link Tools", "No URLs in the focused pane")
      return
    end
    if #found == 1 then
      cx:open(found[1].url)
      return
    end
    local items = {}
    for i, f in ipairs(found) do
      if i > 50 then break end
      table.insert(items, { label = f.url, detail = f.context, url = f.url })
    end
    cx:pick({ items = items, placeholder = "Open URL from pane", icon = "globe", action = "open" })
      :next(function(choice, _err, cx2)
        if choice and type(choice.url) == "string" then
          (cx2 or cx):open(choice.url)
        end
      end)
  end,
})
