#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd "$(dirname "$0")"; pwd)
skills_dir="${script_dir}/skills"

install_skills() {
  local source_dir="$1"
  local agent_skills_dir="$2"
  local skill_source
  local skill_name
  local target_dir

  [ -d "${source_dir}" ] || return 0

  for skill_source in "${source_dir}"/*; do
    [ -d "${skill_source}" ] || continue

    skill_name=$(basename "${skill_source}")
    if [ ! -f "${skill_source}/SKILL.md" ]; then
      echo "skip ${skill_name}: SKILL.md is missing" >&2
      continue
    fi

    target_dir="${agent_skills_dir}/${skill_name}"
    mkdir -p "${target_dir}"
    cp -a "${skill_source}/." "${target_dir}/"
    echo "installed generic skill: ${skill_name} -> ${agent_skills_dir}"
  done
}

# Skills available to both coding agents.
install_skills "${skills_dir}/shared" "${HOME}/.codex/skills"
install_skills "${skills_dir}/shared" "${HOME}/.claude/skills"

# Harness-specific skills. Use these for workflows that call the other agent.
install_skills "${skills_dir}/claude" "${HOME}/.claude/skills"
install_skills "${skills_dir}/codex" "${HOME}/.codex/skills"
