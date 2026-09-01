#!/bin/sh
# postCreateCommand for the Deephaven Core devcontainer — the two setup steps that used to
# live in the local deephaven-core Feature's install.sh, moved here when that Feature was
# folded into devcontainer.json.
#
# Two consequences of the move, both deliberate:
#
#   - This runs at container-*create* time, not image-build time, so it is not a cached
#     layer and repeats on every rebuild. Measured at roughly 15s total, which is not worth
#     reintroducing a Dockerfile to avoid.
#   - It runs as the remote user, not root, so anything touching /usr/local or apt needs
#     sudo. The devcontainer provides passwordless sudo; -n everywhere so a passworded sudo
#     fails fast rather than hanging on a prompt nobody can answer.
#
# Every path exits 0. A failing postCreateCommand aborts container creation, and neither of
# these steps is worth an unbootable container: without the venv you get a loud Python
# error on first use, without dnsname you lose only the multi-container test family. Both
# are recoverable from inside a running container; a container that will not start is not.
set -u

warn() {
  echo "deephaven-core: $*" >&2
}

# --- 1. Python virtualenv --------------------------------------------------------------
#
# Creates the venv that devcontainer.json's remoteEnv points at (VIRTUAL_ENV, and its
# bin/ prepended to PATH).
#
# It lives outside the workspace:
#
#   - The workspace is a bind mount. On macOS and Windows that is virtiofs/gRPC-FUSE, and
#     a venv is thousands of small files — imports and `pip install` are measurably slower
#     there, and it is the one directory here with no reason to be host-visible.
#   - Nothing on the host to .gitignore, and nothing for `git clean -xfd`, gradle's file
#     watcher, or spotless to walk.
#   - One venv per container rather than one per git worktree. The container is already
#     the isolation boundary.
#
# Kept as a venv rather than installing into the interpreter directly — even though this
# python is source-built, group-writable by the remote user and not PEP 668
# externally-managed, so global installs would work — because the python state should be
# disposable independently of the image. The wheel/jpy install loop (`py-server:assemble`
# then `pip install --find-links py/server/build/wheel "deephaven-core[autocomplete]"`)
# does get wedged, and recovery should be `rm -rf $VIRTUAL_ENV && python3 -m venv
# $VIRTUAL_ENV`, not a rebuild. With bin/ on the container PATH it behaves like a global
# install from every tool's point of view, so the usual cost of a venv — having to
# activate it — is not paid.
#
# Not --system-site-packages: the python Feature's linters and formatters are pipx installs
# in /usr/local/py-utils/bin, which stays on PATH on its own, so isolation costs nothing.
#
# Note the venv is created empty. The Deephaven wheels are NOT installed here: building
# them runs `py-server:assemble`, which builds the wheel inside a container and so needs
# the podman API socket — and that socket is only started by the podman-as-docker
# Feature's postStartCommand, which has not run yet at postCreate time. post-start.sh does
# that install, one lifecycle phase later; see its header.
VENV_DIR="/usr/local/share/deephaven-core/venv"
VENV_PARENT="$(dirname "$VENV_DIR")"

if [ ! -x "$VENV_DIR/bin/python" ]; then
  # /usr/local/share is root-owned, so the directory has to be made and handed over before
  # the unprivileged venv creation can write into it.
  if sudo -n mkdir -p "$VENV_PARENT" 2> /dev/null &&
    sudo -n chown "$(id -un)" "$VENV_PARENT" 2> /dev/null; then
    python3 -m venv "$VENV_DIR" || warn "python3 -m venv failed — \$VIRTUAL_ENV is empty"
  else
    warn "could not create $VENV_PARENT (no passwordless sudo?) — venv not created"
  fi
fi

