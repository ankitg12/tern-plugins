-- link-tools: WezTerm-style link handling for Tern.
-- Routes skill://, local://, omp:// schemes; file paths go to the built-in
-- opener (origin "link"); search/open actions via palette commands.
--
-- NOTE: search-URL bases are placeholders. Copy this plugin and set your own
-- internal tracker/wiki hosts before linking.

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

tern.route.link(function(link, cx)
  local url = link.url or ""

  -- Shift-click copies a web link instead of following it.
  if link.mods and link.mods.shift and url:match("^https?://") then
    cx:copy(url)
    cx:toast("success", "Link copied", url)
    return { handled = true }
  end

  -- skill:// -> open the skill file.
  local sp = skill_path(url)
  if sp then
    return { path = sp }
  end

  -- local:// -> open the path.
  local lp = local_path(url)
  if lp then
    return { path = lp }
  end

  -- omp:// docs -> open the checkout file.
  local op = omp_path(url)
  if op then
    return { path = op }
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
