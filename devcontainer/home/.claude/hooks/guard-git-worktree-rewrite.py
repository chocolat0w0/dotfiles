#!/usr/bin/env python3
"""/workspace で作業ツリーを書き換えるブランチ操作を、git-safe-switch 経由に寄せる PreToolUse フック。

devcontainer の /workspace は読み取り専用マウントと virtiofs の影響で、git の切り替えが
途中で失敗すると作業ツリーが新旧の版の混ざった状態で残る。git-safe-switch は事前の判定と
失敗時の切り戻しを行うため、同じ操作を直接実行しようとしたら止めて案内する。
"""

import json
import os
import shlex
import sys

GUIDE = (
    "/workspace で作業ツリーを書き換えるブランチ操作は git-safe-switch を使ってください。"
    "切り替えは `git-safe-switch <ref>`、ブランチを作って切り替えるなら `git-safe-switch -c <branch> [<start>]`、"
    "早送りは `git fetch` の後に `git-safe-switch --ff [<ref>]`、"
    "判定だけなら `git-safe-switch --check <ref>`。"
    "早送りでない merge、`reset --hard`、`gh pr checkout` はホストでの実行をユーザーに依頼してください。"
    "ファイルの変更を戻すだけなら `git restore <path>` を使ってください。"
)

SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "{", "}"}
# コマンドの前に付く語（シェルの予約語や、別のコマンドを実行するもの）
PREFIX_WORDS = {"if", "then", "else", "elif", "do", "while", "until", "!", "command", "env", "sudo", "time", "exec"}
# 値を取る git のグローバルオプション
GLOBAL_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
# switch / checkout で、新しいブランチ名を値に取るオプション
CREATE_OPTS = {"-c", "-C", "--create", "--force-create", "-b", "-B"}
# switch / checkout で値を取るその他のオプション
OPTS_WITH_VALUE = {"--conflict", "--pathspec-from-file"}


def split_commands(command: str) -> list[list[str]]:
    """引用符を解釈したうえで、区切り記号ごとの単語列に分ける。"""
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    try:
        tokens = list(lexer)
    except ValueError:
        tokens = command.split()
    commands, current = [], []
    for token in tokens:
        if token in SEPARATORS:
            if current:
                commands.append(current)
            current = []
        else:
            current.append(token)
    if current:
        commands.append(current)
    return commands


def strip_prefix(words: list[str]) -> list[str]:
    while words and (words[0] in PREFIX_WORDS or ("=" in words[0] and not words[0].startswith("-"))):
        words = words[1:]
    return words


def rewrites_worktree_by_git(args: list[str]) -> bool:
    i = 0
    while i < len(args) and args[i].startswith("-"):
        i += 2 if args[i] in GLOBAL_OPTS_WITH_VALUE else 1
    if i >= len(args):
        return False
    sub, rest = args[i], args[i + 1 :]
    if sub in ("switch", "checkout"):
        if "--" in rest:
            return False
        if "--orphan" in rest:
            return True
        positionals = []
        j = 0
        while j < len(rest):
            arg = rest[j]
            if arg in CREATE_OPTS or arg in OPTS_WITH_VALUE:
                j += 2
                continue
            if arg.startswith("-") and arg != "-":
                j += 1
                continue
            positionals.append(arg)
            j += 1
        # 切り替え先の指定がなければ（今の HEAD から新しいブランチを作るだけなど）作業ツリーは変わらない
        return bool(positionals)
    if sub == "merge":
        return not any(a in ("--abort", "--quit", "--continue") for a in rest)
    if sub == "pull":
        return True
    if sub == "reset":
        return any(a in ("--hard", "--merge", "--keep") for a in rest)
    return False


def rewrites_worktree(words: list[str]) -> bool:
    words = strip_prefix(words)
    if not words:
        return False
    program = os.path.basename(words[0])
    if program == "git":
        return rewrites_worktree_by_git(words[1:])
    if program == "gh":
        return words[1:3] == ["pr", "checkout"]
    return False


def main() -> None:
    payload = json.load(sys.stdin)
    if not payload.get("cwd", "").startswith("/workspace"):
        return
    command = payload.get("tool_input", {}).get("command", "")
    if any(rewrites_worktree(words) for words in split_commands(command)):
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": GUIDE,
                    }
                },
                ensure_ascii=False,
            )
        )


if __name__ == "__main__":
    main()
