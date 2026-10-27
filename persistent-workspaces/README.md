# persistent-workspaces

Tern port of the herdr plugin `ankitg12/herdr-plugins/plugins/persistent-spaces`.

For each workspace (session) in the config:

1. **Pinned root.** A new tab opens in the workspace's root.
2. **Never empty.** When the workspace has 0 tabs (you closed the last one, or
   it starts empty), the plugin opens one tab in the root. So `Ctrl+Shift+T`
   always has a workspace to act in. This check runs on `window_start`,
   `tab_closed` and `focus` (a plugin reload does not re-run `window_start`).
   For a workspace that is not current, it switches there, opens the tab and
   switches back.

A workspace that is not in the config keeps Tern's built-in behaviour.

## Config

`~/.config/tern/persistent-workspaces.json` (per machine, because paths differ):

```json
{
  "workspaces": [
    { "name": "jeeves", "root": "~/agents/jeeves" },
    { "name": "home",   "root": "~" }
  ]
}
```

- `name` is the exact workspace name in the Tern sidebar (case-sensitive).
- `root` may start with `~`.
- An array, not an object, because `tern.json.decode` loses object member order
  and a later version will use the order for the sidebar.
- The plugin reads the file at every new tab. An edit applies at once.
- A bad file or a missing root shows a toast, and the built-in new tab runs.

## Install

```sh
ghq get ankitg12/tern-plugins
tern plugin link ~/repos/github.com/ankitg12/tern-plugins/persistent-workspaces
tern plugin list   # expect: persistent-workspaces 0.1.0 ... window  ready
```

## How it works

`tern.override("new_tab", fn)` in the window half. It covers the built-in
`new_tab` action (key `Ctrl+Shift+T`, tab-bar `+`). It does **not** cover a
plugin that calls `cx.layout:new_tab` itself, for example the `+` in
`rezhajulio/workspaces-sidebar` 0.1.8, and it does not change splits. On lx01
that sidebar's `+` is patched locally to call `cx:action("new_tab")`.

Do not test with `tern ctl run new_tab`: it types the text `new_tab` into the
focused pane; it does not run the action.

## Not yet ported from herdr persistent-spaces

- Recreate a pinned workspace at window start when it is missing
  (`cx.sessions:create({name, cwd})`).
- Lock pinned workspaces against an accidental close (`cx.sessions:lock`).
  Lower value now that an empty pinned workspace refills itself.
- Sidebar order from the array order.
