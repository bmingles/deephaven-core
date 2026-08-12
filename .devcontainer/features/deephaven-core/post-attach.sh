#!/bin/sh
set -e

# cwd should be workspace root. Handle activating the venv in ~/.bashrc since 
# sourcing `activate` here would only affect this process (see install.sh).
python -m venv .venv-devcontainer
