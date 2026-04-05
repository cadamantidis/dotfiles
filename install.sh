#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Dotfiles Bootstrap ==="

# 1. Install dependencies
echo ""
echo "[1/6] Installing packages..."
sudo apt update -qq
sudo apt install -y -qq zsh curl git

# 2. Install Oh My Zsh (skip if already installed)
echo ""
echo "[2/6] Installing Oh My Zsh..."
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "  already installed."
fi

# 3. Install custom plugins
echo ""
echo "[3/6] Installing plugins..."
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
echo "[4/6] Installing Powerlevel10k..."
if [[ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
else
  echo "  already installed."
fi

# 5. Install MesloLGS NF fonts (into Windows user fonts directory)
echo ""
echo "[5/6] Installing MesloLGS NF fonts..."
FONT_BASE_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
FONT_FILES=(
  "MesloLGS NF Regular.ttf"
  "MesloLGS NF Bold.ttf"
  "MesloLGS NF Italic.ttf"
  "MesloLGS NF Bold Italic.ttf"
)

# Detect Windows user fonts directory via WSL interop
WIN_USER=$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r' || true)
if [[ -n "$WIN_USER" ]]; then
  WIN_FONT_DIR="/mnt/c/Users/$WIN_USER/AppData/Local/Microsoft/Windows/Fonts"
  mkdir -p "$WIN_FONT_DIR"
  ALL_INSTALLED=true
  for font in "${FONT_FILES[@]}"; do
    if [[ ! -f "$WIN_FONT_DIR/$font" ]]; then
      ALL_INSTALLED=false
      break
    fi
  done
  if $ALL_INSTALLED; then
    echo "  all fonts already installed."
  else
    for font in "${FONT_FILES[@]}"; do
      if [[ ! -f "$WIN_FONT_DIR/$font" ]]; then
        echo "  downloading: $font"
        curl -fsSL -o "$WIN_FONT_DIR/$font" "$FONT_BASE_URL/${font// /%20}"
      fi
    done
    echo "  fonts installed to: $WIN_FONT_DIR"
    echo "  NOTE: Set 'MesloLGS NF' as the font face in Windows Terminal settings."
  fi
else
  echo "  WSL interop not available — install MesloLGS NF fonts manually."
fi

# 6. Symlink dotfiles
echo ""
echo "[6/6] Symlinking dotfiles..."
bash "$DOTFILES_DIR/symlink.sh"

# Set zsh as default shell
if [[ "$SHELL" != "$(which zsh)" ]]; then
  echo ""
  echo "Setting zsh as default shell..."
  chsh -s "$(which zsh)"
fi

echo ""
echo "=== Bootstrap complete! ==="

# Prompt for p10k configuration if no config exists in the repo
if [[ ! -f "$DOTFILES_DIR/zsh/.p10k.zsh" ]]; then
  echo ""
  echo "No Powerlevel10k config found in the repo."
  echo "Open a new zsh session and run: p10k configure"
  echo "Then run: mv ~/.p10k.zsh $DOTFILES_DIR/zsh/.p10k.zsh && ln -s $DOTFILES_DIR/zsh/.p10k.zsh ~/.p10k.zsh"
fi
