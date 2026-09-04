# dotfiles

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/), with
[devbox](https://www.jetify.com/devbox) (Nix-backed) providing the actual dev
tooling. Goal: one repo, `chezmoi init --apply`, minimal per-machine upkeep.

## Machines

| Machine           | machineClass | Notes                                                        |
|-------------------|--------------|---------------------------------------------------------------|
| Windows 11 laptop | `wsl`        | `chezmoi apply` run **inside WSL/Ubuntu** for devbox/tooling, **and separately on native Windows** for WezTerm's config — see "First-time setup → WSL" below |
| Arch Linux laptop | `standard`   | Throwaway/testing box                                         |
| Bazzite laptop    | `bazzite`    | Atomic/ostree — devbox+Nix run in a Distrobox container        |
| Fedora laptop     | `standard`   | Main daily driver                                              |

## How it fits together

1. **`.chezmoi.toml.tmpl`** prompts once (via `promptStringOnce`) for `machineClass`
   (`standard` / `bazzite` / `wsl`), plus `gitName` and `gitEmail`, and caches
   the answers in the generated `~/.config/chezmoi/chezmoi.toml`. You're only
   asked on first `chezmoi init` per machine; later `chezmoi apply` runs reuse
   them. To change any of these later, edit the value directly in
   `~/.config/chezmoi/chezmoi.toml` (or delete the file and re-init).
   `gitName`/`gitEmail` are prompted rather than hardcoded specifically so the
   actual values only ever live in that per-machine, uncommitted config file —
   never in this (public) repo's git history.

2. **`dot_gitconfig.tmpl`** → `~/.gitconfig`, templated from `gitName`/
   `gitEmail` above, so a fresh `git commit` on a new machine never hits git's
   "Please tell me who you are" error. Also sets `init.defaultBranch = main`
   directly (not prompted — same value everywhere, nothing personal about it).

3. **`.chezmoiscripts/run_once_00-bootstrap-standard.sh.tmpl`** runs on
   `standard` and `wsl` machines (it no-ops and exits immediately when
   `machineClass == bazzite`, or when `.chezmoi.os == "windows"` — devbox/Nix
   aren't supported on native Windows at all, so this only ever does real
   work inside WSL/Linux/macOS). It:
   - installs [devbox](https://www.jetify.com/devbox) if missing, which pulls
     in Nix as a side effect of its own installer;
   - runs `devbox global install` to materialize the packages in
     `~/.local/share/devbox/global/default/devbox.json`;
   - on Linux only (macOS uses Core Text, not fontconfig, for font lookup),
     registers devbox's font directory
     (`.devbox/nix/profile/default/share/fonts`) in
     `~/.config/fontconfig/fonts.conf` and runs `fc-cache -f` — Nix doesn't
     register its installed fonts with the host's fontconfig on non-NixOS
     systems by default, so without this, apps outside devbox's own shell
     (anything not sourcing `devbox global shellenv`) can't see fonts like
     `nerd-fonts.jetbrains-mono` at all;
   - appends `eval "$(devbox global shellenv)"`, `eval "$(starship init
     bash)"`, and `eval "$(fnm env --use-on-cd)"` to `~/.bashrc`,
     idempotently — shellenv first, since `starship` and `fnm` are
     themselves devbox packages and need to already be on `PATH` before
     their own init commands can run. `.zshrc` needs none of this appended
     to it — it's a fully chezmoi-managed file in its own right, see item 5.

4. **`.chezmoiscripts/run_once_00-bootstrap-bazzite.sh.tmpl`** runs only when
   `machineClass == bazzite` (no-ops otherwise). Nix's installer is known to
   fight ostree/atomic hosts (it wants to own `/nix` and rewrite shell rc
   files in `/etc`, which rpm-ostree-based systems don't like). So instead:
   - creates a Fedora-based [Distrobox](https://distrobox.it/) container
     named `devbox` (skipped if it already exists);
   - installs devbox/Nix *inside* that container and runs
     `devbox global install` there, leaving the host untouched, appending the
     same `devbox global shellenv` + `starship init bash` + `fnm env
     --use-on-cd` lines to the container's own `~/.bashrc` — wrapped in
     `if [ -f /run/.containerenv ]; then ... fi`. That guard matters because
     Distrobox shares `$HOME` between host and container, so this is
     literally the *same* `~/.bashrc` the bare Bazzite host uses too; without
     it, every plain host terminal (never entering the container at all)
     would print "command not found" for devbox/starship/fnm on every
     startup, since those only exist inside the container's own filesystem;
   - then, back on the actual **host** (not inside the container): registers
     that same devbox font directory in the host's own
     `~/.config/fontconfig/fonts.conf` and runs `fc-cache -f`. Distrobox
     shares `$HOME` between host and container, so the font files already
     exist at that path on the host's disk — but the host's fontconfig was
     never told to look there, and a Flatpak-installed WezTerm runs on the
     host, never inside the container, so it'd otherwise never see them.

   Enter the container with `distrobox enter devbox`. To make an individual
   binary available on the host `PATH` without entering the container, use
   `distrobox-export --bin /path/in/container/to/bin`.

   Both `run_once_00-*` scripts share the `00-` prefix purely for readability
   in `chezmoi apply -n` output; chezmoi runs whichever one's `if` doesn't
   short-circuit, driven by `machineClass`, not by execution order.

5. **`dot_zshrc.tmpl`** → `~/.zshrc`, fully chezmoi-managed rather than
   appended to by a bootstrap script (unlike `.bashrc`) — a fresh zsh install
   has no meaningful default `.zshrc` to preserve, and every line that would
   go here was already something our own scripts wrote anyway, so there's no
   overwrite risk in owning the whole file. Two parts:
   - **Unconditional, at the top:** `HISTFILE`/`HISTSIZE`/`SAVEHIST`, a few
     sane `HIST_*`/`SHARE_HISTORY` options, and `compinit` for completion.
     These exist here specifically because zsh only ever runs its
     interactive `zsh-newuser-install` wizard (which would otherwise set up
     exactly this) when *none* of `~/.zshenv`/`~/.zprofile`/`~/.zshrc`/
     `~/.zlogin` exist — since chezmoi always deploys this file first, that
     wizard never fires on any machine bootstrapped by this repo, so its
     usual defaults have to be set explicitly instead. Plain zsh options,
     no devbox dependency, so they apply the same regardless of
     `machineClass`/container status.
   - **`devbox global shellenv`, `starship init zsh`, `fnm env
     --use-on-cd`, and the two zsh plugins from `devbox.json`**
     (`zsh-syntax-highlighting` last, per its own requirement to be the
     final thing sourced). On `machineClass == bazzite` only *this* part is
     wrapped in `if [ -f /run/.containerenv ]; then ... fi`, for the same
     reason as item 4's `.bashrc` guard — Distrobox shares `$HOME`, so this
     file is sourced by both the container's shell and the bare host's, but
     devbox only exists inside the container. `standard`/`wsl` never
     involve a container, so no guard is emitted there at all.

   Excluded on native Windows via `.chezmoiignore.tmpl` (meaningless there;
   kept for macOS, which does use zsh).

   One side effect worth knowing: since this file deploys unconditionally
   through chezmoi's normal file management rather than a `command -v zsh`
   runtime check in a `run_once_*` script, the old "install zsh *before*
   `chezmoi init`" ordering requirement doesn't apply to `.zshrc` at all —
   it's always there, correctly populated, whenever zsh eventually gets
   installed and first reads it, regardless of when that happens.

6. **`private_dot_local/share/devbox/global/default/devbox.json`** is the
   single source of truth for global devbox packages, applied to
   `~/.local/share/devbox/global/default/devbox.json` (kept `private_` /
   0600 since devbox itself defaults to writing it that way). Current
   packages: `neovim`, `git`, `lazygit`, `ripgrep`, `fd`, `fzf`,
   `tree-sitter`, `gcc`, `curl`, `nerd-fonts.jetbrains-mono`, `starship`,
   `fnm`, `pnpm`, `zsh-autosuggestions`, `zsh-syntax-highlighting`. Add more
   by editing this file and running `chezmoi apply` — devbox reconciles
   installed packages against it. `starship` ships with sensible defaults, so
   there's no `starship.toml` here yet — add one later if you want a themed
   prompt.

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

   **`zsh-autosuggestions`** and **`zsh-syntax-highlighting`** were chosen
   over installing [Oh My Zsh](https://ohmyz.sh/) for the two specific
   features it's usually reached for. Oh My Zsh itself was skipped for the
   same reason `nvm` was: it self-installs via a curl-piped script that
   clones its own framework into `~/.oh-my-zsh` and rewrites `.zshrc`
   directly, outside Nix/devbox's reproducible model, and it noticeably
   slows shell startup once plugins are added. Both of these are real Nix
   packages instead, `source`d directly from devbox's global profile in
   `.zshrc` (see item 5) — same functionality, no framework, no `sudo`, no
   self-modifying installer.

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

7. **`dot_config/wezterm/wezterm.lua`** sets
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
   (for `wezterm.lua` and anything else under `dot_config/`) — see
   "First-time setup → WSL" below. The native-Windows run answers the same
   `machineClass=wsl` prompt but the bootstrap script no-ops there by design
   (see item 3's OS guard), so it only ever deploys plain files.

8. **`dot_config/nvim/`** — a plain [LazyVim starter](https://github.com/LazyVim/starter)
   config (no pre-existing personal config was found on this machine, so it
   was scaffolded fresh from upstream: `init.lua`, `lua/config/*`,
   `lua/plugins/example.lua`, `stylua.toml`, plus `.gitignore`/`.neoconf.json`
   stored as `dot_gitignore`/`dot_neoconf.json` per chezmoi's naming
   convention). Add real plugin configs as extra files under
   `lua/plugins/`. Requires the `neovim` package from `devbox.json` above (or
   any Neovim ≥ 0.9 on `PATH`).

9. **`dot_config/hypr/`, `dot_config/i3/`, `dot_config/waybar/`** — Hyprland
   and Waybar are a minimal, modern starter config (WezTerm as `$terminal`,
   `mako` for notifications) deliberately kept distro/DE-agnostic: no
   assumptions about which desktop environment, login manager, or polkit
   agent is already on the box, so it's a `chezmoi apply` away from
   dropping Hyprland in *alongside* whatever session already exists there —
   just pick "Hyprland" at your display/login manager. `i3` is a separate,
   untouched legacy config for X11 boxes without Hyprland available. All
   three are inert until you actually install and launch the corresponding
   WM — chezmoi just makes sure `~/.config/hypr`, `~/.config/i3`, and
   `~/.config/waybar` are already populated the moment you do, on any
   current or future Linux box.

   **`.chezmoiignore.tmpl`** excludes all three when `machineClass == "wsl"`
   or the target OS isn't Linux (native Windows, macOS) — those environments
   have no compositor/X server to run a tiling WM against, so the files would
   just be dead weight. They apply on `standard` and `bazzite` Linux
   machines regardless of which desktop environment is currently active
   there.

## First-time setup

Order matters more than it looks like it should here — several steps below
only come out right if done in sequence. This is written as a literal
first-boot-to-working-machine walkthrough; skip the parts you already know.

### 0. Before running chezmoi at all (every machine)

- **A system `git` and `chezmoi` must already be installed.** chezmoi's very
  first clone of this repo has to happen with whatever git the OS already
  provides — devbox's own (Nix-packaged) git only becomes available *after*
  the bootstrap script that same clone triggers, so it can't be what does
  the initial clone. Install both via your OS's package manager, or chezmoi
  via its own installer if your distro doesn't package it:
  ```bash
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
  ```
  **Gotcha:** without the `-b ~/.local/bin` part, the installer defaults to
  a relative `bin/chezmoi` under wherever you ran the command from (so
  `~/bin/chezmoi` from a fresh login) — a directory that's very likely not
  on `PATH` yet, especially in zsh, which (unlike bash) never sources
  `.profile` at all. You'll get `command not found: chezmoi` immediately
  after a successful install. `-b ~/.local/bin` avoids that on distros/shells
  where `~/.local/bin` is already wired onto `PATH` before any rc file runs
  (common on Ubuntu/WSL bash, via a stanza in the default `.bash_profile`) —
  but that's a distro/shell convention, not something the installer or this
  repo guarantees, and it does **not** hold for zsh on Fedora (or plenty of
  other combinations): a fresh zsh has no `.zprofile`/`.profile` step that
  would add it, so the binary can land exactly where you asked and still not
  resolve. After installing, always confirm with `echo $PATH` before
  assuming it worked. If `~/.local/bin` isn't listed, fix it before
  continuing:
  ```bash
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc   # or ~/.bashrc
  exec $SHELL
  ```
  (`chezmoi init --apply` below will later manage `.zshrc`/`.bashrc` for
  devbox's own tools, but chezmoi itself has to already resolve *before*
  that first run, so this one line is on you.) In the meantime, either move
  the binary (`mkdir -p ~/.local/bin && mv ~/bin/chezmoi ~/.local/bin/`) or
  just call it by its full path once (`~/bin/chezmoi --version` or
  `~/.local/bin/chezmoi --version`) to confirm the install itself worked.
- **Your SSH key needs to already work against GitHub**, since the clone
  below goes over SSH:
  ```bash
  ssh -T git@github.com
  ```
  **Gotcha:** using an `https://` URL instead of the SSH one clones fine
  initially, but every later `git push`/`pull` from `chezmoi cd` then fails
  on missing HTTPS credentials — hit this once already on this exact repo.
  Always use the SSH form shown below.
- **Want zsh? Install it whenever — before or after `chezmoi init`, order
  doesn't matter.** `.zshrc` is a fully chezmoi-managed file (not something
  a `run_once_*` script conditionally appends to), so it's always correctly
  populated the moment zsh actually reads it, regardless of when you install
  zsh relative to running chezmoi:
  ```bash
  sudo apt install zsh   # or pacman/dnf, depending on distro
  chsh -s $(which zsh)
  ```
  `chsh` itself is still a manual, one-time step either way — see "Manual
  installs" below for why that's not automated.

With that done, jump to whichever machine type this is.

### Standard (Arch, Fedora)

1. ```bash
   chezmoi init --apply git@github.com:Ryan-ED/dotfiles.git
   ```
2. Answer `standard` at the `machineClass` prompt, plus `gitName` and
   `gitEmail`. Everything else happens automatically: devbox/Nix install,
   every `devbox.json` package, fontconfig registration, shell rc wiring,
   `~/.gitconfig`, the nvim config.
3. **Gotcha:** open a new terminal (or `exec $SHELL`) once it finishes —
   your *current* shell has none of the new `PATH`/prompt/eval lines yet,
   they only apply to shells started after the rc files were written.
4. Sanity-check: `which nvim rg fd fzf lazygit starship pnpm fnm`.
5. **Manual, do now:** install WezTerm itself (`dnf install wezterm` /
   `pacman -S wezterm`) — never part of `devbox.json`; see "Manual
   installs" below for why.
6. **Manual, do once:** launch `nvim`. LazyVim bootstraps `lazy.nvim` and
   installs all plugins on first run — needs internet, takes a minute or
   two, compiles treesitter parsers via the `gcc` package. Run
   `:checkhealth` afterward. Once you're happy with the plugin set, commit
   `lazy-lock.json` back to the repo so other machines match:
   ```bash
   chezmoi add ~/.config/nvim/lazy-lock.json
   ```
7. **Optional, whenever:** the `hypr`/`i3`/`waybar` configs are already
   sitting in `~/.config/`, inert, until you install Hyprland itself plus
   `waybar mako wofi grim slurp wl-clipboard brightnessctl playerctl` via
   your distro's package manager (`pacman -S`, `dnf install`, etc.) and pick
   "Hyprland" at your login manager — it runs next to whatever DE is
   already installed, not instead of it.

### Bazzite

1. **Prerequisite:** `distrobox` must already be on the host (ships by
   default on Bazzite; install it first if it's somehow missing).
2. ```bash
   chezmoi init --apply git@github.com:Ryan-ED/dotfiles.git
   ```
   answering `bazzite` at the `machineClass` prompt (plus `gitName`/
   `gitEmail`).
3. This creates a Fedora Distrobox container named `devbox`, installs
   devbox/Nix *inside* it (the host's immutable base is never touched),
   then registers the container's fonts with the **host's** fontconfig
   afterward.
4. **Gotcha:** the devbox-installed binaries (`nvim`, `rg`, etc.) live
   *inside* the container, not on the host `PATH`. Either
   `distrobox enter devbox` every time, or export specific binaries:
   ```bash
   distrobox-export --bin /path/in/container/to/bin
   ```
5. **Manual, do now:** install WezTerm via Flatpak on the host —
   `flatpak install flathub org.wezfurlong.wezterm` — never inside the
   `devbox` container (circular: you'd need a working terminal to
   `distrobox enter` in the first place).
6. **Manual, do once:** same nvim first-launch step as Standard above —
   `distrobox enter devbox`, then `nvim`, `:checkhealth`, then
   `chezmoi add ~/.config/nvim/lazy-lock.json` once you're happy with it.
7. **Optional, whenever:** same as Standard — hypr/i3/waybar are already
   there, inert until you install the packages and switch sessions.

### WSL (Windows 11 laptop)

This one needs `chezmoi init --apply` run in **two separate places**,
because devbox/Nix only work inside WSL, but WezTerm is a native Windows
GUI process that can't see anything deployed only into WSL's filesystem.

**Inside WSL/Ubuntu:**

1. Make sure `git` and `chezmoi` are installed *inside the WSL distro
   itself* (`sudo apt install git`, then chezmoi's installer), and that
   your SSH key works from there (`ssh -T git@github.com`).
2. ```bash
   chezmoi init --apply git@github.com:Ryan-ED/dotfiles.git
   ```
   answering `wsl` at the prompt. This does the real work — devbox, Nix,
   starship, fnm, pnpm, the nvim config, fontconfig.
3. Same gotchas as Standard apply here too: new shell afterward, nvim
   first-launch step.

**Natively on Windows:**

4. Install chezmoi on Windows itself:
   ```powershell
   winget install twpayne.chezmoi
   ```
5. ```powershell
   chezmoi init --apply git@github.com:Ryan-ED/dotfiles.git
   ```
   answering `wsl` again — this is a *separate* per-OS chezmoi config from
   the WSL one, so it asks again. The bootstrap script no-ops immediately
   here (devbox/Nix aren't supported on native Windows), so this run only
   deploys plain files — in practice, `wezterm.lua`.
6. **Gotcha:** chezmoi still needs to *find* a shell interpreter just to
   run (and immediately exit) the bootstrap script's `.sh.tmpl` file. Git
   for Windows (which you need anyway) provides this; without it, that one
   step errors instead of silently skipping.
7. **Manual, do now:** install WezTerm on Windows:
   `winget install wez.wezterm`.
8. **Manual, do now:** install the Nerd Font *on Windows*, separately from
   the one devbox already installed inside WSL:
   `winget install --id DEVCOM.JetBrainsMonoNerdFont`. This is not
   optional — WSL's copy is invisible to native Windows font rendering, and
   WezTerm's icons won't show without doing this separately.
9. **Skipped by design, no action needed:** `hypr`/`i3`/`waybar` never
   deploy here at all (`.chezmoiignore.tmpl` excludes them when
   `machineClass == wsl`) — there's no compositor to use them against.

### Adding packages or config later

Edit `devbox.json` above, `chezmoi apply`, then `devbox global install` (or
just re-run the relevant bootstrap script's body manually — it's
idempotent). See "Making changes and syncing them everywhere" below for the
full edit → commit → `chezmoi update` cycle.

### Manual installs, and why they're manual

Two things are deliberately **not** part of any bootstrap script — see the
walkthroughs above for exactly *when* to do each; this is the *why*:

- **WezTerm itself.** Only its config (`dot_config/wezterm/wezterm.lua`,
  item 7 above) is managed here. It was left out of `devbox.json` because
  it's a GUI app with real GPU/OpenGL rendering, and Nix-packaged GUI apps
  on non-NixOS Linux sometimes hit graphics-driver mismatches that OS-native
  packaging (or Flatpak, on Bazzite) avoids — not worth the risk for the one
  application you'd be using to fix things if it broke.

- **Switching to zsh.** `.bashrc` and `.zshrc` end up equivalent (same
  `devbox global shellenv` / `starship init` / `fnm env` setup, plus the two
  zsh plugins in `.zshrc`'s case), but nothing here installs zsh itself or
  runs `chsh` to make it your login shell. Every script in this repo is
  deliberately unprivileged (no `sudo` — one of the actual selling points of
  devbox/Nix); automating this would mean the first `sudo` call in the whole
  setup, plus per-distro package-manager branching, just to save one
  copy-pasted command. Since `.zshrc` is a fully chezmoi-managed file (item
  5 above), not something a `run_once_*` script appends to conditionally,
  there's no ordering concern here anymore either — install zsh whenever you
  like, before or after `chezmoi init`, and `.zshrc` is already correctly
  populated the moment zsh actually reads it.

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
