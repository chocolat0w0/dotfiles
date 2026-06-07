#!/bin/zsh

echo "start setup"

echo "setup zsh"
script_dir=$(cd "$(dirname "$0")"; pwd)
ln -fs "${script_dir}/zsh/.zshrc" "${HOME}/.zshrc"
ln -nfs "${script_dir}/zsh/.zsh.d" "${HOME}/.zsh.d"
source "${HOME}/.zshrc"

echo "setup karabiner"
rm -f "${HOME}/.config/karabiner/karabiner.json"
ln -s "${script_dir}/karabiner/karabiner.json" "${HOME}/.config/karabiner/karabiner.json"

echo "setup ghostty"
mkdir -p "${HOME}/.config/ghostty"
rm -f "${HOME}/.config/ghostty/config.ghostty"
ln -s "${script_dir}/ghostty/config.ghostty" "${HOME}/.config/ghostty/config.ghostty"

echo "complete setup"
