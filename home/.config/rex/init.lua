-- Rex configuration
-- Bindings ported from ~/.config/herdr/config.toml, which ported them from
-- ~/.tmux.conf. Reload with `rex config reload`, or prefix+r.
-- Full reference: https://www.superlogical.com/rex/docs/reference/lua
--
-- Herdr terms map onto Rex like this: workspace = session, tab = tab (a
-- "window" in the CLI and Lua API), pane = pane (a "block").
--
-- Herdr bindings with no Rex equivalent yet, so not ported:
--   detach (prefix+d/q)     Rex sessions keep running when the app quits.
--   copy mode (prefix+v)    Rex has no copy mode yet.
--   edit scrollback         Not ported.
--   new/open worktree       No worktree support.
--   rename pane             Rex has no text prompt for custom actions.
--   focus agent 1-9         The Activity sidebar replaces Herdr's Agent panel.
--   notification target     Not ported.

local TERMINAL = "com.superlogical.terminal"

local P = "ctrl+a>"

local function prefix(key, action, args)
  rex.bind(P .. key, action, args)
end

-- Ctrl+A no longer reaches the terminal on its own, so press it twice to send
-- one (beginning of line in the shell).
prefix("ctrl+a", "pane.send_key", { key = "ctrl+a" })

-- -----------------------------------------------------------------------------
-- General
-- -----------------------------------------------------------------------------

prefix("shift+/", "client.palette.toggle") -- prefix+?, Herdr's help
prefix("shift+s", "client.settings")
prefix("r", "client.config.reload")
prefix("b", "client.sidebar.toggle")

-- -----------------------------------------------------------------------------
-- Sessions (Herdr workspaces)
-- -----------------------------------------------------------------------------

prefix("shift+n", "session.new")
prefix("shift+w", "session.rename")
prefix(",", "session.rename")
prefix("shift+d", "session.close")
prefix("s", "session.switch")
prefix("w", "session.switch")
prefix("g", "session.switch")

-- -----------------------------------------------------------------------------
-- Tabs
-- -----------------------------------------------------------------------------

prefix("c", "client.tab.new")
prefix("shift+,", "client.tab.rename")
prefix("shift+x", "client.tab.close")
prefix("p", "client.tab.previous")
prefix("ctrl+p", "client.tab.previous")
prefix("n", "client.tab.next")
prefix("ctrl+n", "client.tab.next")
for i = 1, 9 do
  prefix(tostring(i), "client.tab.goto", { index = i })
end

-- -----------------------------------------------------------------------------
-- Panes
-- -----------------------------------------------------------------------------

prefix("/", "pane.split", { direction = "right" })
prefix("enter", "pane.split", { direction = "down" })

-- Herdr's close_pane: closing the last pane in a tab closes the tab, and
-- closing the last tab closes the session.
rex.action{
  name = "close_pane",
  title = "Close Pane, Tab, or Session",
  category = "Pane",
  keywords = "close pane tab session kill",
  run = function(ctx, args)
    local view, err = rex.session.view{}
    if view == nil then error(err, 0) end
    for _, window in ipairs(view.windows or {}) do
      for _, layer in ipairs(window.layers or {}) do
        for _, block in ipairs(layer.blocks or {}) do
          if block.block_id == ctx.block_id then
            if layer.kind ~= "tiled" or #layer.blocks > 1 then
              rex.client.queue("pane.close")
            elseif #view.windows > 1 then
              rex.client.queue("client.tab.close")
            else
              rex.client.queue("session.close")
            end
            return
          end
        end
      end
    end
    rex.client.queue("pane.close")
  end,
}
prefix("x", "close_pane")
prefix("m", "pane.zoom")
prefix("tab", "pane.focus_next")
prefix("shift+tab", "pane.focus_previous")

local keys = { h = "left", j = "down", k = "up", l = "right" }

for key, direction in pairs(keys) do
  prefix(key, "pane.focus", { direction = direction, wrap = false })
  -- Herdr swaps with the neighbour; Rex moves the pane past it instead.
  prefix("shift+" .. key, "pane.move", { direction = direction })
end

-- Resize mode: hjkl or arrows resize, shift for bigger steps, = balances,
-- Enter or Escape leaves.
rex.mode("resize", { exclusive = true })
prefix("shift+r", "client.mode.enter", { name = "resize" })
for key, direction in pairs(keys) do
  for _, k in ipairs({ key, direction }) do
    rex.bind("resize/" .. k, "pane.resize", { direction = direction })
    rex.bind("resize/shift+" .. k, "pane.resize", { direction = direction, amount = 15 })
  end
end
rex.bind("resize/=", "pane.balance")
rex.bind("resize/enter", "client.mode.exit")

-- -----------------------------------------------------------------------------
-- Neovim navigation
-- -----------------------------------------------------------------------------

-- Seamless Ctrl+h/j/k/l between Neovim splits and Rex panes, replacing the
-- vim-herdr-navigation plugin. When Neovim is in the foreground the key is
-- forwarded to it; anything else moves pane focus. When there is no pane that
-- way, the key goes to the terminal, except Ctrl+L: clearing pi by accident
-- when there's no pane to the right was worse than losing the shortcut, so
-- clearing lives on Cmd+Shift+L instead. The Neovim side lives in
-- ~/.config/nvim/after/plugin/herdr-navigation.lua and runs `rex focus` at a
-- split edge.
--
-- These are actions rather than functions bound directly to the keys, because
-- direct function bindings don't fire from the keyboard in this beta.
local EDITORS = { nvim = true, vim = true, vi = true }

local function runs_editor(block_id)
  local process = rex.block.call(TERMINAL, "process", { block_id = block_id })
  local foreground = process and process.foreground
  return foreground ~= nil and EDITORS[foreground.name] == true
end

local function focused_block(view)
  for _, window in ipairs(view and view.windows or {}) do
    if window.window_id == view.active_window_id then
      return window.focused_block_id
    end
  end
end

for key, direction in pairs(keys) do
  local name = "navigate_" .. direction
  rex.action{
    name = name,
    title = "Navigate " .. direction:gsub("^%l", string.upper) .. " (Neovim/Rex)",
    category = "Pane",
    run = function(ctx, args)
      if not (ctx.block_id and runs_editor(ctx.block_id)) then
        local before = focused_block(rex.session.view{})
        rex.session.focus_direction{ direction = direction, wrap = false }
        if focused_block(rex.session.view{}) ~= before then return end
        if key == "l" then return end
      end
      rex.client.queue("pane.send_key", { key = "ctrl+" .. key })
    end,
  }
  rex.bind("ctrl+" .. key, name)
end

rex.bind("cmd+shift+l", "pane.send_key", { key = "ctrl+l" })
