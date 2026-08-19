#!/bin/sh
# forge-detect.sh - Which forge CLI answers for a repository: GitHub (gh) or GitLab (glab).
#
# The skills under ~/.claude/skills/ are written against `gh`. On a GitLab remote they
# read ~/.claude/forge/gitlab.md and run the `glab` equivalent instead. This script is
# the one place that decides which of the two applies, from the host of the `origin`
# remote and the authentication state of the matching CLI:
#
#   1. host is github.com                          -> github  (gh must be authenticated)
#   2. `glab auth status --hostname <host>` passes  -> gitlab
#   3. `gh auth status -h <host>` passes            -> github  (GitHub Enterprise Server)
#   4. otherwise                                     -> exit 1 with the reason on stderr
#
# Usage: forge-detect.sh [PATH]
#
# Prints exactly one line, tab-separated:
#   <forge>  github | gitlab
#   <host>   host name of the origin remote
#   <path>   owner/repo on GitHub, group[/subgroup...]/project on GitLab
#
# PATH is any directory inside the repository; defaults to the current directory.
#
# The other scripts source this file instead of running it:
#   . "$(dirname "$0")/forge-detect.sh"
#   if forge_detect "$root"; then ... "$FORGE" "$FORGE_HOST" "$FORGE_PATH" ...; else ... "$FORGE_ERROR"; fi
# Sourcing defines the function only; nothing runs and no `set` option is changed.

# forge_detect [PATH] -> sets FORGE (github|gitlab), FORGE_CLI (gh|glab), FORGE_HOST,
# FORGE_PATH; returns 0. On failure sets FORGE_ERROR to a one-line reason and returns 1.
forge_detect() {
    FORGE=""; FORGE_CLI=""; FORGE_HOST=""; FORGE_PATH=""; FORGE_ERROR=""
    _fd_root=${1:-.}

    _fd_url=$(git -C "$_fd_root" remote get-url origin 2>/dev/null | tr -d '\r') || _fd_url=""
    if [ -z "$_fd_url" ]; then
        FORGE_ERROR="no origin remote"
        return 1
    fi

    # Split the URL into host and path. Forms handled:
    #   https://[user@]host[:port]/path[.git]   ssh://[user@]host[:port]/path[.git]
    #   [user@]host:path[.git]                   (scp-like)
    case "$_fd_url" in
        file://*|/*|[A-Za-z]:[/\\]*|.*)
            FORGE_ERROR="origin is a local path, not a forge remote: $_fd_url"
            return 1
            ;;
        *://*)
            _fd_rest=${_fd_url#*://}
            _fd_hostport=${_fd_rest%%/*}
            _fd_path=${_fd_rest#*/}
            ;;
        *:*)
            _fd_hostport=${_fd_url%%:*}
            _fd_path=${_fd_url#*:}
            ;;
        *)
            FORGE_ERROR="cannot parse origin URL: $_fd_url"
            return 1
            ;;
    esac
    _fd_hostport=${_fd_hostport##*@}
    FORGE_HOST=${_fd_hostport%%:*}
    _fd_path=${_fd_path#/}
    _fd_path=${_fd_path%/}
    _fd_path=${_fd_path%.git}
    FORGE_PATH=$_fd_path
    case "$FORGE_HOST" in
        "") FORGE_ERROR="cannot parse origin URL: $_fd_url"; return 1 ;;
    esac
    case "$FORGE_PATH" in
        */*) ;;
        *) FORGE_ERROR="origin URL has no owner/repo path: $_fd_url"; return 1 ;;
    esac

    if [ "$FORGE_HOST" = github.com ]; then
        if ! command -v gh >/dev/null 2>&1; then
            FORGE_ERROR="gh is not installed (origin is github.com)"
            return 1
        fi
        if ! gh auth status -h github.com >/dev/null 2>&1; then
            FORGE_ERROR="gh is not authenticated for github.com: run gh auth login"
            return 1
        fi
        FORGE=github; FORGE_CLI=gh
        return 0
    fi

    _fd_glab=""; _fd_gh=""
    if command -v glab >/dev/null 2>&1; then
        if glab auth status --hostname "$FORGE_HOST" >/dev/null 2>&1; then
            FORGE=gitlab; FORGE_CLI=glab
            return 0
        fi
        _fd_glab="glab: not authenticated for $FORGE_HOST"
    else
        _fd_glab="glab: not installed"
    fi
    if command -v gh >/dev/null 2>&1; then
        if gh auth status -h "$FORGE_HOST" >/dev/null 2>&1; then
            FORGE=github; FORGE_CLI=gh
            return 0
        fi
        _fd_gh="gh: not authenticated for $FORGE_HOST"
    else
        _fd_gh="gh: not installed"
    fi
    FORGE_ERROR="no authenticated CLI for $FORGE_HOST ($_fd_glab; $_fd_gh). For GitLab run: glab auth login --hostname $FORGE_HOST"
    return 1
}

# glab_tsv -> filter for the output of `glab ... --jq '... | @tsv'`. gh prints jq string
# results raw; should glab print them JSON-quoted instead ("a\tb"), this strips the quotes
# and turns the escapes back into tabs, so callers can parse either form.
glab_tsv() {
    sed -e 's/^"\(.*\)"$/\1/' -e "s/\\\\t/$(printf '\t')/g" -e 's/\\"/"/g' -e 's/\\\\/\\/g'
}

forge_detect_main() {
    set -eu
    case "${1:-}" in
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
    esac
    [ $# -le 1 ] || { echo "usage: forge-detect.sh [PATH]" >&2; exit 2; }
    if forge_detect "${1:-.}"; then
        printf '%s\t%s\t%s\n' "$FORGE" "$FORGE_HOST" "$FORGE_PATH"
        exit 0
    fi
    printf 'forge-detect: %s\n' "$FORGE_ERROR" >&2
    exit 1
}

case "$0" in
    *forge-detect.sh) forge_detect_main "$@" ;;
esac
