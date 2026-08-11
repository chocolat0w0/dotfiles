########################################
# Secrets / Tokens

#> secrets

# 1Password 経由でトークンをセットして VS Code を起動
# CODEOP_GH_TOKEN_PATH を secrets.local.zsh で設定してください
# 例: export CODEOP_GH_TOKEN_PATH="op://MyVault/GitHub PAT/token"
function codeop() {
  local op_path="${CODEOP_GH_TOKEN_PATH:-op://YOUR_VAULT/YOUR_ITEM/token}"
  GH_TOKEN="$op_path" op run -- code "${@:-.}"
}

# origin の URL から .devcontainer-personal/<host>/<org>/<repo>/.devcontainer/devcontainer.json
# を解決する。存在すればそのパスを出力、無ければ何も出力せず失敗を返す（dvop/dvex 用）

function _dv_personal_config() {
  local remote_url host_path config_path
  remote_url=$(git config --get remote.origin.url 2>/dev/null) || return 1
  [[ -z "$remote_url" ]] && return 1

  host_path="${remote_url#*://}"   # プロトコル除去 (https://, ssh://)
  host_path="${host_path#*@}"      # user@ 除去 (git@)
  if [[ "$host_path" == *:* ]]; then # host:path → host/path (SSH形式)
    host_path="${host_path%%:*}/${host_path#*:}"
  fi
  host_path="${host_path%.git}"    # .git サフィックス除去

  config_path=".devcontainer-personal/${host_path}/.devcontainer/devcontainer.json"
  [[ -f "$config_path" ]] || return 1
  echo "$config_path"
}

# 1Password の GH_TOKEN を注入して devcontainer up（dotfiles インストール付き）
# codeop と同じ CODEOP_GH_TOKEN_PATH を使用。追加フラグは "$@" で渡せる
# GH_TOKEN をその場限りの環境変数として渡す。コンテナへの反映は devcontainer.json の
#   "remoteEnv": { "GH_TOKEN": "${localEnv:GH_TOKEN}" }
# 経由。以後の対話利用は dvex（下記）か codeop 起動の VS Code から行う
# .devcontainer-personal に個人用設定があれば自動でそちらを使う
function dvop() {
  local op_path="${CODEOP_GH_TOKEN_PATH:-op://YOUR_VAULT/YOUR_ITEM/token}"
  local token config_path
  token=$(op read "$op_path") || return
  config_path=$(_dv_personal_config)
  local config_args=()
  [[ -n "$config_path" ]] && config_args=(--config "$config_path")
  GH_TOKEN="$token" devcontainer up \
    --workspace-folder "$PWD" \
    "${config_args[@]}" \
    --dotfiles-repository https://github.com/chocolat0w0/dotfiles.git \
    --dotfiles-install-command setup-devcontainer.sh \
    "$@"
}

# 1Password の GH_TOKEN を注入して devcontainer 内でコマンド実行（既定は対話シェル）
# devcontainer.json の remoteEnv: { "GH_TOKEN": "${localEnv:GH_TOKEN}" } が
# その場の GH_TOKEN を解決して注入する。トークンは毎回 op から取るので Rebuild 不要
# .devcontainer-personal に個人用設定があれば自動でそちらを使う
# 例: dvex            → コンテナ内で zsh を起動
#     dvex gh auth status
function dvex() {
  local op_path="${CODEOP_GH_TOKEN_PATH:-op://YOUR_VAULT/YOUR_ITEM/token}"
  local token config_path
  token=$(op read "$op_path") || return
  config_path=$(_dv_personal_config)
  local config_args=()
  [[ -n "$config_path" ]] && config_args=(--config "$config_path")
  GH_TOKEN="$token" devcontainer exec --workspace-folder "${PWD}" "${config_args[@]}" "${@:-zsh}"
}

# 個人設定の読み込み（git 管理外 / 各マシンで作成）
[[ -f "${ZDOTDIR:-$HOME}/.zsh.d/secrets.local.zsh" ]] && source "${ZDOTDIR:-$HOME}/.zsh.d/secrets.local.zsh"
