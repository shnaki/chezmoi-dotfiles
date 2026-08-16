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
# Three things make removal fail on Windows, and each is handled here:
#   1. A `git worktree lock` left behind by a claude session that never exited cleanly.
#      The lock reason carries the pid, so a lock whose pid is gone is unlocked and the
#      worktree swept; a lock whose pid is alive is kept.
#   2. `git worktree remove` failing with "Filename too long" on deep node_modules
#      paths. Removal falls back to deleting the directory, then `worktree prune`.
#   3. "Device or resource busy": another process has the directory as its working
#      directory. Nothing here can fix that, so it is reported as such.
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
LOCKS="$TMPDIR_SWEEP/locks"
: > "$LOCKS"

# `ps -W` is a Git Bash extension that lists Windows processes; column 4 is the Windows
# pid, which is the number a Node process reports as `process.pid`. Elsewhere the usual
# `kill -0` works.
PS_W=0
if ps -W >/dev/null 2>&1; then
    PS_W=1
fi

TOTAL_WT=0
TOTAL_BR=0
TOTAL_KEPT=0

# --- helpers ----------------------------------------------------------------

keep() {
    TOTAL_KEPT=$((TOTAL_KEPT + 1))
    log "    keep    $1 ($2)"
}

pid_alive() {
    if [ "$PS_W" -eq 1 ]; then
        ps -W 2>/dev/null | awk -v p="$1" 'NR > 1 && $4 == p { found = 1 } END { exit !found }'
    else
        kill -0 "$1" 2>/dev/null
    fi
}

is_locked() {
    awk -F'\t' -v n="$1" '$1 == n { found = 1 } END { exit !found }' "$LOCKS"
}

lock_reason() {
    awk -F'\t' -v n="$1" '$1 == n { print substr($0, length(n) + 2); exit }' "$LOCKS"
}

# Turn the collected stderr of a failed removal into a reason the user can act on.
removal_failure() {
    case "$1" in
        *"Device or resource busy"*|*"Text file busy"*|*"Permission denied"*|*"being used by another process"*)
            printf '%s' "in use by another process; close the shell or session sitting in it and re-run"
            ;;
        *"Filename too long"*|*"File name too long"*)
            printf '%s' "paths too long to delete; set core.longpaths=true and re-run"
            ;;
        *)
            _last=$(printf '%s\n' "$1" | grep -v '^[[:space:]]*$' | tail -n 1)
            printf 'could not be removed: %s' "${_last:-unknown error}"
            ;;
    esac
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

    # One porcelain read feeds both lookups below.
    _meta=$(git -C "$_root" worktree list --porcelain 2>/dev/null || true)

    # Basenames of registered worktrees. The directory is flat, so comparing basenames
    # is unambiguous and sidesteps the C:/ vs /c/ path mismatch on Windows.
    _registered=$(printf '%s\n' "$_meta" | sed -n 's|^worktree .*/||p')

    # "<basename><TAB><lock reason>" for every locked worktree. Claude Code locks the
    # worktree a session is working in, and the lock outlives a session that crashed.
    printf '%s\n' "$_meta" | awk '
        /^worktree /   { _n = $0; sub(/^worktree .*\//, "", _n); next }
        /^locked($| )/ { _r = substr($0, 7); sub(/^ /, "", _r); print _n "\t" _r }
    ' > "$LOCKS"

    for _wt in "$_wtdir"/*; do
        [ -d "$_wt" ] || continue
        _name=${_wt##*/}

        case "$INVOKED_FROM" in
            *"/.claude/worktrees/$_name"|*"/.claude/worktrees/$_name"/*)
                keep "$_name" "the current session is inside it"
                continue
                ;;
        esac

        _is_registered=0
        if printf '%s\n' "$_registered" | grep -qx -- "$_name"; then
            _is_registered=1
        fi

        # A lock blocks `git worktree remove` outright, so resolve it first.
        _stale_lock=0
        if [ "$_is_registered" -eq 1 ] && is_locked "$_name"; then
            _reason=$(lock_reason "$_name")
            _pid=$(printf '%s' "$_reason" | sed -n 's/.*(pid \([0-9][0-9]*\)).*/\1/p')
            if [ -z "$_pid" ]; then
                keep "$_name" "locked: ${_reason:-no reason given}"
                continue
            fi
            if pid_alive "$_pid"; then
                keep "$_name" "locked by a running claude session (pid $_pid)"
                continue
            fi
            if [ "$DRY_RUN" -eq 1 ]; then
                log "    unlock  $_name (stale lock, pid $_pid is gone)"
            elif git -C "$_root" worktree unlock "$_wt" >/dev/null 2>&1; then
                log "    unlock  $_name (stale lock, pid $_pid is gone)"
            else
                keep "$_name" "stale lock (pid $_pid is gone) but git worktree unlock failed"
                continue
            fi
            _stale_lock=1
        fi

        # A stale lock proves the session that owned the worktree is gone, so the
        # "may still be running" guard does not apply to it.
        if [ "$_stale_lock" -eq 0 ] && [ "$FORCE" -eq 0 ] &&
           [ -n "$(find "$_wtdir" -maxdepth 1 -name "$_name" -mmin "-$RECENT_MINUTES" 2>/dev/null)" ]; then
            keep "$_name" "modified within $RECENT_MINUTES minutes, an agent may still be running"
            continue
        fi

        if [ "$_is_registered" -eq 1 ]; then
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
            elif _err=$(git -C "$_root" worktree remove "$_wt" 2>&1); then
                log "    removed $_name (clean, work is on a remote)"
            else
                # `git worktree remove` gives up when a path inside the worktree is too
                # long for Windows (node_modules), often after it has already dropped
                # its own admin entry. Deleting the directory finishes the job.
                _err="$_err
$(rm -rf "$_wt" 2>&1 || true)"
                if [ -d "$_wt" ]; then
                    keep "$_name" "$(removal_failure "$_err")"
                    continue
                fi
                git -C "$_root" worktree prune >/dev/null 2>&1 || true
                log "    removed $_name (clean, work is on a remote; deleted the directory directly)"
            fi
        else
            # Orphaned: git no longer tracks it, so neither `worktree remove` nor
            # `worktree prune` can help. It is a plain directory now.
            if [ "$DRY_RUN" -eq 1 ]; then
                log "    remove  $_name (orphaned directory)"
            else
                _err=$(rm -rf "$_wt" 2>&1 || true)
                if [ -d "$_wt" ]; then
                    keep "$_name" "orphaned, $(removal_failure "$_err")"
                    continue
                fi
                log "    removed $_name (orphaned directory)"
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
