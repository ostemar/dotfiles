local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder()

local triple = wezterm.target_triple
local is_windows = triple:find("windows") ~= nil
local is_linux = triple:find("linux") ~= nil

config.initial_cols = 120
config.initial_rows = 28

config.font_size = 12
config.color_scheme = "Catppuccin Mocha"
config.font = wezterm.font("JetBrainsMono NF")

config.scrollback_lines = 10000
config.hide_tab_bar_if_only_one_tab = true
config.audible_bell = "Disabled"
config.window_padding = { left = 6, right = 6, top = 6, bottom = 6 }

if is_windows then
	config.default_prog = { "pwsh.exe", "-NoLogo" }
	config.default_cwd = "C:/code/osr"

	-- Frosted Windows 11 backdrop; needs opacity < 1 to show through.
	config.win32_system_backdrop = "Acrylic"
	config.window_background_opacity = 0.9

	config.launch_menu = {
		-- Default WSL distro, starting in the Linux home dir. Distro-agnostic:
		-- once a default distro is installed (e.g. `wsl --install Ubuntu`), this
		-- just works without naming it here.
		{ label = "pwsh", args = { "pwsh.exe", "-NoLogo" } },
		{ label = "WSL", args = { "wsl.exe", "--cd", "~" } },
		{ label = "Git Bash", args = { "C:/Program Files/Git/bin/bash.exe", "-i", "-l" }, cwd = "C:/code/osr" },
		{ label = "cmd", args = { "cmd.exe" } },
	}
elseif is_linux then
	-- No default_prog: WezTerm spawns the login shell from /etc/passwd, which
	-- scripts/setup.sh sets to zsh. Hardcoding bash here skipped .zshrc and p10k.
	-- config.enable_wayland = true  -- enable if you run Wayland; comment out on issues
end

-- Leader for pane management (vim/tmux style): press Ctrl+Space, then the key.
config.leader = { key = "Space", mods = "CTRL", timeout_milliseconds = 1000 }

config.keys = {
	-- Ctrl+Shift+L opens the launcher (overrides the default debug overlay, which
	-- is still reachable via the command palette, Ctrl+Shift+P).
	-- Only the curated launch_menu shows here; DOMAINS/TABS are omitted so WezTerm's
	-- auto-enumerated WSL distros (e.g. docker-desktop) and open tabs don't clutter it.
	{ key = "L", mods = "CTRL|SHIFT", action = act.ShowLauncherArgs({ flags = "FUZZY|LAUNCH_MENU_ITEMS" }) },

	-- Panes (after leader): s = split down, v = split right, w = close.
	{ key = "s", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "v", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "w", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },

	-- Navigate panes vim-style (after leader): h/j/k/l.
	{ key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
	{ key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
	{ key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },

	-- Resize panes (after leader): Shift + h/j/k/l.
	{ key = "H", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Left", 5 }) },
	{ key = "J", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Down", 5 }) },
	{ key = "K", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Up", 5 }) },
	{ key = "L", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },
}

return config