# --- 2. Podman container-name DNS for the gradle deephaven-in-docker tests ---------------
#
# Podman here resolves custom networks through CNI, and the packaged CNI plugin set
# (/usr/lib/cni) ships no `dnsname` — so a network created by `podman network create` comes
# up with no name resolution at all. This installs that one missing plugin; `podman network
# create` then adds dnsname to the plugin chain on its own, and no containers.conf change
# is needed. dnsmasq-base is the resolver dnsname drives, and is not pulled in implicitly.
#
# That matters because the `deephaven-in-docker` gradle plugin
# (buildSrc/.../DeephavenInDockerExtension.groovy) starts the DH server container on a
# per-run network and passes the test container `DH_HOST=<server container name>`,
# expecting DNS on that network to resolve it. Without this the whole family of
# multi-container tests fails: :py-client:testPyClient, :go:testGoClient, :R:testRClient,
# :cpp-client:testCppClient, :py-client-ticking:testCPythonClientTicking-*, and
# web/client-api — all of which are wired into `check`.
#
# NOT netavark/aardvark-dns, which looks like the modern choice and is a dead end here:
# noble pairs podman 4.9.3 with netavark 1.4.0, and with `network_backend = "netavark"`
# pinned, `podman network create` writes to netavark's store while the *container runtime*
# still loads CNI ("Successfully loaded 1 networks" in `podman --log-level=debug run`), so
# every `--network <name>` fails with "network not found" even though `network ls` and
# `network inspect` show it. Verified working on CNI + dnsname instead: resolution by
# container name plus an HTTP fetch between two containers on a created network.
#
# Requires /dev/net/tun (see runArgs in devcontainer.json) — without a real rootless netns
# there are no custom networks for this to serve.
#
# Note this only fixes network *plumbing*. The deephaven-in-docker tests additionally wait
# on the server container's HEALTHCHECK, and podman schedules healthchecks through systemd
# transient timers — with no systemd in this container the status stays "starting" forever
# and `waitForHealthy` times out against a server that is demonstrably up. Those tests
# therefore still do not pass in-container; `podman healthcheck run <container>` works when
# invoked by hand, so a poller could drive them if that is ever worth doing.
if command -v apt-get > /dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  if sudo -n apt-get update -qq 2> /dev/null &&
    sudo -n apt-get install -y --no-install-recommends \
      golang-github-containernetworking-plugin-dnsname dnsmasq-base > /dev/null; then
    :
  else
    warn "dnsname plugin unavailable — podman container-name DNS will not work"
  fi
  sudo -n rm -rf /var/lib/apt/lists/* 2> /dev/null || true
fi

# --- 3. Ownership of the gradle cache volume ---------------------------------------------
#
# The gradle-cache-${devcontainerId} mount in devcontainer.json targets ~/.gradle, a path
# that does not exist in the image. Docker seeds a new named volume from whatever the image
# has at the target and carries that path's ownership across with it — with nothing there
# to copy, it creates the mount point root-owned instead, sitting inside an otherwise
# vscode-owned home. The remote user then cannot write to its own gradle home and the first
# thing ./gradlew does is die:
#
#   Could not create parent directory for lock file
#   /home/vscode/.gradle/wrapper/dists/gradle-<v>-all/<hash>/gradle-<v>-all.zip.lck
#
# taking post-start.sh's wheel build down with it (it fails "after 0s" — the wrapper never
# gets as far as starting a build, so the failure looks nothing like a gradle problem).
#
# Only the mount point itself is wrong, so this is a one-level chown, not -R: anything
# gradle writes underneath is already owned by the user that wrote it. Guarded on the
# directory being unwritable, so it is a no-op on every rebuild that reuses a volume this
# has already fixed.
GRADLE_HOME="$HOME/.gradle"
if [ -d "$GRADLE_HOME" ] && [ ! -w "$GRADLE_HOME" ]; then
  sudo -n chown "$(id -un):$(id -gn)" "$GRADLE_HOME" 2> /dev/null ||
    warn "could not chown $GRADLE_HOME — ./gradlew cannot write its cache"
fi

exit 0
