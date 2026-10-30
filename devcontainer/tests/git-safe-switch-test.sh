#!/usr/bin/env bash

set -u

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
safe_switch="${repo_root}/devcontainer/bin/git-safe-switch"
real_git=$(command -v git)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/git-safe-switch-test.XXXXXXXX") || exit 1
trap 'rm -rf "$test_root"' EXIT

# git-safe-switch runs in Linux devcontainers, where GNU comm supports -z.
# Supply the same narrow behavior when these tests run on macOS.
mkdir -p "${test_root}/bin"
cat > "${test_root}/bin/comm" <<'PY'
#!/usr/bin/env python3
import sys

if len(sys.argv) != 5 or sys.argv[1:3] != ["-z", "-13"]:
    raise SystemExit("unsupported test invocation")
with open(sys.argv[3], "rb") as before_file:
    before = set(before_file.read().split(b"\0"))
with open(sys.argv[4], "rb") as after_file:
    after = set(after_file.read().split(b"\0"))
paths = sorted((after - before) - {b""})
if paths:
    sys.stdout.buffer.write(b"\0".join(paths) + b"\0")
PY
chmod +x "${test_root}/bin/comm"

failures=0

fail() {
  echo "not ok - $1" >&2
  failures=$((failures + 1))
}

new_repo() {
  local name="$1"
  local repo="${test_root}/${name}"

  git init -q "$repo"
  git -C "$repo" config user.name test
  git -C "$repo" config user.email test@example.com
  echo base > "${repo}/shared.txt"
  git -C "$repo" add shared.txt
  git -C "$repo" commit -qm base
  printf '%s' "$repo"
}

run_safe_switch() {
  local repo="$1"
  shift

  (cd "$repo" && PATH="${test_root}/bin:${PATH}" "$safe_switch" "$@" >safe-switch.out 2>&1)
  safe_switch_status=$?
}

make_target_branch() {
  local repo="$1"
  local orig_branch

  orig_branch=$(git -C "$repo" branch --show-current)
  git -C "$repo" switch -qc target
  echo target > "${repo}/target-only.txt"
  git -C "$repo" add target-only.txt
  git -C "$repo" commit -qm target
  git -C "$repo" switch -q "$orig_branch"
}

write_test_state() {
  local repo="$1"
  local orig_branch orig_sha target_sha external_sha

  orig_branch=$(git -C "$repo" branch --show-current)
  orig_sha=$(git -C "$repo" rev-parse HEAD)
  target_sha=$(git -C "$repo" rev-parse target)
  external_sha=$(printf 'external\n' | git -C "$repo" commit-tree "${target_sha}^{tree}" -p "$orig_sha")
  printf '%s\n' "$orig_branch" > "${repo}/.git/test-orig-branch"
  printf '%s\n' "$orig_sha" > "${repo}/.git/test-orig-sha"
  printf '%s\n' "$target_sha" > "${repo}/.git/test-target-sha"
  printf '%s\n' "$external_sha" > "${repo}/.git/test-external-sha"
}

test_recovery_does_not_delete_new_untracked_file() {
  local repo orig_branch orig_sha target_sha status
  repo=$(new_repo preserve-untracked)
  orig_branch=$(git -C "$repo" branch --show-current)
  orig_sha=$(git -C "$repo" rev-parse HEAD)
  make_target_branch "$repo"
  target_sha=$(git -C "$repo" rev-parse target)

  printf '%s\n' "$orig_sha" > "${repo}/.git/test-orig-sha"
  printf '%s\n' "$target_sha" > "${repo}/.git/test-target-sha"
  cat > "${repo}/.git/hooks/post-checkout" <<'HOOK'
#!/bin/sh
git_dir=$(git rev-parse --git-dir)
orig_sha=$(cat "${git_dir}/test-orig-sha")
target_sha=$(cat "${git_dir}/test-target-sha")

if [ "$2" = "$target_sha" ]; then
  exit 1
fi
if [ "$2" = "$orig_sha" ]; then
  echo preserved > target-only.txt
fi
HOOK
  chmod +x "${repo}/.git/hooks/post-checkout"

  run_safe_switch "$repo" target
  status=$safe_switch_status

  [ "$status" -eq 3 ] || fail "recovery should return 3, got ${status}"
  [ -f "${repo}/target-only.txt" ] || fail "recovery must not delete a newly untracked file"
  if [ -f "${repo}/target-only.txt" ]; then
    [ "$(cat "${repo}/target-only.txt")" = preserved ] || fail "recovery changed the newly untracked file"
  fi
}

