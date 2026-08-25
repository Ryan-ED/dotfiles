# dotfiles

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/), with
[devbox](https://www.jetify.com/devbox) (Nix-backed) providing the actual dev
tooling. Goal: one repo, `chezmoi init --apply`, minimal per-machine upkeep.

## Machines

| Machine           | machineClass | Notes                                                        |
|-------------------|--------------|---------------------------------------------------------------|
| Windows 11 laptop | `wsl`        | Bootstraps inside WSL/Ubuntu, same as `standard`               |
| Arch Linux laptop | `standard`   | Throwaway/testing box                                         |
| Bazzite laptop    | `bazzite`    | Atomic/ostree — devbox+Nix run in a Distrobox container        |
| Fedora laptop     | `standard`   | Main daily driver                                              |

## How it fits together

1. **`.chezmoi.toml.tmpl`** prompts once (via `promptStringOnce`) for `machineClass`
   (`standard` / `bazzite` / `wsl`) and caches the answer in the generated
   `~/.config/chezmoi/chezmoi.toml`. You're only asked on first `chezmoi init`
   per machine; later `chezmoi apply` runs reuse it. To change it later, edit
   `machineClass` directly in `~/.config/chezmoi/chezmoi.toml` (or delete the
   file and re-init).

2. **`.chezmoiscripts/run_once_00-bootstrap-standard.sh.tmpl`** runs on
   `standard` and `wsl` machines (it no-ops and exits immediately when
   `machineClass == bazzite`). It:
   - installs [devbox](https://www.jetify.com/devbox) if missing, which pulls
     in Nix as a side effect of its own installer;
   - runs `devbox global install` to materialize the packages in
     `~/.local/share/devbox/global/default/devbox.json`;
   - appends `eval "$(devbox global shellenv)"` to `~/.bashrc` (and `~/.zshrc`
     if zsh is present), idempotently.

3. **`.chezmoiscripts/run_once_00-bootstrap-bazzite.sh.tmpl`** runs only when
   `machineClass == bazzite` (no-ops otherwise). Nix's installer is known to
   fight ostree/atomic hosts (it wants to own `/nix` and rewrite shell rc
   files in `/etc`, which rpm-ostree-based systems don't like). So instead:
   - creates a Fedora-based [Distrobox](https://distrobox.it/) container
     named `devbox` (skipped if it already exists);
   - installs devbox/Nix *inside* that container and runs
     `devbox global install` there, leaving the host untouched.

   Enter the container with `distrobox enter devbox`. To make an individual
   binary available on the host `PATH` without entering the container, use
   `distrobox-export --bin /path/in/container/to/bin`.

   Both `run_once_00-*` scripts share the `00-` prefix purely for readability
   in `chezmoi apply -n` output; chezmoi runs whichever one's `if` doesn't
   short-circuit, driven by `machineClass`, not by execution order.

4. **`private_dot_local/share/devbox/global/default/devbox.json`** is the
   single source of truth for global devbox packages, applied to
   `~/.local/share/devbox/global/default/devbox.json` (kept `private_` /
   0600 since devbox itself defaults to writing it that way). Current
   packages: `neovim`, `git`, `lazygit`, `ripgrep`, `fd`, `fzf`,
   `tree-sitter`, `gcc`, `curl`, `nerd-fonts.jetbrains-mono`. Add more by
   editing this file and running `chezmoi apply` — devbox reconciles
   installed packages against it.

   This list covers every item on
   [LazyVim's requirements](https://www.lazyvim.org/#-requirements): Neovim
   + Git for the editor itself, lazygit, ripgrep/fd/fzf for fzf-lua,
   tree-sitter + gcc for treesitter, curl for blink.cmp, and the Nerd Font
   for icons. WezTerm (below) already satisfies the "true color + undercurl
   terminal" requirement.

   **Caveat:** on `machineClass=wsl`, this bootstrap script (and the Nerd
   Font it installs) runs *inside* WSL, but WezTerm itself is a native
   Windows GUI process — it renders using fonts installed on the Windows
   host, not fonts sitting in the WSL filesystem. So on that machine you
   still need to install the JetBrainsMono Nerd Font on Windows itself
   (e.g. `winget install --id DEVCOM.JetBrainsMonoNerdFont`) for WezTerm to
   actually find the glyphs `wezterm.lua` asks for.

5. **`dot_config/wezterm/wezterm.lua`** sets
   `config.default_domain = "WSL:Ubuntu"` only when
   `wezterm.target_triple` contains `"windows"` (i.e. WezTerm itself is
   running natively on Windows, launching straight into WSL). On Linux
   machines this check is false and WezTerm uses its normal local domain.

6. **`dot_config/nvim/`** — a plain [LazyVim starter](https://github.com/LazyVim/starter)
   config (no pre-existing personal config was found on this machine, so it
   was scaffolded fresh from upstream: `init.lua`, `lua/config/*`,
   `lua/plugins/example.lua`, `stylua.toml`, plus `.gitignore`/`.neoconf.json`
   stored as `dot_gitignore`/`dot_neoconf.json` per chezmoi's naming
   convention). Add real plugin configs as extra files under
   `lua/plugins/`. Requires the `neovim` package from `devbox.json` above (or
   any Neovim ≥ 0.9 on `PATH`).

7. **`dot_config/hypr/`, `dot_config/i3/`, `dot_config/waybar/`** — Hyprland,
   i3, and Waybar configs pulled over verbatim from
   [Ryan-ED/dotfiles](https://github.com/Ryan-ED/dotfiles) (previously a
   Stow-style `<package>/.config/...` layout; flattened into chezmoi's
   `dot_config/...` convention, no content changes). They're inert until you
   actually install and launch Hyprland/i3/Waybar — chezmoi just makes sure
   `~/.config/hypr`, `~/.config/i3`, and `~/.config/waybar` are already
   populated the moment you do, on any current or future Linux box.

   **`.chezmoiignore.tmpl`** excludes all three when `machineClass == "wsl"`
   or the target OS isn't Linux (native Windows, macOS) — those environments
   have no compositor/X server to run a tiling WM against, so the files would
   just be dead weight. They apply on `standard` and `bazzite` Linux
   machines regardless of which desktop environment is currently active
   there.

## Usage

On a new machine, with chezmoi installed (via your OS package manager, or a
one-off `sh -c "$(curl -fsLS get.chezmoi.io)"` if chezmoi itself isn't
available yet):

```bash
chezmoi init --apply <git-remote-url>
```

You'll be prompted once for `machineClass`. After that, `chezmoi apply` is
enough to pick up dotfile changes; the bootstrap scripts only re-run when
their own template content changes (chezmoi tracks `run_once_*` scripts by
content hash).

To add packages later: edit `devbox.json` above, `chezmoi apply`, then
`devbox global install` (or just re-run the relevant bootstrap script's body
manually — it's idempotent).

### Bazzite caveat

The Bazzite bootstrap script assumes `distrobox` is already present on the
host (it ships by default on Bazzite; if not, install it before running
`chezmoi apply`). It creates the container but does not auto-export every
devbox binary to the host — do that per-binary with `distrobox-export` if you
want e.g. `nvim` callable directly from the host shell instead of via
`distrobox enter devbox`.
