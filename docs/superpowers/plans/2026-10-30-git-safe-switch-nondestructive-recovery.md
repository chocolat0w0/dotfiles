# git-safe-switch Non-destructive Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `git-safe-switch` の復旧処理が、失敗後に生じたファイルや外部更新された参照を追加で破壊しないようにする。

**Architecture:** 実Gitリポジトリを使う回帰テストを追加し、復旧開始前と各再試行前にHEAD・ブランチ参照を検証する。未追跡ファイルは削除せず報告し、作成ブランチは既知のコミットを指す場合だけ削除する。

**Tech Stack:** Bash, Git

**Spec:** `docs/superpowers/specs/2026-10-30-git-safe-switch-nondestructive-recovery-design.md`

## Global Constraints

- 想定外の状態を検出した場合は、それ以上変更せず終了コード 4 で復旧を依頼する。
- 復旧処理はパス名だけを根拠に未追跡ファイルを削除しない。
- 既存の正常な切り替え、通常の復旧、終了コードの意味は維持する。

## Review Focus

- 復旧後に残るtarget-onlyの未追跡ファイルは削除されず、パスが報告されること。
- 復旧前に元ブランチrefが外部更新された場合、`-B` で巻き戻さないこと。
- 復旧再試行間でHEADまたはrefが想定外に変わった場合、それ以上再試行しないこと。
- `-c` で作ったブランチが外部更新された場合、そのブランチを削除しないこと。
- 復旧前に追跡中ファイルが変更された場合、強制復旧で上書きしないこと。
- 作成ブランチの削除直前にref更新が競合した場合、期待値不一致としてブランチを残すこと。
- 作成ブランチがsymbolic refへ変更された場合や別worktreeで使用中の場合、ブランチを削除しないこと。
- 外部変更がない通常の失敗では元のHEADへ戻り、終了コード3を返すこと。

---

### Task 1: 非破壊復旧の回帰テストと実装

**Files:**
- Create: `devcontainer/tests/git-safe-switch-test.sh`
- Modify: `devcontainer/bin/git-safe-switch`

**Interfaces:**
- Consumes: `git-safe-switch` の既存CLIと終了コード 0/1/2/3/4/64
- Produces: `recovery_state_is_expected` 相当の内部状態検査と、非破壊な復旧・報告動作

- [ ] **Step 1: 実Gitリポジトリを作るテストハーネスと、復旧後の未追跡ファイルを残す失敗テストを書く**
- [ ] **Step 2: `bash devcontainer/tests/git-safe-switch-test.sh` を実行し、自動削除によって失敗することを確認する**
- [ ] **Step 3: 外部ref更新時に巻き戻さないテスト、更新済み作成ブランチを削除しないテスト、通常復旧テストを追加し、それぞれ期待理由で失敗することを確認する**
- [ ] **Step 4: `git-safe-switch` に状態検査を追加し、自動 `rm -f` を残存ファイルの報告へ置き換え、作成ブランチ削除をref一致時だけにする**
- [ ] **Step 5: `bash devcontainer/tests/git-safe-switch-test.sh` を実行し、全ケースが成功することを確認する**
- [ ] **Step 6: `bash -n`、Python構文解析、JSON検証、`git diff --check` を実行する**
- [ ] **Step 7: 独立レビューを依頼し、指摘を反映して再検証する**
