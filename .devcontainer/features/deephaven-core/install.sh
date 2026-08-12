#!/bin/sh
set -e

DEEPHAVEN_CORE_POST_ATTACH_SCRIPT_PATH="/usr/local/share/deephaven-core-post-attach.sh"

tee "$DEEPHAVEN_CORE_POST_ATTACH_SCRIPT_PATH" > /dev/null \
<< EOF
#!/bin/sh
set -e
python -m venv .venv-devcontainer
EOF

chmod +x "$DEEPHAVEN_CORE_POST_ATTACH_SCRIPT_PATH"