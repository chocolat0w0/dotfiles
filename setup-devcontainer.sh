#!/usr/bin/env bash

set -u

echo "start setup (devcontainer)"

failed_paths=()
failed_contents=()
script_dir=$(cd "$(dirname "$0")"; pwd)

display_path() {
  local path="$1"
  printf '%s' "${path/#$HOME/~}"
}

record_failure() {
  local path="$1"
  local reason="$2"
  local content="$3"

  failed_paths+=("$(display_path "$path"): $reason")
  failed_contents+=("----- $(display_path "$path") -----"$'\n'"$content")
}

copy_file_if_missing() {
  local source_path="$1"
  local dest_path="$2"
  local mode="$3"
  local content
  local tmp

  if ! content="$(cat "$source_path")"; then
    record_failure "$dest_path" "failed to read source file: $(display_path "$source_path")" ""
    return 1
  fi

  if [ -e "$dest_path" ]; then
    record_failure "$dest_path" "already exists" "$content"
    return 1
  fi

  if ! mkdir -p "$(dirname "$dest_path")"; then
    record_failure "$dest_path" "failed to create parent directory" "$content"
    return 1
  fi

  if ! tmp="$(mktemp "${dest_path}.tmp.XXXXXX")"; then
    record_failure "$dest_path" "failed to create temporary file" "$content"
    return 1
  fi

  if ! printf '%s\n' "$content" > "$tmp"; then
    record_failure "$dest_path" "failed to write file" "$content"
    rm -f "$tmp"
    return 1
  fi

  if ! chmod "$mode" "$tmp"; then
    record_failure "$dest_path" "failed to set file mode" "$content"
    rm -f "$tmp"
    return 1
  fi

  if ! mv "$tmp" "$dest_path"; then
    record_failure "$dest_path" "failed to move file into place" "$content"
    rm -f "$tmp"
    return 1
  fi

  return 0
}

run_setup_command() {
  local description="$1"
  shift

  echo "$description"
  if ! "$@"; then
    failed_paths+=("$description")
  fi
}

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
ln -fs "${script_dir}/zsh/.zshrc" "${HOME}/.zshrc"
ln -nfs "${script_dir}/zsh/.zsh.d" "${HOME}/.zsh.d"

echo "setup Claude Code"
copy_file_if_missing "${script_dir}/devcontainer/home/.claude/settings.json" "${HOME}/.claude/settings.json" 0644
copy_file_if_missing "${script_dir}/devcontainer/home/.claude/statusline-command.sh" "${HOME}/.claude/statusline-command.sh" 0755

echo "setup Codex"
copy_file_if_missing "${script_dir}/devcontainer/home/.codex/config.toml" "${HOME}/.codex/config.toml" 0644
run_setup_command "install generic agent skills" "${script_dir}/devcontainer/install-generic-agent-skills.sh"
if command -v go >/dev/null 2>&1; then
  run_setup_command "install Crit" go install github.com/tomasz-tomczyk/crit/cmd/crit@v0.18.1
else
  echo "skip Crit install: Go is unavailable"
fi

if command -v claude >/dev/null 2>&1; then
  run_setup_command "add Crit marketplace to Claude Code" claude plugin marketplace add tomasz-tomczyk/crit
  run_setup_command "install Crit plugin for Claude Code" claude plugin install crit@crit
  run_setup_command "update Claude Code official plugin marketplace" claude plugin marketplace update claude-plugins-official
  run_setup_command "install Superpowers plugin for Claude Code" claude plugin install superpowers@claude-plugins-official --scope user
else
  echo "skip Claude Code plugins: Claude Code is unavailable"
fi

if command -v codex >/dev/null 2>&1; then
  echo "Codex Superpowers plugin requires interactive installation:"
  echo "  1. Start Codex"
  echo "  2. Open /plugins"
  echo "  3. Select and install Superpowers"
else
  echo "skip Codex plugins: Codex is unavailable"
fi

if command -v crit >/dev/null 2>&1 && command -v codex >/dev/null 2>&1; then
  run_setup_command "configure Crit Codex plugin" bash -c 'cd "$HOME" && crit install codex-plugin'
else
  echo "skip Crit Codex plugin: Crit or Codex is unavailable"
fi

if [ "${#failed_paths[@]}" -gt 0 ]; then
  echo "failed to complete some devcontainer setup steps:" >&2
  for failed_path in "${failed_paths[@]}"; do
    echo "  - ${failed_path}" >&2
  done

  if [ "${#failed_contents[@]}" -gt 0 ]; then
    echo >&2
    echo "not written contents:" >&2
    for failed_content in "${failed_contents[@]}"; do
      echo "$failed_content" >&2
      echo >&2
    done
  fi

  echo "complete setup (with errors)"
  exit 1
fi

echo "complete setup"
