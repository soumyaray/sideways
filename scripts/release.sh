#!/bin/bash
#
# Release script for sideways
#
# Usage: ./scripts/release.sh [--dry-run] <version>
#        ./scripts/release.sh --init [version]
#
# Options:
#   --dry-run    Show what would happen without making changes
#   --init       Create first release (defaults to 0.1.0)
#
# This script:
# 1. Creates and pushes a git tag
# 2. Calculates the SHA256 of the release tarball
# 3. Updates the Homebrew formula in homebrew-sideways
# 4. Commits and pushes the formula update

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}Warning: $1${NC}" >&2
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

info() {
    echo -e "$1"
}

dry_run() {
    echo -e "${YELLOW}[dry-run]${NC} $1"
}

# ------------------------------------------------------------------------------
# Argument Parsing
# ------------------------------------------------------------------------------

DRY_RUN=false
INIT=false
VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --init)
            INIT=true
            shift
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            VERSION="$1"
            shift
            ;;
    esac
done

# Get latest version tag (used for display and --init warning)
LATEST_TAG=$(git tag --sort=-v:refname 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

# Handle --init flag
if $INIT; then
    if [[ -n "$LATEST_TAG" ]]; then
        warn "Tags already exist (latest: $LATEST_TAG). Use --init only for first release."
        echo -n "Continue anyway? [y/N] "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 1
        fi
    fi
    # Default to 0.1.0 if no version specified with --init
    VERSION="${VERSION:-0.1.0}"
fi

if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 [--dry-run] <version>"
    echo "       $0 --init [version]"
    echo ""
    if [[ -n "$LATEST_TAG" ]]; then
        echo "Current version: $LATEST_TAG"
        echo ""
    fi
    echo "Options:"
    echo "  --dry-run    Show what would happen without making changes"
    echo "  --init       Create first release (defaults to 0.1.0)"
    echo ""
    echo "Examples:"
    echo "  $0 --init              # First release (v0.1.0)"
    echo "  $0 0.2.0               # Release v0.2.0"
    echo "  $0 --dry-run 0.2.0     # Preview without making changes"
    exit 1
fi

# Normalize version: strip leading 'v' if present, then use consistently
VERSION="${VERSION#v}"

# Validate semver format (X.Y.Z)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "Invalid version format: $VERSION (expected X.Y.Z)"
fi

TAG="v$VERSION"

if $DRY_RUN; then
    echo ""
    echo -e "${YELLOW}=========================================="
    echo "DRY RUN MODE - No changes will be made"
    echo -e "==========================================${NC}"
    echo ""
fi

# ------------------------------------------------------------------------------
# Pre-flight Checks
# ------------------------------------------------------------------------------

# Verify we're in the sideways repo root
if [[ ! -f "worktrees.sh" ]]; then
    error "Must run from sideways repo root (worktrees.sh not found)"
fi

# Verify working directory is clean
if [[ -n "$(git status --porcelain)" ]]; then
    error "Working directory is not clean. Commit or stash changes first."
fi

# Verify on main branch
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    error "Must be on main branch (currently on: $CURRENT_BRANCH)"
fi

# Check that tag doesn't already exist locally
if git tag -l "$TAG" | grep -q "^$TAG$"; then
    error "Tag $TAG already exists locally"
fi

# Check that tag doesn't already exist remotely
if git ls-remote --tags origin | grep -q "refs/tags/$TAG$"; then
    error "Tag $TAG already exists on remote"
fi

# Verify homebrew-sideways repo exists
HOMEBREW_REPO="../homebrew-sideways"
if [[ ! -d "$HOMEBREW_REPO" ]]; then
    error "Homebrew tap not found at $HOMEBREW_REPO"
fi

if [[ ! -f "$HOMEBREW_REPO/Formula/sideways.rb" ]]; then
    error "Formula not found at $HOMEBREW_REPO/Formula/sideways.rb"
fi

info "Pre-flight checks passed"
info ""

# ------------------------------------------------------------------------------
# Create and Push Tag
# ------------------------------------------------------------------------------

if $DRY_RUN; then
    dry_run "Would create tag: git tag -a $TAG -m \"Release $TAG\""
    dry_run "Would push tag: git push origin $TAG"
else
    info "Creating tag $TAG..."
    git tag -a "$TAG" -m "Release $TAG"
    success "Created tag $TAG"

    info "Pushing tag to origin..."
    git push origin "$TAG"
    success "Pushed tag to origin"

    # Brief pause for GitHub to process
    sleep 2
fi

# ------------------------------------------------------------------------------
# Calculate SHA256
# ------------------------------------------------------------------------------

TARBALL_URL="https://github.com/soumyaray/sideways/archive/refs/tags/$TAG.tar.gz"

if $DRY_RUN; then
    dry_run "Would fetch tarball from: $TARBALL_URL"
    dry_run "Would calculate SHA256 (not available in dry-run for new tags)"
    SHA256="<sha256-would-be-calculated>"
else
    info "Fetching tarball from GitHub..."
    TARBALL=$(curl -sL "$TARBALL_URL")

    if [[ -z "$TARBALL" ]]; then
        error "Failed to fetch tarball from $TARBALL_URL"
    fi

    SHA256=$(echo "$TARBALL" | shasum -a 256 | awk '{print $1}')

    if [[ -z "$SHA256" ]] || [[ ${#SHA256} -ne 64 ]]; then
        error "Failed to calculate valid SHA256"
    fi

    success "SHA256: $SHA256"
fi

# ------------------------------------------------------------------------------
# Update Homebrew Formula
# ------------------------------------------------------------------------------

ORIGINAL_DIR=$(pwd)
cd "$HOMEBREW_REPO"

# Verify homebrew repo is clean
if [[ -n "$(git status --porcelain)" ]]; then
    cd "$ORIGINAL_DIR"
    error "Homebrew repo has uncommitted changes"
fi

# Verify on main branch
HOMEBREW_BRANCH=$(git branch --show-current)
if [[ "$HOMEBREW_BRANCH" != "main" ]]; then
    cd "$ORIGINAL_DIR"
    error "Homebrew repo must be on main branch (currently on: $HOMEBREW_BRANCH)"
fi

if $DRY_RUN; then
    dry_run "Would pull latest: git pull --ff-only origin main"
    dry_run "Would update Formula/sideways.rb:"
    dry_run "  - Set URL to /tags/$TAG.tar.gz"
    dry_run "  - Set sha256 to $SHA256"
    dry_run "Would commit: git commit -m \"Update sideways to $TAG\""
    dry_run "Would push: git push origin main"
else
    # Pull latest
    info "Pulling latest homebrew-sideways..."
    git pull --ff-only origin main

    # Update formula
    info "Updating formula..."
    sed -i '' "s|/tags/v[0-9.]*\.tar\.gz|/tags/$TAG.tar.gz|" Formula/sideways.rb
    sed -i '' "s|sha256 \"[^\"]*\"|sha256 \"$SHA256\"|" Formula/sideways.rb

    success "Updated Formula/sideways.rb"

    # --------------------------------------------------------------------------
    # Commit and Push Formula
    # --------------------------------------------------------------------------

    git add Formula/sideways.rb
    git commit -m "Update sideways to $TAG"
    success "Committed formula update"

    info "Pushing to origin..."
    git push origin main
    success "Pushed formula to origin"
fi

cd "$ORIGINAL_DIR"

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------

echo ""
if $DRY_RUN; then
    echo -e "${YELLOW}=========================================="
    echo "DRY RUN COMPLETE - No changes were made"
    echo -e "==========================================${NC}"
    echo ""
    echo "Would have done:"
    echo "  • Tag sideways $TAG"
    echo "  • Push tag to origin"
    echo "  • Calculate SHA256 from tarball"
    echo "  • Update homebrew-sideways formula"
    echo "  • Push formula to origin"
    echo ""
    echo "Run without --dry-run to perform the release."
else
    echo "=========================================="
    success "Release $TAG complete!"
    echo "=========================================="
    echo ""
    echo "Summary:"
    echo "  • Tagged sideways $TAG"
    echo "  • Pushed tag to origin"
    echo "  • SHA256: $SHA256"
    echo "  • Updated homebrew-sideways formula"
    echo "  • Pushed formula to origin"
    echo ""
    echo "Users can now run:"
    echo "  brew update && brew upgrade sideways"
fi
echo ""
