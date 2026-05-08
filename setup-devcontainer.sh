#!/bin/sh

echo "start setup (devcontainer)"

# Install fzf
if ! command -v fzf >/dev/null 2>&1; then
  echo "installing fzf"
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y fzf
  else
    FZF_VERSION="0.61.1"
    ARCH=$(uname -m)
    case "$ARCH" in
      x86_64)  FZF_ARCH="amd64" ;;
      aarch64) FZF_ARCH="arm64" ;;
      *)       echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    mkdir -p "${HOME}/.local/bin"
    curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${FZF_ARCH}.tar.gz" | tar xz -C "${HOME}/.local/bin"
  fi
fi

echo "setup zsh"
script_dir=$(cd $(dirname $0); pwd)
ln -fs ${script_dir}/zsh/.zshrc ${HOME}/.zshrc

ln -nfs ${script_dir}/zsh/.zsh.d ${HOME}/.zsh.d

echo "complete setup"