test_recovery_does_not_reset_externally_updated_original_branch() {
  local repo orig_branch external_sha
  repo=$(new_repo preserve-original-ref)
  make_target_branch "$repo"
  write_test_state "$repo"
  orig_branch=$(cat "${repo}/.git/test-orig-branch")
  external_sha=$(cat "${repo}/.git/test-external-sha")

  cat > "${repo}/.git/hooks/post-checkout" <<'HOOK'
#!/bin/sh
git_dir=$(git rev-parse --git-dir)
target_sha=$(cat "${git_dir}/test-target-sha")
if [ "$2" = "$target_sha" ]; then
  orig_branch=$(cat "${git_dir}/test-orig-branch")
  orig_sha=$(cat "${git_dir}/test-orig-sha")
  external_sha=$(cat "${git_dir}/test-external-sha")
  git update-ref "refs/heads/${orig_branch}" "$external_sha" "$orig_sha"
  exit 1
fi
HOOK
  chmod +x "${repo}/.git/hooks/post-checkout"

  run_safe_switch "$repo" target

  [ "$safe_switch_status" -eq 4 ] || fail "external original-branch update should stop recovery with 4, got ${safe_switch_status}"
  [ "$(git -C "$repo" rev-parse "refs/heads/${orig_branch}")" = "$external_sha" ] || fail "recovery reset an externally updated original branch"
}

test_recovery_stops_before_retry_after_ref_changes() {
  local repo orig_branch external_sha
  repo=$(new_repo preserve-ref-between-retries)
  make_target_branch "$repo"
  write_test_state "$repo"
  orig_branch=$(cat "${repo}/.git/test-orig-branch")
  external_sha=$(cat "${repo}/.git/test-external-sha")

  cat > "${repo}/.git/hooks/post-checkout" <<'HOOK'
#!/bin/sh
git_dir=$(git rev-parse --git-dir)
orig_sha=$(cat "${git_dir}/test-orig-sha")
target_sha=$(cat "${git_dir}/test-target-sha")
if [ "$2" = "$target_sha" ]; then
  exit 1
fi
if [ "$2" = "$orig_sha" ] && [ ! -e "${git_dir}/test-first-restore" ]; then
  orig_branch=$(cat "${git_dir}/test-orig-branch")
  external_sha=$(cat "${git_dir}/test-external-sha")
  : > "${git_dir}/test-first-restore"
  git update-ref "refs/heads/${orig_branch}" "$external_sha" "$orig_sha"
  exit 1
fi
HOOK
  chmod +x "${repo}/.git/hooks/post-checkout"

  run_safe_switch "$repo" target

  [ "$safe_switch_status" -eq 4 ] || fail "ref change between retries should stop recovery with 4, got ${safe_switch_status}"
  [ "$(git -C "$repo" rev-parse "refs/heads/${orig_branch}")" = "$external_sha" ] || fail "a recovery retry reset an externally updated branch"
}

