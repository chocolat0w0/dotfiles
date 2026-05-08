echo "set help"

# カスタムコマンド一覧を表示
function zhelp() {
  local files=(
    "${ZDOTDIR:-$HOME}/.zsh.d/alias.zsh"
    "${ZDOTDIR:-$HOME}/.zsh.d/fzf.zsh"
    "${ZDOTDIR:-$HOME}/.zsh.d/secrets.zsh"
  )
  local section="" pending_desc="" name desc line

  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    pending_desc=""
    while IFS= read -r line; do
      if [[ "$line" =~ '^#>[[:space:]]*(.+)$' ]]; then
        # セクションヘッダー
        section="${match[1]}"
        print -P "\n%B%F{yellow}[$section]%f%b"
        pending_desc=""
      elif [[ "$line" =~ '^(alias|function)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)' ]]; then
        name="${match[2]}"
        # インラインコメント優先、なければ直前のコメントを使用
        if [[ "$line" =~ '[[:space:]]+#[[:space:]]+([^#]+)$' ]]; then
          desc="${match[1]}"
        elif [[ -n "$pending_desc" ]]; then
          desc="$pending_desc"
        else
          pending_desc=""
          continue
        fi
        printf "  \033[32m%-14s\033[0m %s\n" "$name" "${desc%"${desc##*[![:space:]]}"}"
        pending_desc=""
      elif [[ "$line" =~ '^#[[:space:]]+(.+)$' ]]; then
        # 直前コメント（最初の行を採用）
        [[ -z "$pending_desc" ]] && pending_desc="${match[1]}"
      else
        pending_desc=""
      fi
    done < "$f"
  done
  echo
}
