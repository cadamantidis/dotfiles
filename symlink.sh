#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/dotfiles_backup/$(date +%Y%m%d_%H%M%S)"

link_file() {
  local src="$1"
  local dest="$2"

  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ "$(readlink -f "$dest")" == "$(readlink -f "$src")" ]]; then
      echo "  already linked: $dest"
      return
    fi
    mkdir -p "$BACKUP_DIR"
    mv "$dest" "$BACKUP_DIR/"
    echo "  backed up: $dest -> $BACKUP_DIR/$(basename "$dest")"
  fi

  ln -s "$src" "$dest"
  echo "  linked: $dest -> $src"
}

echo "Symlinking dotfiles..."
link_file "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"
[[ -f "$DOTFILES_DIR/zsh/.p10k.zsh" ]] && link_file "$DOTFILES_DIR/zsh/.p10k.zsh" "$HOME/.p10k.zsh"
link_file "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"
link_file "$DOTFILES_DIR/zsh/.zsh_functions" "$HOME/.zsh_functions"
[[ -f "$DOTFILES_DIR/zsh/.zprofile" ]] && link_file "$DOTFILES_DIR/zsh/.zprofile" "$HOME/.zprofile"
mkdir -p "$HOME/.config/git"
link_file "$DOTFILES_DIR/git/ignore" "$HOME/.config/git/ignore"

# Ghostty: macOS uses Application Support; other platforms use ~/.config/ghostty.
if [[ "$OSTYPE" == "darwin"* ]]; then
  GHOSTTY_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
  mkdir -p "$GHOSTTY_DIR"
  link_file "$DOTFILES_DIR/ghostty/config" "$GHOSTTY_DIR/config.ghostty"
else
  mkdir -p "$HOME/.config/ghostty"
  link_file "$DOTFILES_DIR/ghostty/config" "$HOME/.config/ghostty/config"
fi

echo "Done."
