# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/); [devbox](https://www.jetify.com/devbox)
(Nix-backed) provides the actual dev tooling on top. This is chezmoi's *source state* — files here get transformed
(names de-prefixed, templates rendered) into the *target state* under `$HOME` on each machine via `chezmoi apply`.
There is no build/test/lint pipeline; "correctness" means the templates render right and the bootstrap scripts are
idempotent.

## Commands

- `chezmoi diff` — preview what `chezmoi apply` would change against the live `$HOME` (run before committing).
- `chezmoi apply` — render source state and write it to `$HOME`.
- `chezmoi apply -n` — dry run (also shows which of the two `run_once_00-bootstrap-*.sh.tmpl` scripts would fire).
- `chezmoi edit ~/path/to/file` — open the corresponding source file in `$EDITOR`.
- `chezmoi re-add ~/path/to/file` — pull a live edit back into the source state (safe for plain files; for a
  `.tmpl` file this captures the *rendered* output, not the template, so check `chezmoi diff` after).
- `chezmoi cd` — drop into `~/.local/share/chezmoi` (the actual git repo) to commit/push.
- `chezmoi update` — `git pull` + `chezmoi apply` in one shot, used on every other machine after a push.
- `devbox global install` — reconcile installed global packages against `devbox.json` (chezmoi's bootstrap scripts
  call this automatically; re-run manually after hand-editing `devbox.json`).

Edit → commit cycle: edit the live file or `chezmoi edit` the source → `chezmoi re-add` if you edited live →
`chezmoi diff` to confirm clean → `chezmoi cd && git add -A && git commit && git push` → `chezmoi update`
elsewhere.

## Architecture

**Naming convention drives the transform.** chezmoi maps source filenames to target paths by prefix/suffix, not
by config: `dot_` → `.` (e.g. `dot_gitconfig.tmpl` → `~/.gitconfig`), `private_` → mode 0600, `run_once_*` → a
script chezmoi runs at most once per content-hash, `.tmpl` → Go-template rendering before writing. Reading any
file's *purpose* means reading its name, not just its contents.

**`machineClass` is the central branch point.** `.chezmoi.toml.tmpl` prompts once per machine (cached in
`~/.config/chezmoi/chezmoi.toml`, never re-asked) for `machineClass` (`standard` / `bazzite` / `wsl`) plus
`gitName`/`gitEmail`. Templated files key off this value (and sometimes `.chezmoi.os` / target triple directly,
e.g. `wezterm.lua`'s WSL-domain check) to decide what to render. `gitName`/`gitEmail` are prompted rather than
hardcoded specifically so they never land in this (public) repo's git history — they only exist in the
per-machine, uncommitted `chezmoi.toml`.

**Two mutually-exclusive bootstrap scripts**, both prefixed `run_once_00-` (prefix is just for readable
`apply -n` ordering, not execution order — chezmoi runs whichever one's template `if` doesn't short-circuit):
- `run_once_00-bootstrap-standard.sh.tmpl` — runs for `standard` and `wsl` (no-ops on `bazzite`, and no-ops for
  the real work when `.chezmoi.os == "windows"`, since Nix isn't supported there). Installs devbox+Nix directly
  on the host, runs `devbox global install`, registers devbox's font dir with the host's fontconfig on Linux,
  and idempotently appends shell-init lines (`devbox global shellenv`, `starship init`, `fnm env`) to
  `.bashrc`/`.zshrc`.
- `run_once_00-bootstrap-bazzite.sh.tmpl` — runs only for `machineClass == bazzite`. Bazzite is atomic/ostree, so
  Nix can't touch the host directly; instead this creates a Fedora Distrobox container named `devbox`, installs
  devbox/Nix *inside* it, then goes back to the **host** to register that container's fonts (shared via `$HOME`)
  with the host's own fontconfig, since Flatpak-installed GUI apps like WezTerm run on the host, not in the
  container.

**`private_dot_local/share/devbox/global/default/devbox.json`** is the single source of truth for global CLI
packages (neovim, git, lazygit, ripgrep, fd, fzf, tree-sitter, gcc, curl, a Nerd Font, starship, fnm, pnpm,
zsh-autosuggestions, zsh-syntax-highlighting). Add packages by editing this file, not by installing manually —
the bootstrap scripts (and `devbox global install`) reconcile against it. GUI apps and things that must self-
manage their own version state (WezTerm, zsh itself) are deliberately kept *out* of `devbox.json` — see the
README's "Manual installs, and why they're manual" section for the specific reasoning per tool.

**`dot_config/hypr/`, `dot_config/waybar/`** are inert configs (no logic reads them until you
install/launch Hyprland). `.chezmoiignore.tmpl` excludes both when `machineClass == wsl` or the target OS
isn't Linux, since there's no compositor to target on those platforms.

**`dot_config/nvim/`** is an unmodified LazyVim starter scaffold. Real personal config should go in new files
under `lua/plugins/`, not by editing the starter files in place.

## Key constraints when editing

- Every script here must stay unprivileged (no `sudo`) — this is treated as a deliberate selling point of the
  devbox/Nix approach, not an oversight. Don't add commands that require elevated privileges.
- Bootstrap scripts must stay idempotent — they're `run_once_*` by content hash but are also manually re-run
  (e.g. after editing `devbox.json`), so re-running with no changes must be a no-op.
- Never hardcode `gitName`/`gitEmail` or other machine-specific secrets into tracked files — route new
  per-machine values through `promptStringOnce` in `.chezmoi.toml.tmpl` the same way.
