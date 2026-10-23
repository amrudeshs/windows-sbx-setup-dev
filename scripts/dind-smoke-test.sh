#!/usr/bin/env sh
# Smoke test: does Docker (and Compose) work inside THIS sbx sandbox?
#
# Run it from a shell inside the sandbox:  sh scripts/dind-smoke-test.sh
# Checks, in order:
#   1. the Docker daemon is the sandbox's own (not a host daemon)
#   2. an image can be fetched (hello-world, busybox:stable)
#   3. a container runs
#   4. two containers resolve each other by name on a user-defined network
#   5. a two-service Docker Compose project works
# Exit status is non-zero if any check fails. Everything it creates is removed on exit.

set -u

SUFFIX="$$"
NET="dindtest-net-$SUFFIX"
PROJECT="dindtest$SUFFIX"
WORKDIR="$(mktemp -d)"
FAILED=0

cleanup() {
  docker rm -f "dindtest-a-$SUFFIX" >/dev/null 2>&1
  docker network rm "$NET" >/dev/null 2>&1
  if [ -f "$WORKDIR/compose.yaml" ]; then
    docker compose -p "$PROJECT" -f "$WORKDIR/compose.yaml" down -v --remove-orphans >/dev/null 2>&1
  fi
  rm -rf "$WORKDIR"
}
trap cleanup EXIT INT TERM

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILED=1; }

# Use a local image if present; otherwise pull it, and explain the usual failure.
ensure_image() {
  if docker image inspect "$1" >/dev/null 2>&1; then
    return 0
  fi
  if docker pull -q "$1" >"$WORKDIR/pull.log" 2>&1; then
    return 0
  fi
  cat "$WORKDIR/pull.log" >&2
  if grep -q "x509" "$WORKDIR/pull.log"; then
    echo "      Hint: TLS inspection on the network. See 11-troubleshooting.md," >&2
    echo "      section 'docker pull fails with x509: certificate signed by unknown authority'." >&2
  fi
  return 1
}

# 1. Whose daemon is this? A sandbox's daemon reports the sandbox's name and its own kernel.
if ! docker info >/dev/null 2>&1; then
  fail "docker daemon not reachable"
  exit 1
fi
DAEMON_NAME="$(docker info --format '{{.Name}}')"
echo "info  daemon: $DAEMON_NAME | server $(docker version --format '{{.Server.Version}}') | kernel $(uname -r) | host $(hostname)"
if [ "$DAEMON_NAME" = "$(hostname)" ]; then
  pass "daemon name matches this machine's hostname (the sandbox's own daemon)"
else
  fail "daemon name '$DAEMON_NAME' differs from hostname '$(hostname)': this may be a host daemon"
fi

# 2 + 3. Fetch and run a container.
if ensure_image hello-world && docker run --rm hello-world 2>&1 | grep -q "Hello from Docker!"; then
  pass "hello-world image available and container ran"
else
  fail "could not fetch/run hello-world"
fi

# 4. User-defined network with name resolution (what Compose relies on).
if ensure_image busybox:stable; then
  if docker network create "$NET" >/dev/null &&
     docker run -d --name "dindtest-a-$SUFFIX" --network "$NET" busybox:stable sleep 60 >/dev/null &&
     docker run --rm --network "$NET" busybox:stable ping -c 1 -W 2 "dindtest-a-$SUFFIX" >/dev/null 2>&1; then
    pass "containers resolve each other by name on a user-defined network"
  else
    fail "user-defined network name resolution"
  fi
else
  fail "could not fetch busybox:stable"
fi

# 5. Compose: a service that waits for another and talks to it by service name.
cat >"$WORKDIR/compose.yaml" <<'YAML'
services:
  web:
    image: busybox:stable
    command: sleep 120
  probe:
    image: busybox:stable
    command: ping -c 1 -W 2 web
    depends_on:
      - web
YAML
if docker compose version >/dev/null 2>&1; then
  if docker compose -p "$PROJECT" -f "$WORKDIR/compose.yaml" up --exit-code-from probe >"$WORKDIR/compose.log" 2>&1; then
    pass "docker compose project with two services ran"
  else
    cat "$WORKDIR/compose.log" >&2
    fail "docker compose project"
  fi
else
  fail "docker compose plugin not found"
fi

if [ "$FAILED" -eq 0 ]; then
  echo "All checks passed."
else
  echo "Some checks failed."
fi
exit "$FAILED"
