#!/bin/bash
# Sideways installer

set -e

# Configuration (update these if forking)
GITHUB_USER="${GITHUB_USER:-soumyaray}"
GITHUB_REPO="${GITHUB_REPO:-sideways}"

INSTALL_DIR="${HOME}/.sideways"
REPO_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"

echo "Installing Sideways..."

# Clone or update
if [[ -d "$INSTALL_DIR" ]]; then
    echo "Updating existing installation..."
    git -C "$INSTALL_DIR" pull --quiet
else
    echo "Cloning to $INSTALL_DIR..."
    git clone --quiet "$REPO_URL" "$INSTALL_DIR"
fi

# Detect shell config file
if [[ -n "$ZSH_VERSION" ]] || [[ "$SHELL" == */zsh ]]; then
    SHELL_RC="${HOME}/.zshrc"
elif [[ -n "$BASH_VERSION" ]] || [[ "$SHELL" == */bash ]]; then
    SHELL_RC="${HOME}/.bashrc"
else
    SHELL_RC="${HOME}/.profile"
fi

SOURCE_LINE="source \"\${HOME}/.sideways/worktrees.sh\""

# Add source line if not already present
if ! grep -qF ".sideways/worktrees.sh" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# Sideways - git worktree helper" >> "$SHELL_RC"
    echo "$SOURCE_LINE" >> "$SHELL_RC"
    echo "Added to $SHELL_RC"
else
    echo "Already configured in $SHELL_RC"
fi

echo ""
echo "Done! Restart your shell or run:"
echo "  source $SHELL_RC"
