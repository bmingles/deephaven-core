#!/bin/sh
set -e

DEEPHAVEN_CORE_POST_ATTACH_SCRIPT_PATH="/usr/local/share/deephaven-core-post-attach.sh"

cp post-attach.sh "$DEEPHAVEN_CORE_POST_ATTACH_SCRIPT_PATH"
# postAttachCommand invokes it by path, so it has to be executable regardless of the
# mode it was checked in with.
chmod 0755 "$DEEPHAVEN_CORE_POST_ATTACH_SCRIPT_PATH"

# Activate the project's Python virtualenv in every interactive shell. post-attach.sh
# creates the venv, but sourcing `activate` there only affects that script's own process —
# every shell has to source it for itself, hence ~/.bashrc.
#
# Feature install runs as root, so target the remote user's home explicitly instead of
# $HOME. Feature layers are applied on top of the image built from ../../Dockerfile, so
# this lands after the devc bashrc-additions block (and after the python feature's own
# additions). Marker-guarded so a re-install does not double-append.
BASHRC="${_REMOTE_USER_HOME:-/home/${_REMOTE_USER:-vscode}}/.bashrc"
MARKER="# >>> deephaven-core venv >>>"
if ! grep -qF "$MARKER" "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" <<'EOF'

# >>> deephaven-core venv >>>
# PROJECT_PATH is the container-side workspace root (remoteEnv in devcontainer.json).
# Absolute, not relative: a shell can start anywhere, and the venv only exists at the root.
if [ -f "${PROJECT_PATH:-}/.venv-devcontainer/bin/activate" ]; then
  . "$PROJECT_PATH/.venv-devcontainer/bin/activate"
fi
# <<< deephaven-core venv <<<
EOF
fi
