local wezterm = require("wezterm")

local config = wezterm.config_builder()

-- 1. Detect the Operating System
local is_windows = wezterm.target_triple:find("windows") ~= nil
local is_mac = wezterm.target_triple:find("apple") ~= nil
local is_linux = wezterm.target_triple:find("linux") ~= nil

-- 2. Shared/Universal Configurations
config.color_scheme = 'Tokyo Night'
-- Nerd Font variant (not plain "JetBrains Mono") so LazyVim's file/diagnostic icons render.
config.font = wezterm.font('JetBrainsMono Nerd Font Mono')
config.font_size = 11.0

-- 3. OS-Specific Adjustments
if is_windows then
    -- Default into WSL as a proper multiplexer domain (new tabs/panes stay in WSL too),
    -- rather than just launching wsl.exe as the local domain's shell program.
    config.default_domain = "WSL:Ubuntu"
    config.font_size = 10.0 -- Fonts can render differently on Windows
    
elseif is_mac then
    -- Make the titlebar blend in beautifully on macOS
    config.window_decorations = "RESIZE"
    config.font_size = 12.0
    
elseif is_linux then
    -- Enable Wayland if available, fallback to X11
    config.enable_wayland = true
end

-- 4. Cross-Platform Keybindings
-- Uses 'ALT' as a universal modifier instead of 'CMD' (Mac) or 'CTRL' (Windows/Linux)
config.keys = {
  {
    key = 'd',
    mods = 'ALT',
    action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' },
  },
  {
    key = 'D',
    mods = 'ALT|SHIFT',
    action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' },
  },
}

return config

