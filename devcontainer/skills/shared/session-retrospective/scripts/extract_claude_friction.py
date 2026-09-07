#!/usr/bin/env python3
"""セッション transcript から摩擦の候補イベントを機械的に抽出する。

このスクリプトは摩擦かどうかを「判定」しない。判定と分類はスキルを使う
エージェントの仕事で、ここでは見落としやすい痕跡を漏れなく並べるだけを担う。
機械抽出と判断を分けてあるので、判断基準を SKILL.md 側で変えても
このスクリプトを直す必要はない。

設計上の重要な前提: 実測すると 1 セッションの実ユーザー発言は 7〜20 件程度しかない。
そのため「修正指示らしい語」でフィルタすると取りこぼす（「コミットメッセージは
日本語にしてください」「差分が残るので reset してほしい」のような明確な修正指示は
語彙に引っかからない）。よって発言は全部出し、語彙一致は `correction_hint` という
ヒントとして添えるだけにしている。読む量が少ないので全部読ませたほうが精度が高い。

使い方:
    # 現在の作業ディレクトリの最新セッション（= たいてい今のセッション）
    python3 extract_claude_friction.py

    # セッションを明示
    python3 extract_claude_friction.py --session f61599e0

    # transcript を新しい順に一覧する
    python3 extract_claude_friction.py --list

    # JSON で出す（自前で加工したいとき）
    python3 extract_claude_friction.py --json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

# ユーザーが軌道修正をかけたときに出やすい語。ヒント表示にしか使わない。
# 一致しなかった発言も摩擦であり得るので、フィルタには使わない。
CORRECTION_PATTERNS = [
    r"違う", r"ちがう", r"では?なく", r"じゃなく", r"やめて", r"不要", r"いらない",
    r"勝手に", r"言って(ない|いない)", r"聞いて(ない|いない)", r"そうじゃ", r"逆",
    r"直して", r"修正して", r"戻して", r"取り消", r"reset", r"なんで", r"なぜ",
    r"忘れ(て|た)", r"また同じ", r"何度も", r"もう一度", r"再度", r"先に",
    r"その前に", r"ではない", r"しなくて良い", r"しなくてよい", r"必要ない",
    r"(して|に して)ください", r"ほしい", r"現状維持", r"一旦",
    r"\bwrong\b", r"\bnot what\b", r"\bstop\b", r"\brevert\b", r"\bundo\b",
    r"\bagain\b", r"\bwhy did you\b", r"\binstead\b",
]
CORRECTION_RE = re.compile("|".join(CORRECTION_PATTERNS), re.IGNORECASE)

DENIAL_MARKERS = [
    "Permission for this action was denied",
    "The user doesn't want to proceed",
    "The user doesn't want to take this action",
    "requested permissions to use",
]

# 会話ではない行（モード切替、タイトル、スナップショット等）を除くためのフィルタ。
CONVERSATION_TYPES = {"user", "assistant"}

# ユーザーの発話ではない注入テキスト。これらを含む行は発言として数えない。
NON_PROMPT_MARKERS = [
    "<local-command-stdout>",
    "<local-command-stderr>",
    "<command-name>",
    "<task-notification>",
    "[Request interrupted by user",
]


def encode_cwd(cwd: str) -> str:
    """cwd を Claude Code の transcript ディレクトリ名へ変換する。

    `/` だけでなく `.` も `-` になる。worktree を `.worktree/` の下に置く運用では
    `.` を落とすと transcript を丸ごと見失うので、両方を置換する。
    例: /repo/.worktree/feat -> -repo--worktree-feat
    """
    return re.sub(r"[/.]", "-", cwd)


def recorded_cwd(directory: Path) -> str:
    """transcript が自分で記録している作業ディレクトリを読む。

    先頭行にはまだ `cwd` が無いことがあるので、見つかるまで数行読む。
    """
    for path in directory.glob("*.jsonl"):
        try:
            with path.open(encoding="utf-8") as fh:
                for _ in range(50):
                    line = fh.readline()
                    if not line:
                        break
                    try:
                        row = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if cwd := row.get("cwd"):
                        return cwd
        except OSError:
            continue
    return ""


def project_dir(cwd: str) -> Path:
    """cwd から Claude Code の transcript 置き場を導く。

    命名規則は Claude Code 側の実装都合で変わりうる。規則から導けなかったときは、
    transcript 自身が記録している `cwd` と突き合わせて探し直す。
    """
    root = Path.home() / ".claude" / "projects"
    direct = root / encode_cwd(cwd)
    if direct.is_dir() or not root.is_dir():
        return direct

    wanted = {cwd, str(Path(cwd).resolve())}
    for candidate in sorted(root.iterdir()):
        if candidate.is_dir() and recorded_cwd(candidate) in wanted:
            return candidate
    return direct


def find_transcripts(cwd: str) -> list[Path]:
    d = project_dir(cwd)
    if not d.is_dir():
        return []
    return sorted(d.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)


def resolve_session(cwd: str, session: str | None) -> Path:
    files = find_transcripts(cwd)
    if not files:
        sys.exit(f"transcript が見つからない: {project_dir(cwd)}")
    if session is None:
        return files[0]
    matches = [p for p in files if p.stem.startswith(session)]
    if not matches:
        sys.exit(f"session '{session}' に一致する transcript がない")
    return matches[0]


def text_of(content) -> str:
    """message.content を素のテキストに落とす。"""
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    return "\n".join(
        b.get("text", "")
        for b in content
        if isinstance(b, dict) and b.get("type") == "text"
    )


def strip_system_reminders(text: str) -> str:
    """<system-reminder> はシステム注入なのでユーザー発言から除く。"""
    return re.sub(r"<system-reminder>.*?</system-reminder>", "", text, flags=re.DOTALL)


def tool_results(content) -> list[dict]:
    if not isinstance(content, list):
        return []
    return [b for b in content if isinstance(b, dict) and b.get("type") == "tool_result"]


def result_text(block: dict) -> str:
    c = block.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(
            b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text"
        )
    return ""


def summarize_tool_input(name: str, tool_input: dict) -> str:
    """tool_use の引数を 1 行に潰す。

    失敗したツール呼び出しは「何を叩いて失敗したか」がわからないと分類できない。
    ツール名だけ出しても `(tool_use: Bash)` にしかならず判断材料にならないので、
    実際のコマンドやパスを出す。引数の名前はツールによって違うため、
    よく使うものを優先順で拾い、無ければ JSON にフォールバックする。
    """
    if not isinstance(tool_input, dict):
        return name
    for key in ("command", "file_path", "path", "url", "pattern", "query", "prompt"):
        if value := tool_input.get(key):
            text = str(value).replace("\n", " ⏎ ")
            return f"{name}: {text[:500]}"
    dumped = json.dumps(tool_input, ensure_ascii=False)
    return f"{name}: {dumped[:500]}"


def index_tool_uses(rows: list[dict]) -> dict[str, str]:
    """tool_use_id -> 「ツール名: 引数」の対応表を作る。"""
    index: dict[str, str] = {}
    for row in rows:
        if row.get("type") != "assistant":
            continue
        content = (row.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_use" and block.get("id"):
                index[block["id"]] = summarize_tool_input(
                    block.get("name", "?"), block.get("input") or {}
                )
    return index


def load_rows(path: Path) -> list[dict]:
    rows = []
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return rows


def error_signature(text: str) -> str:
    """同じエラーの繰り返しをまとめるための署名。

    パス・ポート・時刻・16 進 id のような可変部分を落として比較する。
    同一エラーを 9 回並べても情報は増えないが、「何回繰り返したか」は
    摩擦の深刻度そのものなので回数として残す。
    """
    normalized = re.sub(r"\d+", "N", text[:300])
    normalized = re.sub(r"[0-9a-f]{8,}", "HEX", normalized)
    return hashlib.sha1(normalized.encode("utf-8")).hexdigest()[:12]


def collect(path: Path, include_sidechain: bool = False, max_chars: int = 1200) -> dict:
    rows = load_rows(path)
    by_uuid = {r["uuid"]: r for r in rows if r.get("uuid")}
    tool_uses = index_tool_uses(rows)

    events: list[dict] = []
    session_id = ""
    branches: set[str] = set()
    first_ts = last_ts = ""

    def preceding_assistant(row: dict) -> str:
        """直前のアシスタント挙動。そのイベントが「何をした結果か」の手がかりになる。"""
        cur = by_uuid.get(row.get("parentUuid") or "")
        for _ in range(6):
            if cur is None:
                break
            if cur.get("type") == "assistant":
                content = cur.get("message", {}).get("content")
                txt = text_of(content).strip()
                if txt:
                    return txt[:400]
                if isinstance(content, list):
                    names = [
                        b.get("name", "")
                        for b in content
                        if isinstance(b, dict) and b.get("type") == "tool_use"
                    ]
                    if any(names):
                        return "(tool_use: " + ", ".join(n for n in names if n) + ")"
            cur = by_uuid.get(cur.get("parentUuid") or "")
        return ""

    def add(event: dict) -> None:
        """同一署名の tool-error が連続したらまとめて回数だけ増やす。"""
        if event["kind"] == "tool-error":
            for prev in reversed(events):
                if prev["kind"] != "tool-error":
                    break
                if prev.get("signature") == event.get("signature"):
                    prev["repeat"] = prev.get("repeat", 1) + 1
                    return
        events.append(event)

    for row in rows:
        session_id = session_id or row.get("sessionId") or row.get("session_id") or ""
        if row.get("gitBranch"):
            branches.add(row["gitBranch"])
        if ts := (row.get("timestamp") or ""):
            first_ts = first_ts or ts
            last_ts = ts
        ts = row.get("timestamp") or ""

        if row.get("isSidechain") and not include_sidechain:
            continue

        # フックによる継続阻止 / フックエラー。会話行以外にも付くので先に見る。
        if row.get("preventedContinuation") or row.get("hookErrors"):
            add(
                {
                    "kind": "hook-blocked",
                    "timestamp": ts,
                    "detail": json.dumps(
                        {"stopReason": row.get("stopReason"), "hookErrors": row.get("hookErrors")},
                        ensure_ascii=False,
                    )[:600],
                    "preceding_assistant": preceding_assistant(row),
                }
            )

        rtype = row.get("type")
        if rtype not in CONVERSATION_TYPES:
            continue

        content = (row.get("message") or {}).get("content")

        # ツール拒否（ユーザー却下 / auto mode ブロック）とツールエラー
        denial_kind = row.get("toolDenialKind")
        for block in tool_results(content):
            body = result_text(block).strip()
            # 失敗した呼び出し自体が分類の主材料。ツール名だけでは足りないので引数を出す。
            call = tool_uses.get(block.get("tool_use_id") or "", "")
            # 本文の語句一致は失敗した結果にだけ適用する。成功した Read の中身が
            # たまたま拒否メッセージを含むことがあり（このスクリプト自身がそう）、
            # 無条件に当てると読んだだけのファイルが拒否として記録される。
            failed = bool(block.get("is_error"))
            if denial_kind or (failed and any(m in body for m in DENIAL_MARKERS)):
                add(
                    {
                        "kind": "tool-denied",
                        "timestamp": ts,
                        "denial_kind": denial_kind or "user-rejected",
                        "tool_call": call,
                        "detail": body[:max_chars],
                        "preceding_assistant": preceding_assistant(row),
                    }
                )
            elif failed:
                add(
                    {
                        "kind": "tool-error",
                        "timestamp": ts,
                        "signature": error_signature(call + "\n" + body),
                        "repeat": 1,
                        "tool_call": call,
                        "detail": body[:max_chars],
                        "preceding_assistant": preceding_assistant(row),
                    }
                )

        if rtype != "user":
            continue

        raw = text_of(content)
        if "[Request interrupted by user" in raw:
            add(
                {
                    "kind": "user-interrupt",
                    "timestamp": ts,
                    "detail": raw.strip()[:300],
                    "preceding_assistant": preceding_assistant(row),
                }
            )
            continue

        if row.get("isMeta") or any(m in raw for m in NON_PROMPT_MARKERS):
            continue

        body = strip_system_reminders(raw).strip()
        if not body:
            continue

        match = CORRECTION_RE.search(body)
        add(
            {
                "kind": "user-prompt",
                "timestamp": ts,
                "correction_hint": match.group(0) if match else "",
                "detail": body[:max_chars],
                "preceding_assistant": preceding_assistant(row),
            }
        )

    return {
        "transcript": str(path),
        "session_id": session_id,
        "session_short": (session_id or path.stem)[:8],
        "git_branches": sorted(branches),
        "started_at": first_ts,
        "ended_at": last_ts,
        "total_rows": len(rows),
        "events": events,
    }


def print_report(data: dict) -> None:
    counts: dict[str, int] = {}
    for e in data["events"]:
        counts[e["kind"]] = counts.get(e["kind"], 0) + 1

    print(f"# 摩擦候補 — session `{data['session_short']}`")
    print()
    print(f"- transcript: `{data['transcript']}`")
    print(f"- branch: {', '.join(data['git_branches']) or '(不明)'}")
    if data["started_at"]:
        print(f"- 期間: {data['started_at']} → {data['ended_at']}")
    print(f"- 候補件数: {len(data['events'])}" + (f" {counts}" if counts else ""))
    print()
    print("> これは候補にすぎない。摩擦かどうかの判定と分類は SKILL.md の手順に従って")
    print("> エージェントが行う。`user-prompt` は全発言を出しているので大半は摩擦ではない。")
    print("> `correction_hint` は語彙一致のヒントで、無印でも摩擦のことはある。")
    print()

    for i, e in enumerate(data["events"], 1):
        head = f"## {i}. [{e['kind']}]"
        if e.get("repeat", 1) > 1:
            head += f" ×{e['repeat']}"
        print(f"{head} {e.get('timestamp', '')}")
        if e.get("denial_kind"):
            print(f"- denial_kind: `{e['denial_kind']}`")
        if e.get("correction_hint"):
            print(f"- correction_hint: `{e['correction_hint']}`")
        if e.get("tool_call"):
            print(f"- 失敗した呼び出し: `{e['tool_call']}`")
        if e.get("preceding_assistant"):
            print("- 直前のアシスタント挙動:")
            print("  ```")
            for line in e["preceding_assistant"].splitlines():
                print(f"  {line}")
            print("  ```")
        print("- 内容:")
        print("  ```")
        for line in e["detail"].splitlines():
            print(f"  {line}")
        print("  ```")
        print()


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--session", help="session id の先頭数文字。省略時は最新の transcript")
    ap.add_argument("--cwd", default=os.getcwd(), help="対象プロジェクトの作業ディレクトリ")
    ap.add_argument("--list", action="store_true", help="transcript を新しい順に一覧する")
    ap.add_argument("--json", action="store_true", help="Markdown ではなく JSON で出力する")
    ap.add_argument(
        "--include-sidechain",
        action="store_true",
        help="サブエージェント（isSidechain）の発言も対象にする",
    )
    ap.add_argument(
        "--max-chars",
        type=int,
        default=1200,
        help="各イベント本文の打ち切り文字数（既定 1200）。切れて判断できないときは増やす",
    )
    args = ap.parse_args()

    if args.list:
        files = find_transcripts(args.cwd)
        if not files:
            sys.exit(f"transcript が見つからない: {project_dir(args.cwd)}")
        print(f"# {project_dir(args.cwd)} の transcript（新しい順）")
        print()
        for p in files:
            rows = load_rows(p)
            branches = sorted({r["gitBranch"] for r in rows if r.get("gitBranch")})
            stamps = [r["timestamp"] for r in rows if r.get("timestamp")]
            print(
                f"- `{p.stem[:8]}`  {stamps[0][:16] if stamps else '?'} → "
                f"{stamps[-1][:16] if stamps else '?'}  ({len(rows)} rows)  "
                f"branch: {', '.join(branches) or '(不明)'}"
            )
        return

    data = collect(
        resolve_session(args.cwd, args.session),
        include_sidechain=args.include_sidechain,
        max_chars=args.max_chars,
    )
    if args.json:
        json.dump(data, sys.stdout, ensure_ascii=False, indent=2)
        print()
    else:
        print_report(data)


if __name__ == "__main__":
    main()
