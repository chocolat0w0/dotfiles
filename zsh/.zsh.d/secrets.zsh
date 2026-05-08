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

# 個人設定の読み込み（git 管理外 / 各マシンで作成）
[[ -f "${ZDOTDIR:-$HOME}/.zsh.d/secrets.local.zsh" ]] && source "${ZDOTDIR:-$HOME}/.zsh.d/secrets.local.zsh"
