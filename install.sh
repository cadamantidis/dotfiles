#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse flags
QUICK=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -q|--quick) QUICK=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

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

# Powerlevel10k configuration
echo ""
HAS_REPO_CONFIG=false
[[ -f "$DOTFILES_DIR/zsh/.p10k.zsh" ]] && HAS_REPO_CONFIG=true

if $HAS_REPO_CONFIG; then
  if $QUICK; then
    echo "p10k config found in repo — skipping reconfiguration (quick mode)."
  else
    echo "Existing p10k config detected in repo."
    read -rp "Reconfigure Powerlevel10k? [y/N] " answer
    if [[ "${answer,,}" == "y" ]]; then
      zsh -ic "p10k configure"
      # If p10k wrote a new file (not our symlink), capture it into the repo
      if [[ -f "$HOME/.p10k.zsh" && ! -L "$HOME/.p10k.zsh" ]]; then
        mv "$HOME/.p10k.zsh" "$DOTFILES_DIR/zsh/.p10k.zsh"
        ln -s "$DOTFILES_DIR/zsh/.p10k.zsh" "$HOME/.p10k.zsh"
        echo "  updated p10k config in repo."
      fi
    else
      echo "  keeping existing config."
    fi
  fi
else
  # Check if user already ran p10k configure outside of this script
  if [[ -f "$HOME/.p10k.zsh" && ! -L "$HOME/.p10k.zsh" ]]; then
    echo "Found p10k config at ~/.p10k.zsh — moving into repo..."
    mv "$HOME/.p10k.zsh" "$DOTFILES_DIR/zsh/.p10k.zsh"
    ln -s "$DOTFILES_DIR/zsh/.p10k.zsh" "$HOME/.p10k.zsh"
    echo "  done."
  else
    echo "No p10k config found. Launching configurator..."
    zsh -ic "p10k configure"
    # Capture the generated config
    if [[ -f "$HOME/.p10k.zsh" && ! -L "$HOME/.p10k.zsh" ]]; then
      mv "$HOME/.p10k.zsh" "$DOTFILES_DIR/zsh/.p10k.zsh"
      ln -s "$DOTFILES_DIR/zsh/.p10k.zsh" "$HOME/.p10k.zsh"
      echo "  p10k config saved to repo."
    elif [[ -f "$HOME/.p10k.zsh" && -L "$HOME/.p10k.zsh" ]]; then
      echo "  p10k config already symlinked."
    else
      echo "  WARNING: p10k configure did not produce a config file."
      echo "  Run 'p10k configure' manually in zsh, then re-run this script."
    fi
  fi
fi

echo ""
echo "=== Bootstrap complete! ==="
