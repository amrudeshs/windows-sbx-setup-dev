#!/usr/bin/env sh
# Network policy for a developer's sandbox.
# Sandboxes are deny-by-default; allow only what the project needs.
#
# Usage:  sh allowlist.sh <db-host>
# Example: sh allowlist.sh 10.0.0.5

set -eu

DB_HOST="${1:?usage: sh allowlist.sh <db-host>}"

# --- Shared database on the on-prem Linux server -----------------------------
sbx policy allow network "${DB_HOST}:5432"

# --- Model provider (keep only the one(s) you use) ---------------------------
sbx policy allow network api.anthropic.com
sbx policy allow network api.x.ai
sbx policy allow network opencode.ai:443

# --- Package registries / source control -------------------------------------
sbx policy allow network registry.npmjs.org
sbx policy allow network pypi.org
sbx policy allow network files.pythonhosted.org
sbx policy allow network proxy.golang.org
sbx policy allow network crates.io
sbx policy allow network github.com:443

# --- Optional: local model server running on THIS machine (e.g. Ollama) ------
# sbx policy allow network localhost:11434

echo "--- active rules ---"
sbx policy ls
