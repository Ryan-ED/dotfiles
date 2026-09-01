# dotfiles

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/), with
[devbox](https://www.jetify.com/devbox) (Nix-backed) providing the actual dev
tooling. Goal: one repo, `chezmoi init --apply`, minimal per-machine upkeep.

## Machines

| Machine           | machineClass | Notes                                                        |
|-------------------|--------------|---------------------------------------------------------------|
| Windows 11 laptop | `wsl`        | `chezmoi apply` run **inside WSL/Ubuntu** for devbox/tooling, **and separately on native Windows** for WezTerm's config — see "WSL + native Windows" below |
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
   `machineClass == bazzite`, or when `.chezmoi.os == "windows"` — devbox/Nix
   aren't supported on native Windows at all, so this only ever does real
   work inside WSL/Linux/macOS). It:
   - installs [devbox](https://www.jetify.com/devbox) if missing, which pulls
     in Nix as a side effect of its own installer;
   - runs `devbox global install` to materialize the packages in
     `~/.local/share/devbox/global/default/devbox.json`;
   - appends `eval "$(devbox global shellenv)"`, `eval "$(starship init
     bash/zsh)"`, and `eval "$(fnm env --use-on-cd)"` to `~/.bashrc` (and
     `~/.zshrc` if zsh is present), idempotently — shellenv first, since
     `starship` and `fnm` are themselves devbox packages and need to already
     be on `PATH` before their own init commands can run.

3. **`.chezmoiscripts/run_once_00-bootstrap-bazzite.sh.tmpl`** runs only when
   `machineClass == bazzite` (no-ops otherwise). Nix's installer is known to
   fight ostree/atomic hosts (it wants to own `/nix` and rewrite shell rc
   files in `/etc`, which rpm-ostree-based systems don't like). So instead:
   - creates a Fedora-based [Distrobox](https://distrobox.it/) container
     named `devbox` (skipped if it already exists);
   - installs devbox/Nix *inside* that container and runs
     `devbox global install` there, leaving the host untouched, appending the
     same `devbox global shellenv` + `starship init bash` + `fnm env
     --use-on-cd` lines to the container's own `~/.bashrc`.

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
   `tree-sitter`, `gcc`, `curl`, `nerd-fonts.jetbrains-mono`, `starship`,
   `fnm`, `pnpm`. Add more by editing this file and running `chezmoi apply`
   — devbox reconciles installed packages against it. `starship` ships with
   sensible defaults, so there's no `starship.toml` here yet — add one later
   if you want a themed prompt.

   **`fnm`** (Fast Node Manager) covers per-project Node versions the way
   [nvm](https://github.com/nvm-sh/nvm) would, reading the same `.nvmrc`
   files — nvm itself has no Nix package because it isn't a binary at all,
   just a shell script meant to be sourced, which doesn't map onto Nix's
   model. `fnm` is a real Nix-packaged binary, but worth being clear about
   what that does and doesn't buy you: the *switcher* is reproducible, but
   the actual Node.js versions it downloads per project land in `~/.local/
   share/fnm`, outside the Nix store and untracked by this repo — same as
   nvm's runtimes always were. A fully Nix-native alternative exists (a
   per-project `devbox.json` pinning `nodejs@X`, auto-activated via direnv),
   but only helps in repos that adopt devbox themselves; `fnm` was chosen
   here so version-switching still works in any project with a plain
   `.nvmrc`, regardless of whether it uses devbox.

   **`pnpm`** is the package manager (npm/yarn alternative — shared
   content-addressable store, strict dependency resolution), a separate
   concern from `fnm` (which Node *runtime* you're on). They're kept side
   by side deliberately rather than dropping `fnm` in favor of pnpm's own
   `pnpm env use`: pnpm's version switching is explicit/manual and only
   applies within `pnpm` commands, whereas `fnm`'s shell hook rewrites
   `node` on `PATH` automatically for *any* invocation (`node script.js`,
   other tools that shell out to it) the moment you `cd` into a project —
   keeping both means that still works even for commands that never go
   through `pnpm`. No shell-hook needed for `pnpm` itself — it works
   straight off `PATH` once devbox's shellenv is sourced. One thing it
   doesn't cover: `PNPM_HOME` + a `PATH` entry for *global* installs
   (`pnpm add -g <tool>`) aren't set up here, since they're only needed if
   you start installing CLI tools globally via pnpm — add them to the
   bootstrap script's rc-file lines later if that comes up.

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

   **Caveat:** WezTerm must be installed natively on Windows (`winget install
   wez.wezterm`), never inside WSL — it's a GUI app, and the WSL domain
   setting above is what makes *it* open WSL shells, not a reason to install
   it there. But that also means its config needs to live at
   `%USERPROFILE%\.config\wezterm\wezterm.lua` on the Windows side, which
   `chezmoi apply` run *inside* WSL never touches (WSL's `~` resolves inside
   the Linux filesystem, a different path entirely). So on the `wsl` machine,
   you run `chezmoi init --apply <repo>` twice: once inside WSL (for
   devbox/nvim/starship), and once with chezmoi installed natively on Windows
   (for `wezterm.lua` and anything else under `dot_config/`) — see "WSL +
   native Windows" under Usage. The native-Windows run answers the same
   `machineClass=wsl` prompt but the bootstrap script no-ops there by design
   (see item 2's OS guard), so it only ever deploys plain files.

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

On a new machine if chezmoi itself isn't available yet,
install it via your OS package manager, or a one-off:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)"
```

With chezmoi installed:

```bash
chezmoi init --apply https://github.com/Ryan-ED/dotfiles # or your <git-remote-url>
```

You'll be prompted once for `machineClass`. After that, `chezmoi apply` is
enough to pick up dotfile changes; the bootstrap scripts only re-run when
their own template content changes (chezmoi tracks `run_once_*` scripts by
content hash).

To add packages later: edit `devbox.json` above, `chezmoi apply`, then
`devbox global install` (or just re-run the relevant bootstrap script's body
manually — it's idempotent).

### WSL + native Windows

The Windows 11 laptop needs `chezmoi init --apply <repo>` run in **two
places**, because devbox/Nix work inside WSL but WezTerm's config has to
land in the native Windows profile:

1. **Inside WSL/Ubuntu** — installs chezmoi + git there if needed, then
   `chezmoi init --apply <repo>`, answering `wsl` at the prompt. This does
   the real work: devbox, Nix, starship, the nvim config.
2. **Natively on Windows** — install chezmoi itself
   (`winget install twpayne.chezmoi`), then run the same
   `chezmoi init --apply <repo>` from PowerShell, answering `wsl` again (it's
   a separate per-OS chezmoi config, so it asks again). The bootstrap script
   no-ops immediately here (native Windows isn't Linux/macOS), so this run
   just deploys plain dotfiles — in practice, `wezterm.lua`.

One thing to verify on that second, native-Windows run: chezmoi executes
`.sh.tmpl` scripts by finding a `sh` interpreter on `PATH`, and even though
our script no-ops immediately for `chezmoi.os == "windows"`, chezmoi still
needs to *find* an interpreter to run it at all. Git for Windows (ships
`sh.exe`) covers this in practice; if it's ever missing, that one script step
would error rather than silently skip.

### Bazzite caveat

The Bazzite bootstrap script assumes `distrobox` is already present on the
host (it ships by default on Bazzite; if not, install it before running
`chezmoi apply`). It creates the container but does not auto-export every
devbox binary to the host — do that per-binary with `distrobox-export` if you
want e.g. `nvim` callable directly from the host shell instead of via
`distrobox enter devbox`.

### Manual installs (by design)

Two things are deliberately **not** part of any bootstrap script, kept
manual on purpose rather than automated:

- **WezTerm itself.** Only its config (`dot_config/wezterm/wezterm.lua`,
  item 5 above) is managed here — the application is installed separately,
  per OS: `winget install wez.wezterm` on Windows, your distro's package
  manager or `flatpak install flathub org.wezfurlong.wezterm` on Linux
  (Flatpak specifically on Bazzite — see the Bazzite caveat above for why
  devbox/Distrobox isn't the right place for it), `brew install --cask
  wezterm` on macOS. It was left out of `devbox.json` because it's a GUI app
  with real GPU/OpenGL rendering, and Nix-packaged GUI apps on non-NixOS
  Linux sometimes hit graphics-driver mismatches that OS-native packaging
  avoids — not worth the risk for the one application you'd be using to fix
  things if it broke.

- **Switching to zsh.** The bootstrap script writes identical `devbox
  global shellenv` / `starship init` / `fnm env` lines to *both* `.bashrc`
  and `.zshrc` so either shell works, but it never installs zsh or runs
  `chsh` to make it your login shell. That's a manual, one-time step:
  ```bash
  sudo apt install zsh      # or pacman/dnf, depending on distro
  chsh -s $(which zsh)
  ```
  then open a new terminal. Reasoning: every script in this repo so far is
  deliberately unprivileged (no `sudo`, one of the actual selling points of
  devbox/Nix) — automating this would mean the first `sudo` call in the
  whole setup, plus per-distro package-manager branching, just to save one
  copy-pasted command.

  **Ordering matters on a brand-new machine.** The bootstrap script decides
  whether to touch `.zshrc` at all with a single check — `command -v zsh`,
  i.e. "does zsh exist right now" — at the one and only moment it ever runs
  (it's `run_once_*`, tracked by content hash, so it never re-checks later).
  So on a **new** machine, install and switch to zsh *before* running
  `chezmoi init --apply`:
  ```bash
  sudo apt install zsh      # or pacman/dnf, depending on distro
  chsh -s $(which zsh)
  ```
  then `chezmoi init --apply <repo>`. Done in that order, the bootstrap
  script's zsh check passes on its one run, and `.zshrc` gets the same
  `devbox global shellenv` / `starship init zsh` / `fnm env` lines as
  `.bashrc` automatically — no manual copying needed.

  If zsh gets installed *after* chezmoi already bootstrapped that machine
  (i.e. the order this repo's own WSL machine actually went through), the
  script won't retroactively populate a `.zshrc` that didn't exist yet at
  that time — copy the three `eval` lines over from `.bashrc` manually
  (swap `starship init bash` for `starship init zsh`).

## Making changes and syncing them everywhere

Example: you tweak `~/.config/wezterm/wezterm.lua` on one machine and want
that change on all the others. No manual copying between machines — git does
all the syncing, chezmoi just knows how to turn `dot_config/wezterm/
wezterm.lua` back into `~/.config/wezterm/wezterm.lua` (and vice versa) on
each box.

**1. Edit the file — either the live target or the source, your choice:**
- **Live file** (`~/.config/wezterm/wezterm.lua`) — quick, and lets you
  test the change immediately since WezTerm reads that path directly.
- **Source file** — run `chezmoi edit ~/.config/wezterm/wezterm.lua`, which
  opens the corresponding file in `~/.local/share/chezmoi/dot_config/
  wezterm/wezterm.lua` in your `$EDITOR`. Skips step 2 below.

**2. Pull a live edit back into the source state** (only needed if you
edited the live file directly):
```bash
chezmoi re-add ~/.config/wezterm/wezterm.lua
```
This copies your live edit into `~/.local/share/chezmoi/dot_config/wezterm/
wezterm.lua`, overwriting what was there. Safe for plain files like this one
(no `.tmpl` suffix, no template logic) — for a templated file, `re-add`
captures the machine's already-*rendered* output rather than the template
source, so check `chezmoi diff` first before trusting it there.

**3. Sanity check before committing:**
```bash
chezmoi diff
```
Should show no pending diff now — source and target match.

**4. Commit and push from the source repo:**
```bash
chezmoi cd          # drops you into ~/.local/share/chezmoi
git add -A
git commit -m "tweaked wezterm font size"
git push
exit                 # back to your normal shell
```

**5. On every other machine, pull and apply in one shot:**
```bash
chezmoi update
```
This runs `git pull` inside the source repo and then `chezmoi apply`
immediately, so the change lands right away. To preview first: `chezmoi
update -n` (dry run), then `chezmoi update` for real.

So the full cycle is: edit → `re-add` (only if you edited the live file) →
commit/push from the source repo → `chezmoi update` everywhere else.