test_recovery_does_not_delete_updated_created_branch() {
  local repo external_sha
  repo=$(new_repo preserve-created-ref)
  make_target_branch "$repo"
  write_test_state "$repo"
  external_sha=$(cat "${repo}/.git/test-external-sha")

  cat > "${repo}/.git/hooks/post-checkout" <<'HOOK'
#!/bin/sh
git_dir=$(git rev-parse --git-dir)
orig_sha=$(cat "${git_dir}/test-orig-sha")
target_sha=$(cat "${git_dir}/test-target-sha")
if [ "$2" = "$target_sha" ]; then
  exit 1
fi
if [ "$2" = "$orig_sha" ]; then
  external_sha=$(cat "${git_dir}/test-external-sha")
  git update-ref refs/heads/created "$external_sha" "$target_sha"
fi
HOOK
  chmod +x "${repo}/.git/hooks/post-checkout"

  run_safe_switch "$repo" -c created target

  [ "$safe_switch_status" -eq 3 ] || fail "successful recovery after create should return 3, got ${safe_switch_status}"
  git -C "$repo" show-ref --verify --quiet refs/heads/created || fail "recovery deleted an externally updated created branch"
  if git -C "$repo" show-ref --verify --quiet refs/heads/created; then
    [ "$(git -C "$repo" rev-parse refs/heads/created)" = "$external_sha" ] || fail "recovery changed the updated created branch"
  fi
}

test_normal_recovery_still_restores_original_head() {
  local repo orig_branch orig_sha
  repo=$(new_repo normal-recovery)
  make_target_branch "$repo"
  write_test_state "$repo"
  orig_branch=$(cat "${repo}/.git/test-orig-branch")
  orig_sha=$(cat "${repo}/.git/test-orig-sha")

  cat > "${repo}/.git/hooks/post-checkout" <<'HOOK'
#!/bin/sh
git_dir=$(git rev-parse --git-dir)
target_sha=$(cat "${git_dir}/test-target-sha")
[ "$2" != "$target_sha" ]
HOOK
  chmod +x "${repo}/.git/hooks/post-checkout"

  run_safe_switch "$repo" target

  [ "$safe_switch_status" -eq 3 ] || fail "normal recovery should return 3, got ${safe_switch_status}"
  [ "$(git -C "$repo" branch --show-current)" = "$orig_branch" ] || fail "normal recovery did not restore the original branch"
  [ "$(git -C "$repo" rev-parse HEAD)" = "$orig_sha" ] || fail "normal recovery did not restore the original HEAD"
}

test_recovery_stops_on_unexpected_branch_at_known_sha() {
  local repo target_sha
  repo=$(new_repo preserve-unexpected-branch)
  make_target_branch "$repo"
  write_test_state "$repo"
  target_sha=$(cat "${repo}/.git/test-target-sha")
  git -C "$repo" branch other "$target_sha"

  cat > "${repo}/.git/hooks/post-checkout" <<'HOOK'
#!/bin/sh
git_dir=$(git rev-parse --git-dir)
target_sha=$(cat "${git_dir}/test-target-sha")
if [ "$2" = "$target_sha" ]; then
  git symbolic-ref HEAD refs/heads/other
  echo external-edit > shared.txt
  exit 1
fi
HOOK
  chmod +x "${repo}/.git/hooks/post-checkout"

  run_safe_switch "$repo" target

  [ "$safe_switch_status" -eq 4 ] || fail "unexpected branch at a known SHA should stop recovery with 4, got ${safe_switch_status}"
  [ "$(git -C "$repo" branch --show-current)" = other ] || fail "recovery changed an unexpected current branch"
  [ "$(cat "${repo}/shared.txt")" = external-edit ] || fail "recovery overwrote a tracked edit on an unexpected branch"
}

test_recovery_stops_before_overwriting_new_untracked_file() {
  local repo orig_branch
  repo=$(new_repo preserve-untracked-before-recovery)
  orig_branch=$(git -C "$repo" branch --show-current)
  echo base > "${repo}/original-only.txt"
  git -C "$repo" add original-only.txt
  git -C "$repo" commit -qm original-file
  git -C "$repo" switch -qc target
  git -C "$repo" rm -q original-only.txt
  git -C "$repo" commit -qm remove-original-file
  git -C "$repo" switch -q "$orig_branch"
  write_test_state "$repo"

  cat > "${repo}/.git/hooks/post-checkout" <<'HOOK'
#!/bin/sh
git_dir=$(git rev-parse --git-dir)
target_sha=$(cat "${git_dir}/test-target-sha")
if [ "$2" = "$target_sha" ]; then
  echo new-user-data > original-only.txt
  exit 1
fi
HOOK
  chmod +x "${repo}/.git/hooks/post-checkout"

  run_safe_switch "$repo" target

  [ "$safe_switch_status" -eq 4 ] || fail "new untracked file before recovery should stop recovery with 4, got ${safe_switch_status}"
  [ "$(cat "${repo}/original-only.txt")" = new-user-data ] || fail "recovery overwrote a newly untracked file"
}

