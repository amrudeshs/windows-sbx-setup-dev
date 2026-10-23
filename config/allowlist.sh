#!/usr/bin/env sh
# Network policy for a developer's sandbox.
# Sandboxes are deny-by-default; allow only what the project needs.
#
# Usage:   sh allowlist.sh <db-host> <providers> [-- <extra-host[:port]>...]
#   <providers>  comma-separated model providers: anthropic,openai,xai,opencode
#                (allow only the ones you actually use)
#
# Examples:
#   sh allowlist.sh 10.0.0.5 anthropic
#   sh allowlist.sh 10.0.0.5 anthropic,opencode -- repo.maven.apache.org:443 api.nuget.org:443
#
# Optional switches (environment variables):
#   WITH_APT=1     also allow Ubuntu apt mirrors (needed for `sudo apt install` in a sandbox)
#
# Start from the "Locked Down" preset (see 06-networking-and-policy.md) so this script is the
# complete, reviewable list of what a sandbox can reach.
#
# NOTE: github.com is both a dependency source and a data-exfiltration path (push to any repo,
# create a gist). Keep the rest of the list as small as you can.

set -eu

usage() {
  echo "usage: sh allowlist.sh <db-host> <providers> [-- <extra-host[:port]>...]" >&2
  exit 2
}

[ $# -ge 2 ] || usage
DB_HOST="$1"
PROVIDERS="$2"
shift 2

if [ $# -gt 0 ]; then
  [ "$1" = "--" ] || usage
  shift
fi

allow() {
  sbx policy allow network "$1"
}

# Resolve providers to hosts first, so a typo exits before any policy is changed.
PROVIDER_HOSTS=""
old_ifs="$IFS"
IFS=','
for provider in $PROVIDERS; do
  case "$provider" in
    anthropic) host=api.anthropic.com:443 ;;
    openai)    host=api.openai.com:443 ;;
    xai)       host=api.x.ai:443 ;;
    opencode)  host=opencode.ai:443 ;;
    *) echo "unknown provider: $provider (anthropic, openai, xai, opencode)" >&2; exit 2 ;;
  esac
  PROVIDER_HOSTS="$PROVIDER_HOSTS $host"
done
IFS="$old_ifs"

# --- Shared database on the on-prem Linux server -----------------------------
allow "${DB_HOST}:5432"

# --- Model provider(s) -------------------------------------------------------
for host in $PROVIDER_HOSTS; do
  allow "$host"
done

# --- Package registries ------------------------------------------------------
allow registry.npmjs.org:443
allow pypi.org:443
allow files.pythonhosted.org:443
allow proxy.golang.org:443
allow crates.io:443
allow static.crates.io:443

# --- Container images (docker compose build/pull inside the sandbox) ---------
allow registry-1.docker.io:443
allow auth.docker.io:443
allow production.cloudflare.docker.com:443
allow ghcr.io:443

# --- Source control ----------------------------------------------------------
allow github.com:443
allow api.github.com:443
allow codeload.github.com:443
allow raw.githubusercontent.com:443

# --- Optional: OS packages ---------------------------------------------------
if [ "${WITH_APT:-0}" = "1" ]; then
  allow archive.ubuntu.com:443
  allow security.ubuntu.com:443
fi

# --- Optional: project-specific hosts (private registries, Maven, NuGet, ...) --
for host in "$@"; do
  allow "$host"
done

# --- Optional: local model server running on THIS machine (e.g. Ollama) ------
# sbx policy allow network localhost:11434

echo "--- active rules ---"
sbx policy ls
