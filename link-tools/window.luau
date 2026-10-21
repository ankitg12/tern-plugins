-- link-tools: WezTerm-style link handling for Tern.
-- Routes skill://, local://, omp:// schemes; file paths go to the built-in
-- opener (origin "link"); search/open actions via palette commands.

-- Percent-decode a URI component.
local function url_decode(s)
  return (s:gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end))
end

-- skill://name/path -> ~/skills/name/path (adjust root to taste).
local function skill_path(url)
  local name, rest = url:match("^skill://([%w_.-]+)/*(.*)$")
  if not name then
    return nil
  end
  local home = os.getenv("HOME") or ""
  local p = home .. "/skills/" .. name
  if rest and rest ~= "" then
    p = p .. "/" .. rest
  end
  return p
end

-- local://path -> absolute path (relative to pane cwd when needed).
local function local_path(url)
  local p = url:match("^local://(.*)$")
  if not p then
    return nil
  end
  return url_decode(p)
end

-- omp://path -> materialize via checkout docs path fallback.
-- omp:// docs live in the oh-my-pi checkout; other paths pass through.
local function omp_path(url)
  local rel = url:match("^omp://(.*)$")
  if not rel then
    return nil
  end
  local home = os.getenv("HOME") or ""
  local checkout = home .. "/repos/github.com/can1357/oh-my-pi/docs/" .. rel
  local f = io.open(checkout, "r")
  if f then
    f:close()
    return checkout
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

-- Palette: search actions on the clipboard text (mirrors WezTerm right-click menu).
local function search_url(base)
  return function(cx)
    local text = cx:paste() or ""
    text = text:gsub("^%s*(.-)%s*$", "%1")
    if text == "" then
      cx:toast("info", "Link Tools", "Clipboard is empty")
      return
    end
    -- Minimal percent-encoding for the query.
    local q = text:gsub("[^%w%-%.%_%~]", function(c)
      return string.format("%%%02X", string.byte(c))
    end)
    cx:open_url(base .. q)
  end
end

tern.command({
  id = "search-google",
  title = "Search Google for clipboard",
  icon = "globe",
  run = search_url("https://www.google.com/search?q="),
})

tern.command({
  id = "search-hn",
  title = "Search HN for clipboard",
  icon = "globe",
  run = search_url("https://hn.algolia.com/?q="),
})

tern.command({
  id = "search-jira",
  title = "Search Jira for clipboard",
  icon = "tag",
  run = search_url("https://pensando.atlassian.net/secure/QuickSearch.jspa?searchString="),
})

tern.command({
  id = "open-clipboard-url",
  title = "Open clipboard text as URL",
  icon = "globe",
  run = function(cx)
    local text = cx:paste() or ""
    text = text:gsub("^%s*(.-)%s*$", "%1")
    if text == "" then
      cx:toast("info", "Link Tools", "Clipboard is empty")
      return
    end
    if not text:match("^https?://") then
      text = "https://" .. text
    end
    cx:open_url(text)
  end,
})
