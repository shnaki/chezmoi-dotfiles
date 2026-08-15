#!/bin/sh
# worktree-sweep.sh - Remove leftover Claude Code agent worktrees and stale local branches.
#
# Agent worktrees created with `isolation: "worktree"` are only auto-removed when the
# agent leaves them unchanged. A worker that commits keeps both its worktree directory
# under .claude/worktrees/ and its `worktree-agent-*` base branch forever. Claude Code
# has no setting to clean these up, so this script does it.
#
# Only unambiguously safe targets are deleted. Anything holding work that is not on a
# remote is kept and reported with a reason.
#
# Usage: worktree-sweep.sh [--dry-run] [--recursive] [--no-fetch] [--force] [PATH...]

set -eu

DRY_RUN=0
RECURSIVE=0
FETCH=1
FORCE=0
# Skip worktrees touched within this many minutes; a background agent may still be running.
RECENT_MINUTES=60

usage() {
    cat <<'EOF'
Usage: worktree-sweep.sh [options] [PATH...]

Removes leftover agent worktrees under <repo>/.claude/worktrees/ and local branches
that are already merged into the base branch or whose upstream is gone.

Options:
  --dry-run     Report what would be removed without changing anything.
  --recursive   Treat each PATH as a tree to scan for git repositories.
  --no-fetch    Skip `git fetch --prune`. Upstream-gone detection becomes unreliable.
  --force       Ignore the guard that skips worktrees modified in the last 60 minutes.
  -h, --help    Show this help.

PATH defaults to the current directory. There is no built-in root; pass one explicitly,
for example: worktree-sweep.sh --recursive ~/src
EOF
}

log() { printf '%s\n' "$*"; }

# --- argument parsing -------------------------------------------------------

PATHS=""
add_path() { PATHS="$PATHS$1
"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --recursive) RECURSIVE=1 ;;
        --no-fetch) FETCH=0 ;;
        --force) FORCE=1 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) log "unknown option: $1" >&2; usage >&2; exit 2 ;;
        *) add_path "$1" ;;
    esac
    shift