test_recovery_stops_before_overwriting_tracked_edit() {
  local repo
  repo=$(new_repo preserve-tracked-edit)
  make_target_branch "$repo"
  write_test_state "$repo"

  cat > "${repo}/.git/hooks/post-checkout" <<'HOOK'
#!/bin/sh
git_dir=$(git rev-parse --git-dir)
target_sha=$(cat "${git_dir}/test-target-sha")
if [ "$2" = "$target_sha" ]; then
  echo external-user-data > shared.txt
  exit 1
fi
HOOK
  chmod +x "${repo}/.git/hooks/post-checkout"

  run_safe_switch "$repo" target

  [ "$safe_switch_status" -eq 4 ] || fail "tracked edit before recovery should stop recovery with 4, got ${safe_switch_status}"
  [ "$(git -C "$repo" branch --show-current)" = target ] || fail "recovery changed branch after a tracked edit"
  [ "$(cat "${repo}/shared.txt")" = external-user-data ] || fail "recovery overwrote a tracked edit"
}

test_created_branch_delete_preserves_concurrent_update() {
  local repo external_sha race_bin
  repo=$(new_repo preserve-created-ref-race)
  make_target_branch "$repo"
  write_test_state "$repo"
  external_sha=$(cat "${repo}/.git/test-external-sha")
  race_bin="${repo}/race-bin"
  mkdir -p "$race_bin"

  cat > "${repo}/.git/hooks/post-checkout" <<'HOOK'
#!/bin/sh
git_dir=$(git rev-parse --git-dir)
target_sha=$(cat "${git_dir}/test-target-sha")
[ "$2" != "$target_sha" ]
HOOK
  chmod +x "${repo}/.git/hooks/post-checkout"

  cat > "${race_bin}/git" <<'HOOK'
#!/bin/sh
should_race=false
if [ "${1:-}" = branch ] && [ "${2:-}" = -D ] && [ "${3:-}" = created ]; then
  should_race=true
elif [ "${1:-}" = update-ref ] && [ "${2:-}" = -d ] && [ "${3:-}" = refs/heads/created ]; then
  should_race=true
elif [ "${1:-}" = update-ref ] && [ "${2:-}" = --no-deref ] && [ "${3:-}" = -d ] && [ "${4:-}" = refs/heads/created ]; then
  should_race=true
fi

if [ "$should_race" = true ]; then
  git_dir=$($REAL_GIT rev-parse --git-dir)
  target_sha=$(cat "${git_dir}/test-target-sha")
  external_sha=$(cat "${git_dir}/test-external-sha")
  $REAL_GIT update-ref refs/heads/created "$external_sha" "$target_sha"
fi

exec $REAL_GIT "$@"
HOOK
  chmod +x "${race_bin}/git"

  (cd "$repo" && REAL_GIT="$real_git" PATH="${race_bin}:${test_root}/bin:${PATH}" "$safe_switch" -c created target >safe-switch.out 2>&1)
  safe_switch_status=$?

  [ "$safe_switch_status" -eq 3 ] || fail "successful recovery during created-branch race should return 3, got ${safe_switch_status}"
  git -C "$repo" show-ref --verify --quiet refs/heads/created || fail "created branch was deleted after a concurrent update"
  if git -C "$repo" show-ref --verify --quiet refs/heads/created; then
    [ "$(git -C "$repo" rev-parse refs/heads/created)" = "$external_sha" ] || fail "created branch lost its concurrent update"
  fi
}

