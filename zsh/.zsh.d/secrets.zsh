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

# 1Password の GH_TOKEN を注入して devcontainer up（dotfiles インストール付き）
# codeop と同じ CODEOP_GH_TOKEN_PATH を使用。追加フラグは "$@" で渡せる
# GH_TOKEN をその場限りの環境変数として渡す。コンテナへの反映は devcontainer.json の
#   "remoteEnv": { "GH_TOKEN": "${localEnv:GH_TOKEN}" }
# 経由。以後の対話利用は dvex（下記）か codeop 起動の VS Code から行う
function dvop() {
  local op_path="${CODEOP_GH_TOKEN_PATH:-op://YOUR_VAULT/YOUR_ITEM/token}"
  local token
  token=$(op read "$op_path") || return
  GH_TOKEN="$token" devcontainer up \
    --dotfiles-repository https://github.com/chocolat0w0/dotfiles.git \
    --dotfiles-install-command setup-devcontainer.sh \
    "$@"
}

# 1Password の GH_TOKEN を注入して devcontainer 内でコマンド実行（既定は対話シェル）
# devcontainer.json の remoteEnv: { "GH_TOKEN": "${localEnv:GH_TOKEN}" } が
# その場の GH_TOKEN を解決して注入する。トークンは毎回 op から取るので Rebuild 不要
# 例: dvex            → コンテナ内で zsh を起動
#     dvex gh auth status
function dvex() {
  local op_path="${CODEOP_GH_TOKEN_PATH:-op://YOUR_VAULT/YOUR_ITEM/token}"
  local token
  token=$(op read "$op_path") || return
  GH_TOKEN="$token" devcontainer exec --workspace-folder "${PWD}" "${@:-zsh}"
}

# 個人設定の読み込み（git 管理外 / 各マシンで作成）
[[ -f "${ZDOTDIR:-$HOME}/.zsh.d/secrets.local.zsh" ]] && source "${ZDOTDIR:-$HOME}/.zsh.d/secrets.local.zsh"