done
while [ $# -gt 0 ]; do
    add_path "$1"
    shift
done
[ -n "$PATHS" ] || PATHS=".
"

# Directory we were invoked from, so we never sweep out from under the caller.
# Only its tail is ever compared: Git Bash resolves one directory to several
# absolute forms (/c/Users/.../Temp/x and /tmp/x are the same place), so comparing
# whole paths is not reliable on Windows.
INVOKED_FROM=$(pwd -P)

TMPDIR_SWEEP=$(mktemp -d)
trap 'rm -rf "$TMPDIR_SWEEP"' EXIT INT TERM
REPOS="$TMPDIR_SWEEP/repos"
BRANCHES="$TMPDIR_SWEEP/branches"

TOTAL_WT=0
TOTAL_BR=0
TOTAL_KEPT=0

# --- helpers ----------------------------------------------------------------

keep() {
    TOTAL_KEPT=$((TOTAL_KEPT + 1))
    log "    keep    $1 ($2)"
}

# Ref to compare branches against: origin/<default> when available, since a local
# base branch can be behind what has actually been merged.
base_ref() {
    _b=$(git -C "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
    if [ -z "$_b" ]; then
        for _c in main master; do
            if git -C "$1" show-ref --verify --quiet "refs/remotes/origin/$_c"; then
                _b="origin/$_c"
                break
            fi
        done
    fi
    if [ -z "$_b" ]; then
        for _c in main master; do
            if git -C "$1" show-ref --verify --quiet "refs/heads/$_c"; then
                _b="$_c"
                break
            fi
        done
    fi
    printf '%s' "$_b"
}

# --- worktree handling ------------------------------------------------------

sweep_worktrees() {
    _root=$1
    _wtdir="$_root/.claude/worktrees"
    [ -d "$_wtdir" ] || return 0

    # Basenames of registered worktrees. The directory is flat, so comparing basenames
    # is unambiguous and sidesteps the C:/ vs /c/ path mismatch on Windows.
    _registered=$(git -C "$_root" worktree list --porcelain 2>/dev/null |
        sed -n 's|^worktree .*/||p')

    for _wt in "$_wtdir"/*; do
        [ -d "$_wt" ] || continue
        _name=${_wt##*/}

        case "$INVOKED_FROM" in
            *"/.claude/worktrees/$_name"|*"/.claude/worktrees/$_name"/*)
                keep "$_name" "the current session is inside it"
                continue
                ;;
        esac

        if [ "$FORCE" -eq 0 ] &&
           [ -n "$(find "$_wtdir" -maxdepth 1 -name "$_name" -mmin "-$RECENT_MINUTES" 2>/dev/null)" ]; then
            keep "$_name" "modified within $RECENT_MINUTES minutes, an agent may still be running"
            continue
        fi

        if printf '%s\n' "$_registered" | grep -qx -- "$_name"; then
            if [ -n "$(git -C "$_wt" status --porcelain 2>/dev/null)" ]; then
                keep "$_name" "has uncommitted changes"
                continue
            fi
            if [ -z "$(git -C "$_wt" branch -r --contains HEAD 2>/dev/null)" ]; then
                keep "$_name" "HEAD is not on any remote branch"
                continue
            fi
            if [ "$DRY_RUN" -eq 1 ]; then
                log "    remove  $_name (clean, work is on a remote)"
            elif git -C "$_root" worktree remove "$_wt" >/dev/null 2>&1; then
                log "    removed $_name (clean, work is on a remote)"
            else
                keep "$_name" "git worktree remove failed"
                continue
            fi
        else
            # Orphaned: git no longer tracks it, so neither `worktree remove` nor
            # `worktree prune` can help. It is a plain directory now.
            if [ "$DRY_RUN" -eq 1 ]; then
                log "    remove  $_name (orphaned directory)"
            elif rm -rf "$_wt" 2>/dev/null; then
                log "    removed $_name (orphaned directory)"
            else
                keep "$_name" "orphaned but could not be deleted, files may be locked"
                continue
            fi
        fi
        TOTAL_WT=$((TOTAL_WT + 1))
    done
}

# --- branch handling --------------------------------------------------------

sweep_branches() {
    _root=$1
    _base=$2

    if [ -z "$_base" ]; then
        keep "(all branches)" "base branch could not be determined"
        return 0
    fi

    _current=$(git -C "$_root" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    _checked_out=$(git -C "$_root" worktree list --porcelain 2>/dev/null |
        sed -n 's|^branch refs/heads/||p')
    _merged=$(git -C "$_root" branch --format='%(refname:short)' --merged "$_base" 2>/dev/null || true)

    git -C "$_root" for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads \
        > "$BRANCHES" 2>/dev/null || : > "$BRANCHES"

    while IFS= read -r _line; do
        _br=${_line%% *}
        [ -n "$_br" ] || continue
        _track=${_line#"$_br"}

        [ "$_br" = "$_current" ] && continue
        [ "$_br" = "$_base" ] && continue
        [ "$_br" = "${_base#origin/}" ] && continue
        case "$_br" in
            backup/*) continue ;;
        esac
        printf '%s\n' "$_checked_out" | grep -qx -- "$_br" && continue

        _is_merged=0
        printf '%s\n' "$_merged" | grep -qx -- "$_br" && _is_merged=1
        case "$_track" in
            *gone*) _is_gone=1 ;;
            *) _is_gone=0 ;;
        esac
        [ "$_is_merged" -eq 0 ] && [ "$_is_gone" -eq 0 ] && continue

        if [ "$_is_merged" -eq 1 ]; then
            if [ "$DRY_RUN" -eq 1 ]; then
                log "    delete  $_br (merged into $_base)"
            elif git -C "$_root" branch -d "$_br" >/dev/null 2>&1; then
                log "    deleted $_br (merged into $_base)"
            else
                keep "$_br" "git refused to delete it"
                continue
            fi
            TOTAL_BR=$((TOTAL_BR + 1))
            continue
        fi

        # Upstream is gone but the branch is not merged: most likely a squash-merged
        # PR. Only force-delete when GitHub confirms the PR was actually merged.
        if ! command -v gh >/dev/null 2>&1; then
            keep "$_br" "upstream gone but unmerged; gh unavailable to confirm"
            continue
        fi
        _pr=$(cd "$_root" && gh pr list --head "$_br" --state merged --limit 1 \
                --json number --jq '.[0].number' 2>/dev/null || true)
        if [ -z "$_pr" ] || [ "$_pr" = "null" ]; then
            keep "$_br" "upstream gone but unmerged, and no merged PR found"
            continue
        fi
        if [ "$DRY_RUN" -eq 1 ]; then
            log "    delete  $_br (squash-merged as PR #$_pr)"
        elif git -C "$_root" branch -D "$_br" >/dev/null 2>&1; then
            log "    deleted $_br (squash-merged as PR #$_pr)"
        else
            keep "$_br" "git refused to delete it"
            continue
        fi
        TOTAL_BR=$((TOTAL_BR + 1))
    done < "$BRANCHES"
}

# --- per-repository driver --------------------------------------------------

sweep_repo() {
    _root=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null || true)
    [ -n "$_root" ] || return 0
    # Do not descend into a repository through one of its own agent worktrees.
    case "$_root" in
        */.claude/worktrees/*) return 0 ;;
    esac

    log "$_root"

    if [ "$FETCH" -eq 1 ]; then
        git -C "$_root" fetch --prune --quiet 2>/dev/null ||
            log "    note    fetch failed; upstream-gone detection may be stale"
    fi
    if [ "$DRY_RUN" -eq 0 ]; then
        git -C "$_root" worktree prune 2>/dev/null || true
    fi

    sweep_worktrees "$_root"
    sweep_branches "$_root" "$(base_ref "$_root")"
}

# --- main -------------------------------------------------------------------

printf '%s' "$PATHS" | while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    if [ ! -d "$_p" ]; then
        log "not a directory: $_p" >&2
        continue
    fi
    if [ "$RECURSIVE" -eq 1 ]; then
        find "$_p" -name .git -prune 2>/dev/null | sed 's|/\.git$||'
    else
        printf '%s\n' "$_p"
    fi
done > "$REPOS"

while IFS= read -r _repo; do
    [ -n "$_repo" ] || continue
    sweep_repo "$_repo"
done < "$REPOS"

if [ "$DRY_RUN" -eq 1 ]; then
    log "dry run: would remove $TOTAL_WT worktree(s), delete $TOTAL_BR branch(es), keep $TOTAL_KEPT item(s)"
else
    log "removed $TOTAL_WT worktree(s), deleted $TOTAL_BR branch(es), kept $TOTAL_KEPT item(s)"
fi
