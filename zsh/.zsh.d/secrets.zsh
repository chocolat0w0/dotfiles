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
# トークンは secrets-file 経由で渡す（ps に出ず devcontainer のログでもマスクされる）
function dvcop() {
  local op_path="${CODEOP_GH_TOKEN_PATH:-op://YOUR_VAULT/YOUR_ITEM/token}"
  local token
  token=$(op read "$op_path") || return
  devcontainer up \
    --dotfiles-repository https://github.com/chocolat0w0/dotfiles.git \
    --dotfiles-install-command setup-devcontainer.sh \
    --secrets-file <(GH_TOKEN="$token" jq -n '{GH_TOKEN: env.GH_TOKEN}') \
    "$@"
}

# 個人設定の読み込み（git 管理外 / 各マシンで作成）
[[ -f "${ZDOTDIR:-$HOME}/.zsh.d/secrets.local.zsh" ]] && source "${ZDOTDIR:-$HOME}/.zsh.d/secrets.local.zsh"