test_created_branch_delete_does_not_follow_symbolic_ref() {
  local repo target_sha
  repo=$(new_repo preserve-created-symbolic-ref)
  make_target_branch "$repo"
  write_test_state "$repo"
  target_sha=$(cat "${repo}/.git/test-target-sha")
  git -C "$repo" branch victim "$target_sha"

  cat > "${repo}/.git/hooks/post-checkout" <<'HOOK'
#!/bin/sh
git_dir=$(git rev-parse --git-dir)
orig_sha=$(cat "${git_dir}/test-orig-sha")
target_sha=$(cat "${git_dir}/test-target-sha")
if [ "$2" = "$target_sha" ]; then
  exit 1
fi
if [ "$2" = "$orig_sha" ]; then
  git symbolic-ref refs/heads/created refs/heads/victim
fi
HOOK
  chmod +x "${repo}/.git/hooks/post-checkout"

  run_safe_switch "$repo" -c created target

  [ "$safe_switch_status" -eq 3 ] || fail "successful recovery with a symbolic created ref should return 3, got ${safe_switch_status}"
  git -C "$repo" show-ref --verify --quiet refs/heads/victim || fail "created-branch cleanup deleted a symbolic ref target"
  [ "$(git -C "$repo" symbolic-ref -q refs/heads/created || true)" = refs/heads/victim ] || fail "created symbolic ref was changed during cleanup"
}

test_created_branch_delete_preserves_branch_used_by_other_worktree() {
  local repo other_worktree target_sha
  repo=$(new_repo preserve-created-worktree)
  make_target_branch "$repo"
  write_test_state "$repo"
  target_sha=$(cat "${repo}/.git/test-target-sha")
  other_worktree="${test_root}/created-worktree"
  printf '%s\n' "$other_worktree" > "${repo}/.git/test-other-worktree"

  cat > "${repo}/.git/hooks/post-checkout" <<'HOOK'
#!/bin/sh
common_dir=$(git rev-parse --git-common-dir)
orig_sha=$(cat "${common_dir}/test-orig-sha")
target_sha=$(cat "${common_dir}/test-target-sha")
marker="${common_dir}/test-adding-worktree"
if [ "$2" = "$target_sha" ] && [ ! -e "$marker" ]; then
  exit 1
fi
if [ "$2" = "$orig_sha" ] && [ ! -e "$marker" ]; then
  : > "$marker"
  other_worktree=$(cat "${common_dir}/test-other-worktree")
  git worktree add -q "$other_worktree" created
fi
HOOK
  chmod +x "${repo}/.git/hooks/post-checkout"

  run_safe_switch "$repo" -c created target

  [ "$safe_switch_status" -eq 3 ] || fail "successful recovery with created in another worktree should return 3, got ${safe_switch_status}"
  git -C "$repo" show-ref --verify --quiet refs/heads/created || fail "cleanup deleted a branch used by another worktree"
  [ "$(git -C "$other_worktree" branch --show-current)" = created ] || fail "cleanup detached the other worktree from created"
  [ "$(git -C "$other_worktree" rev-parse HEAD)" = "$target_sha" ] || fail "cleanup changed the other worktree HEAD"
}

test_recovery_does_not_delete_new_untracked_file
test_recovery_does_not_reset_externally_updated_original_branch
test_recovery_stops_before_retry_after_ref_changes
test_recovery_does_not_delete_updated_created_branch
test_normal_recovery_still_restores_original_head
test_recovery_stops_on_unexpected_branch_at_known_sha
test_recovery_stops_before_overwriting_new_untracked_file
test_recovery_stops_before_overwriting_tracked_edit
test_created_branch_delete_preserves_concurrent_update
test_created_branch_delete_does_not_follow_symbolic_ref
test_created_branch_delete_preserves_branch_used_by_other_worktree

if [ "$failures" -ne 0 ]; then
  echo "${failures} test assertion(s) failed" >&2
  exit 1
fi

echo "ok - git-safe-switch recovery tests"
