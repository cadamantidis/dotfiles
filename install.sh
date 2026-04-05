#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Dotfiles Bootstrap ==="

# 1. Install dependencies
echo ""
echo "[1/5] Installing packages..."
sudo apt update -qq
sudo apt install -y -qq zsh curl git

# 2. Install Oh My Zsh (skip if already installed)
echo ""
echo "[2/5] Installing Oh My Zsh..."
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "  already installed."
fi

# 3. Install custom plugins
echo ""
echo "[3/5] Installing plugins..."
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
  git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
else
  echo "  zsh-autosuggestions already installed."
fi

if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
  git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
else
  echo "  zsh-syntax-highlighting already installed."
fi

# 4. Install Powerlevel10k
echo ""
echo "[4/5] Installing Powerlevel10k..."
if [[ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
else
  echo "  already installed."
fi

# 5. Symlink dotfiles
echo ""
echo "[5/5] Symlinking dotfiles..."
bash "$DOTFILES_DIR/symlink.sh"

# Set zsh as default shell
if [[ "$SHELL" != "$(which zsh)" ]]; then
  echo ""
  echo "Setting zsh as default shell..."
  chsh -s "$(which zsh)"
fi

echo ""
echo "=== Bootstrap complete! ==="
echo ""
echo "NEXT STEPS:"
echo "  1. Install MesloLGS NF font on Windows:"
echo "     https://github.com/romkatv/powerlevel10k#meslo-nerd-font-patched-for-powerlevel10k"
echo "  2. Set 'MesloLGS NF' as the font in Windows Terminal settings"
echo "  3. Open a new zsh session and run: p10k configure"
