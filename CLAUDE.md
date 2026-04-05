# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

WSL2-focused dotfiles repository that bootstraps and manages a zsh shell environment on Ubuntu/Debian, with deep Windows Terminal integration (fonts, registry, terminal config).

## Key Commands

- `./install.sh` — Full idempotent bootstrap (packages, oh-my-zsh, plugins, p10k theme, fonts, symlinks)
- `./install.sh -q` / `./install.sh --quick` — Skip p10k reconfiguration wizard
- `./symlink.sh` — Standalone symlink creation with automatic backup of existing files

There are no build, test, or lint commands — this is a configuration repository.

## Architecture

### Symlink Strategy

Uses **direct symlinks** via `symlink.sh` (not GNU Stow). The script backs up conflicting files to `~/dotfiles_backup/YYYYMMDD_HHMMSS/` before linking.

Symlink mappings:
- `zsh/.zshrc` → `~/.zshrc`
- `zsh/.p10k.zsh` → `~/.p10k.zsh` (conditional on existence)
- `git/.gitconfig` → `~/.gitconfig`

### install.sh Flow

Runs 6 sequential stages, each idempotent (checks before acting):
1. apt packages (`zsh`, `curl`, `git`, `jq`)
2. Oh My Zsh framework
3. Custom plugins (`zsh-autosuggestions`, `zsh-syntax-highlighting`) into `$ZSH_CUSTOM/plugins/`
4. Powerlevel10k theme into `$ZSH_CUSTOM/themes/`
5. MesloLGS NF font installation — WSL2-specific: installs to Windows fonts dir, registers in Windows Registry via `reg.exe`, auto-configures Windows Terminal `settings.json` using `jq`
6. Symlinks via `symlink.sh`, then p10k wizard lifecycle (captures generated config back into `zsh/.p10k.zsh`)

Uses `set -euo pipefail` for strict error handling.

### WSL2 Integration Points

- Detects Windows username via `cmd.exe /C "echo %USERNAME%"`
- Font path: `/mnt/c/Users/$WIN_USER/AppData/Local/Microsoft/Windows/Fonts`
- Registry writes via `reg.exe add` for font registration
- Windows Terminal config modification via `jq` on `settings.json`

### Zsh Plugin Stack

Configured in `.zshrc`: `git`, `z`, `sudo`, `command-not-found`, `zsh-autosuggestions`, `zsh-syntax-highlighting`. Theme is `powerlevel10k/powerlevel10k` with Pure style prompt.
