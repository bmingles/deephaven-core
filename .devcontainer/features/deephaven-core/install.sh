#!/bin/sh
set -e

# Create the Python virtualenv that devcontainer-feature.json's containerEnv points at.
#
# Built here, at image-build time, rather than in a postCreate/postAttach script: the
# venv is then a cached image layer that already exists before the first lifecycle command
# runs, so nothing downstream has to tolerate its absence, and no per-attach work is
# needed. dependsOn orders the python feature ahead of this script, so `python3` on PATH
# is that feature's interpreter.
#
# It lives outside the workspace, which is the more consequential half of the change:
#
#   - The workspace is a bind mount. On macOS and Windows that is virtiofs/gRPC-FUSE, and
#     a venv is thousands of small files — imports and `pip install` are measurably slower
#     there, and it is the one directory here with no reason to be host-visible.
#   - Nothing on the host to .gitignore, and nothing for `git clean -xfd`, gradle's file
#     watcher, or spotless to walk.
#   - One venv per container rather than one per git worktree. The container is already
#     the isolation boundary.
#   - An absolute literal path is what a feature's containerEnv can express (see the note
#     there about Dockerfile ENV).
#
# Kept as a venv rather than installing into the interpreter directly — even though this
# python is source-built, group-writable by the remote user and not PEP 668
# externally-managed, so global installs would work — because the python state should be
# disposable independently of the image. The wheel/editable/jpy install loop
# (`py-server:assemble` then `pip install dist/deephaven_core-*.whl`) does get wedged, and
# recovery should be `rm -rf $VIRTUAL_ENV && python3 -m venv $VIRTUAL_ENV`, not a rebuild.
# With bin/ on the container PATH it behaves like a global install from every tool's
# point of view, so the usual cost of a venv — having to activate it — is not paid.
#
# Not --system-site-packages: the feature's linters and formatters are pipx installs in
# /usr/local/py-utils/bin, which stays on PATH on its own, so isolation costs nothing.
VENV_DIR="/usr/local/share/deephaven-core/venv"

if [ ! -x "$VENV_DIR/bin/python" ]; then
  python3 -m venv "$VENV_DIR"
fi

# Feature install runs as root; hand the tree to the user who will be pip-installing into
# it. _REMOTE_USER is set by the devcontainer CLI.
chown -R "${_REMOTE_USER:-vscode}" "$(dirname "$VENV_DIR")"
