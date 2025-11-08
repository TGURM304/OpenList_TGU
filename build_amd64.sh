#!/usr/bin/env bash
set -euo pipefail

# Simple build script that injects build metadata into the Go binary via -ldflags.
# Usage:
#   ./build.sh
#   ./build.sh -o ./bin/openlist
#   ./build.sh --help

print_usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -o <output>    Specify output binary path (default: ./openlist)
  -h, --help     Show this help message
EOF
}

# defaults
output="./openlist"

# parse args (very simple)
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      shift
      output="$1"
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      print_usage
      exit 1
      ;;
  esac
done

# Check required tools
command -v go >/dev/null 2>&1 || { echo "Error: 'go' not found in PATH. Install Go and retry."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Warning: 'curl' not found. webVersion will default to 0.0.0."; }
# git is optional (we can continue without it)
if ! command -v git >/dev/null 2>&1; then
  echo "Warning: 'git' not found. Git-related fields will use safe defaults."
fi

appName="openlist"
builtAt="$(date +'%F %T %z')"

# Go version (safe even if go isn't present because we already checked)
goVersion="$(go version | sed 's/go version //')"

# Git metadata (safe fallbacks if no git repo or git not installed)
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir > /dev/null 2>&1; then
  # inside a git repo
  gitAuthor="$(git show -s --format='format:%aN <%ae>' HEAD 2>/dev/null || echo "unknown <unknown>")"
  gitCommit="$(git log --pretty=format:'%h' -1 2>/dev/null || echo "unknown")"
  version="$(git describe --long --tags --dirty --always 2>/dev/null || echo "v0.0.0")"
else
  gitAuthor="unknown <unknown>"
  gitCommit="unknown"
  version="v0.0.0"
fi

# Fetch webVersion from GitHub releases (fallback to 0.0.0 if curl fails)
webVersion="0.0.0"
if command -v curl >/dev/null 2>&1; then
  set +e
  resp="$(curl -s --max-time 5 "https://api.github.com/repos/OpenListTeam/OpenList-Frontend/releases/latest" -L 2>/dev/null || true)"
  set -e
  if [[ -n "$resp" ]]; then
    tag="$(echo "$resp" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)"
    if [[ -n "$tag" ]]; then
      # strip leading v if present
      webVersion="${tag#v}"
    fi
  fi
fi

# Build ldflags string. Use double quotes around values so spaces are preserved.
ldflags="-w -s \
-X 'github.com/OpenListTeam/OpenList/v4/internal/conf.BuiltAt=${builtAt}' \
-X 'github.com/OpenListTeam/OpenList/v4/internal/conf.GoVersion=${goVersion}' \
-X 'github.com/OpenListTeam/OpenList/v4/internal/conf.GitAuthor=${gitAuthor}' \
-X 'github.com/OpenListTeam/OpenList/v4/internal/conf.GitCommit=${gitCommit}' \
-X 'github.com/OpenListTeam/OpenList/v4/internal/conf.Version=${version}' \
-X 'github.com/OpenListTeam/OpenList/v4/internal/conf.WebVersion=${webVersion}'"

echo "Building ${appName} -> ${output}"
echo "  BuiltAt:   ${builtAt}"
echo "  GoVersion: ${goVersion}"
echo "  GitAuthor: ${gitAuthor}"
echo "  GitCommit: ${gitCommit}"
echo "  Version:   ${version}"
echo "  WebVersion:${webVersion}"
echo

# Run the build
# Use eval to ensure the quoting in ldflags is preserved correctly when passed to go build.
eval "go build -ldflags=\"$ldflags\" -o \"$output\" ."

echo "Build finished: $output"
