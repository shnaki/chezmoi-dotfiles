#!/bin/sh
# work-status.sh - Report what is in flight in a repository and what to run next.
#
# Long-running skills (ship-issues above all) leave their state in four places: open
# Pull Requests on GitHub, agent worktrees under .claude/worktrees/, local branches, and
# ship-issues run files under ~/.claude/ship-issues/. This script reads all four, joins
# them by branch name, and prints one row per unit of work with a `next` column naming
# the skill to invoke (/pr-fix, /pr-review, /pr-land, /ship-issues --resume, /pr-ready,
# /worktree-sweep) or `wait`.
#
# Read-only. The only side effect is `git fetch --prune`; --no-fetch disables it. Nothing
# is merged, swept, or written, and none of the suggested commands are run.
#
# Agent liveness is a heuristic. A worktree lock whose pid is alive is the only hard
# signal; a recently modified worktree, an existing branch, an open PR, and a state-file
# entry are hints. Background Agent tasks are visible only to the session that started
# them, so a run in another session cannot be seen from here.
#
# The `next` decision table (first match wins):
#    1 orphaned worktree directory                          -> /worktree-sweep
#    2 worktree lock, pid alive                              -> wait
#    3 worktree lock without a pid                           -> wait
#    4 PR draft                                              -> wait
#    5 PR mergeable=CONFLICTING or mergeStateStatus=DIRTY    -> /pr-fix N
#    6 PR checks failing                                     -> /pr-fix N
#    7 PR reviewDecision=CHANGES_REQUESTED                   -> /pr-fix N
#    8 PR checks pending                                     -> wait
#    9 PR mergeable=UNKNOWN                                  -> wait
#   10 PR APPROVED and checks green or none                  -> /pr-land N
#   11 PR reviewDecision=REVIEW_REQUIRED                     -> /pr-review N
#   12 PR not reviewed and checks green or none              -> /pr-review N
#   13 PR mergeStateStatus=BLOCKED                           -> wait
#   14 no PR, worktree dirty, touched recently               -> wait
#   15 no PR, worktree dirty, stale, in a ship-issues run    -> /ship-issues --resume
#   16 no PR, worktree dirty, stale                          -> /pr-ready (in <wt>)
#   17 no PR, commits ahead of base, in a ship-issues run    -> /ship-issues --resume
#   18 no PR, commits ahead of base                          -> /pr-ready
#   19 no PR, clean worktree, nothing ahead, recent          -> wait
#   20 no PR, clean worktree, nothing ahead, stale           -> /worktree-sweep
#   21 branch merged into base or upstream gone              -> /worktree-sweep
#   22 state-file Issue with a merged PR                     -> - (done)
#   23 state-file Issue with no signal anywhere              -> /ship-issues --resume
#
# Output is tab-separated, one record per line, the record type in column 1. A `# ` line
# names the columns before the first record of each type:
#   repo     root  repository  base  invoked  fetch  gh
#   row      key  issue  pr  pr_state  checks  review  branch  ahead/behind  worktree  agent  state  next  reason
#   state    file  started  options  issues  repository  resolved/total
#   srow     file  <raw table row copied from the state file>
#   note     <free text>
#   summary  <counts>
#
# Usage: work-status.sh [--no-fetch] [PATH]

set -eu

FETCH=1
TARGET=""
# A worktree touched within this many minutes may still have an agent in it.
RECENT_MINUTES=60
STATE_DIR="${HOME}/.claude/ship-issues"
PR_LIMIT=200

usage() {
    cat <<'EOF'
Usage: work-status.sh [options] [PATH]

Lists what is in flight in the repository containing PATH (default: the current
directory): open Pull Requests, agent worktrees and local branches, and unfinished
ship-issues runs, each with the next command to run. Read-only.

Options:
  --no-fetch    Skip `git fetch --prune`. ahead/behind and upstream-gone become stale.
  -h, --help    Show this help.
EOF
}

log() { printf '%s\n' "$*"; }
TAB=$(printf '\t')

# --- argument parsing -------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --no-fetch) FETCH=0 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) log "unknown option: $1" >&2; usage >&2; exit 2 ;;
        *) TARGET=$1 ;;
    esac
    shift
done
[ $# -eq 0 ] || TARGET=$1
[ -n "$TARGET" ] || TARGET=.
[ -d "$TARGET" ] || { log "not a directory: $TARGET" >&2; exit 1; }

# --- repository --------------------------------------------------------------

TOPLEVEL=$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null) ||
    { log "not a git repository: $TARGET" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM
PRS="$TMP/prs"          # number head draft mergeable mergestate review checks issues updated url
MERGED="$TMP/merged"    # number head issues
WTS="$TMP/wts"          # name path branch dirty recent agent orphan
BRS="$TMP/brs"          # branch ahead behind merged gone
STATES="$TMP/states"    # file stamp started options issues repository
SROWS="$TMP/srows"      # file line
ROWS="$TMP/rows"
NOTES="$TMP/notes"
CLAIMED_BR="$TMP/claimed_br"
CLAIMED_ISSUE="$TMP/claimed_issue"
for _f in "$PRS" "$MERGED" "$WTS" "$BRS" "$STATES" "$SROWS" "$ROWS" "$NOTES" "$CLAIMED_BR" "$CLAIMED_ISSUE"; do
    : > "$_f"
done

note() { printf '%s\n' "$*" >> "$NOTES"; }

# The main worktree is the first entry of `git worktree list`; TOPLEVEL may be a linked
# worktree when invoked from inside one.
PORCELAIN=$(git -C "$TOPLEVEL" worktree list --porcelain 2>/dev/null || true)
ROOT=$(printf '%s\n' "$PORCELAIN" | sed -n 's/^worktree //p' | head -n 1)
[ -n "$ROOT" ] || ROOT=$TOPLEVEL

INVOKED=main
INVOKED_WT=""
if [ "$TOPLEVEL" != "$ROOT" ]; then
    INVOKED_WT=${TOPLEVEL##*/}
    INVOKED="worktree:$INVOKED_WT"
fi

# `ps -W` is a Git Bash extension that lists Windows processes; column 4 is the Windows
# pid, which is the number a Node process reports as `process.pid`. Elsewhere `kill -0`.
PS_W=0
if ps -W >/dev/null 2>&1; then
    PS_W=1
fi

pid_alive() {
    if [ "$PS_W" -eq 1 ]; then
        ps -W 2>/dev/null | awk -v p="$1" 'NR > 1 && $4 == p { found = 1 } END { exit !found }'
    else
        kill -0 "$1" 2>/dev/null
    fi
}

# Ref to compare branches against: origin/<default> when available.
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

# --- gh and remote -----------------------------------------------------------

GH_STATE=ok
NWO=""
HAS_REMOTE=0
if git -C "$ROOT" remote get-url origin >/dev/null 2>&1; then
    HAS_REMOTE=1
fi

if ! command -v gh >/dev/null 2>&1; then
    GH_STATE=missing
elif ! gh auth status >/dev/null 2>&1; then
    GH_STATE=unauth
elif [ "$HAS_REMOTE" -eq 0 ]; then
    GH_STATE=no-remote
else
    NWO=$(cd "$ROOT" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null | tr -d '\r') || NWO=""
    [ -n "$NWO" ] || GH_STATE=failed
fi

if [ -z "$NWO" ] && [ "$HAS_REMOTE" -eq 1 ]; then
    NWO=$(git -C "$ROOT" remote get-url origin 2>/dev/null |
        sed -e 's#[/:]*$##' -e 's#\.git$##' -e 's#.*[:/]\([^/]*/[^/]*\)$#\1#')
    case "$NWO" in
        */*) ;;
        *) NWO="" ;;
    esac
fi
REPO_NAME=${NWO##*/}
[ -n "$REPO_NAME" ] || REPO_NAME=${ROOT##*/}

FETCH_STATE=skipped
if [ "$FETCH" -eq 1 ] && [ "$HAS_REMOTE" -eq 1 ]; then
    if git -C "$ROOT" fetch --prune --quiet 2>/dev/null; then
        FETCH_STATE=ok
    else
        FETCH_STATE=failed
    fi
fi

BASE=$(base_ref "$ROOT")

# The local counterpart of origin/<base>, when it exists and is a different ref.
LOCAL_BASE=""
case "$BASE" in
    origin/*)
        if git -C "$ROOT" show-ref --verify --quiet "refs/heads/${BASE#origin/}"; then
            LOCAL_BASE=${BASE#origin/}
            _unpushed=$(git -C "$ROOT" rev-list --count "$BASE..$LOCAL_BASE" 2>/dev/null || printf 0)
            if [ "$_unpushed" -gt 0 ]; then
                note "$LOCAL_BASE is $_unpushed commit(s) ahead of $BASE (unpushed)"
            fi
        fi
        ;;
esac

case "$GH_STATE" in
    ok) ;;
    missing) note "gh is not installed: PR state and merged-PR lookup skipped; GitHub columns show ?" ;;
    unauth) note "gh is not authenticated: PR state and merged-PR lookup skipped; GitHub columns show ?" ;;
    no-remote) note "no origin remote: PR state and merged-PR lookup skipped; GitHub columns show ?" ;;
    failed) note "gh repo view failed: PR state and merged-PR lookup skipped; GitHub columns show ?" ;;
esac

# --- data: open Pull Requests -----------------------------------------------

# checks: CheckRun entries carry status/conclusion, StatusContext entries carry state.
PR_JQ='.[] | [
  .number, .headRefName,
  (if .isDraft then 1 else 0 end),
  (.mergeable // "UNKNOWN"), (.mergeStateStatus // "UNKNOWN"),
  ((.reviewDecision // "") | if . == "" then "NONE" else . end),
  ((.statusCheckRollup // [])
     | if length == 0 then "none"
       elif any(.[]; ((.conclusion // .state // "") | IN("FAILURE","ERROR","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE"))) then "fail"
       elif any(.[]; ((.status // "") | IN("QUEUED","IN_PROGRESS","PENDING","WAITING","REQUESTED"))
                     or ((.state // "") | IN("PENDING","EXPECTED"))) then "pending"
       else "pass" end),
  ((.closingIssuesReferences // []) | map(.number | tostring) | join(",") | if . == "" then "-" else . end),
  .updatedAt, .url ] | @tsv'

if [ "$GH_STATE" = ok ]; then
    if _out=$(cd "$ROOT" && gh pr list --state open --limit "$PR_LIMIT" \
            --json number,headRefName,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,closingIssuesReferences,updatedAt,url \
            --jq "$PR_JQ" 2>/dev/null); then
        printf '%s\n' "$_out" | tr -d '\r' | grep -v '^$' > "$PRS" || true
        if [ "$(wc -l < "$PRS" | tr -d " ")" -ge "$PR_LIMIT" ]; then
            note "open PR list capped at $PR_LIMIT; some PRs may be missing"
        fi
    else
        GH_STATE=failed
        note "gh pr list failed: PR state unknown; GitHub columns show ?"
    fi
fi

# --- data: worktrees ---------------------------------------------------------

# name path branch lock  for every linked worktree (the main worktree is skipped).
printf '%s\n' "$PORCELAIN" | awk -F'\t' '
    function emit() { if (idx > 1 && path != "") { name = path; sub(/.*\//, "", name);
                      print name "\t" path "\t" branch "\t" lock } }
    /^worktree /   { emit(); path = substr($0, 10); idx++; branch = ""; lock = ""; next }
    /^branch /     { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch); next }
    /^detached$/   { branch = "(detached)"; next }
    /^locked/      { lock = substr($0, 7); sub(/^ /, "", lock); if (lock == "") lock = "(no reason given)"; next }
    END            { emit() }
' > "$TMP/wt_raw"

# recent_label PATH GITDIR -> "<Nm" for the smallest rung that PATH, or HEAD / the HEAD
# reflog in its git admin dir, was modified within; nothing when older than the last
# rung. The index is deliberately not consulted: any `git status` (this script's own
# included) rewrites it, so it would report every worktree as recent.
recent_label() {
    for _n in 5 15 "$RECENT_MINUTES"; do
        if [ -n "$(find "$(dirname "$1")" -maxdepth 1 -name "$(basename "$1")" -mmin "-$_n" 2>/dev/null)" ]; then
            printf '<%sm' "$_n"; return
        fi
        if [ -n "$2" ] && [ -n "$(find "$2" "$2/logs" -maxdepth 1 -name HEAD -mmin "-$_n" 2>/dev/null)" ]; then
            printf '<%sm' "$_n"; return
        fi
    done
}

while IFS="$TAB" read -r _name _path _branch _lock; do
    [ -n "$_name" ] || continue
    _gitdir=$(git -C "$_path" rev-parse --absolute-git-dir 2>/dev/null || true)
    _recent=$(recent_label "$_path" "$_gitdir")
    _dirty=0
    if [ -n "$(git -C "$_path" status --porcelain 2>/dev/null)" ]; then
        _dirty=1
    fi
    if [ -n "$_lock" ]; then
        _pid=$(printf '%s' "$_lock" | sed -n 's/.*(pid \([0-9][0-9]*\)).*/\1/p')
        if [ -z "$_pid" ]; then
            _agent="locked:$_lock"
        elif pid_alive "$_pid"; then
            _agent="alive:$_pid"
        else
            _agent="dead-lock:$_pid"
        fi
    elif [ -n "$_recent" ]; then
        _agent="recent:$_recent"
    else
        _agent=stale
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t0\n' "$_name" "$_path" "$_branch" "$_dirty" "${_recent:-0}" "$_agent" >> "$WTS"
done < "$TMP/wt_raw"

# Directories under .claude/worktrees/ that git no longer tracks.
WTDIR="$ROOT/.claude/worktrees"
if [ -d "$WTDIR" ]; then
    for _wt in "$WTDIR"/*; do
        [ -d "$_wt" ] || continue
        _name=${_wt##*/}
        if ! awk -F'\t' -v n="$_name" '$1 == n { found = 1 } END { exit !found }' "$WTS"; then
            printf '%s\t%s\t-\t0\t0\torphan\t1\n' "$_name" "$_wt" >> "$WTS"
        fi
    done
fi

# --- data: local branches ----------------------------------------------------

if [ -n "$BASE" ]; then
    _merged_list=$(git -C "$ROOT" branch --format='%(refname:short)' --merged "$BASE" 2>/dev/null || true)
    git -C "$ROOT" for-each-ref --format='%(refname:short)%09%(upstream:track)' refs/heads 2>/dev/null |
    while IFS="$TAB" read -r _br _track; do
        [ -n "$_br" ] || continue
        [ "$_br" = "$BASE" ] && continue
        [ "$_br" = "${BASE#origin/}" ] && continue
        case "$_br" in
            backup/*) continue ;;
        esac
        _behind=$(git -C "$ROOT" rev-list --count "$_br..$BASE" 2>/dev/null || printf 0)
        # Commits the branch has that neither origin/<base> nor the local <base> has, so
        # branches cut from an unpushed local base do not look like unpublished work.
        _ahead=$(git -C "$ROOT" rev-list --count "$_br" --not "$BASE" $LOCAL_BASE 2>/dev/null || printf 0)
        _is_merged=0
        printf '%s\n' "$_merged_list" | grep -qx -- "$_br" && _is_merged=1
        _is_gone=0
        case "$_track" in *gone*) _is_gone=1 ;; esac
        printf '%s\t%s\t%s\t%s\t%s\n' "$_br" "$_ahead" "$_behind" "$_is_merged" "$_is_gone"
    done > "$BRS"
else
    note "base branch could not be determined; ahead/behind and merged detection skipped"
fi

# --- data: ship-issues state files ------------------------------------------

state_header() {  # state_header FILE KEY -> value of "- KEY: value"
    sed -n "s/^- *$2: *//p" "$1" | head -n 1 | tr -d '\r'
}

OTHER_STATES=""
if [ -d "$STATE_DIR" ]; then
    for _f in $(ls -1r "$STATE_DIR"/*.md 2>/dev/null); do
        [ -f "$_f" ] || continue
        if grep -Eq '^\**DONE\**([[:space:]]|$)' "$_f"; then
            continue
        fi
        _fname=${_f##*/}
        _repo=$(state_header "$_f" repository)
        _mine=0
        case "$_fname" in
            "$REPO_NAME"-*) _mine=1 ;;
        esac
        if [ "$_mine" -eq 1 ] && [ -n "$_repo" ] && [ -n "$NWO" ] && [ "$_repo" != "$NWO" ]; then
            _mine=0
        fi
        if [ "$_mine" -eq 0 ]; then
            OTHER_STATES="$OTHER_STATES $_fname"
            continue
        fi
        _stamp=${_fname#"$REPO_NAME"-}
        _stamp=${_stamp%.md}
        _started=$(state_header "$_f" started)
        _options=$(state_header "$_f" options)
        _issues=$(state_header "$_f" "requested issues" | grep -o '[0-9][0-9]*' | tr '\n' ' ' | sed 's/ $//')
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$_fname" "$_stamp" "${_started:--}" "${_options:--}" "${_issues:--}" "${_repo:--}" >> "$STATES"
        grep -E '^\| *#?[0-9]+ *\|' "$_f" | tr -d '\r' | while IFS= read -r _line; do
            printf '%s\t%s\n' "$_fname" "$_line"
        done >> "$SROWS"
    done
fi

if [ -n "$OTHER_STATES" ]; then
    note "unfinished ship-issues run(s) of other repositories:$OTHER_STATES"
fi
_nstates=$(wc -l < "$STATES" | tr -d " ")
if [ "$_nstates" -gt 1 ]; then
    note "$_nstates unfinished ship-issues runs for this repository; /ship-issues --resume picks the newest ($(head -n 1 "$STATES" | cut -f1))"
fi

# Merged PRs are only needed to tell whether a state-file Issue is actually finished.
if [ "$_nstates" -gt 0 ] && [ "$GH_STATE" = ok ]; then
    _out=$(cd "$ROOT" && gh pr list --state merged --limit 100 --json number,headRefName,closingIssuesReferences \
        --jq '.[] | [.number, .headRefName, ((.closingIssuesReferences // []) | map(.number | tostring) | join(",") | if . == "" then "-" else . end)] | @tsv' 2>/dev/null) || _out=""
    printf '%s\n' "$_out" | tr -d '\r' | grep -v '^$' > "$MERGED" || true
fi

# --- lookups -----------------------------------------------------------------

pr_for_branch() { awk -F'\t' -v b="$1" '$2 == b { print; exit }' "$PRS"; }
wt_for_branch() { awk -F'\t' -v b="$1" '$3 == b { print; exit }' "$WTS"; }
br_row() { awk -F'\t' -v b="$1" '$1 == b { print; exit }' "$BRS"; }

# issue_from_branch BRANCH -> leading number of "<N>-slug", else a number found on a
# state-file row mentioning the branch, else nothing.
issue_from_branch() {
    _n=$(printf '%s' "$1" | sed -n 's/^\([0-9][0-9]*\)-.*/\1/p')
    if [ -z "$_n" ] && [ -n "$1" ] && [ "$1" != "-" ] && [ "$1" != "(detached)" ]; then
        _n=$(awk -F'\t' -v b="$1" 'index($2, b) { l = $2; if (match(l, /\| *#?[0-9]+/)) { s = substr(l, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); print s; exit } }' "$SROWS")
    fi
    printf '%s' "$_n"
}

# state_for_issue N -> comma-separated stamps of unfinished runs listing Issue N.
state_for_issue() {
    [ -n "$1" ] && [ "$1" != "-" ] || return 0
    awk -F'\t' -v n="$1" '{ c = split($5, a, " "); for (i = 1; i <= c; i++) if (a[i] == n) { out = out (out == "" ? "" : ",") $2 } } END { print out }' "$STATES"
}

# merged_pr_for_issue N -> number of a merged PR closing Issue N or on branch "<N>-*".
merged_pr_for_issue() {
    awk -F'\t' -v n="$1" '
        { c = split($3, a, ","); for (i = 1; i <= c; i++) if (a[i] == n) { print $1; exit }
          if ($2 ~ ("^" n "-")) { print $1; exit } }' "$MERGED"
}

claim_branch() { printf '%s\n' "$1" >> "$CLAIMED_BR"; }
branch_claimed() { grep -qx -- "$1" "$CLAIMED_BR"; }
claim_issue() { [ -n "$1" ] && [ "$1" != "-" ] && printf '%s\n' "$1" >> "$CLAIMED_ISSUE" || true; }
issue_claimed() { grep -qx -- "$1" "$CLAIMED_ISSUE"; }

# --- decision ----------------------------------------------------------------

# Inputs are the d_* globals set by the caller; outputs NEXT and REASON.
decide_next() {
    NEXT=""; REASON=""
    _pr_known=1
    [ "$GH_STATE" = ok ] || _pr_known=0

    if [ "$d_orphan" = 1 ]; then
        NEXT="/worktree-sweep"; REASON="orphaned worktree directory"
    else
        case "$d_agent" in
            alive:*) NEXT=wait; REASON="agent session alive (pid ${d_agent#alive:})" ;;
            locked:*) NEXT=wait; REASON="locked by hand: ${d_agent#locked:}; unlocking is a human decision" ;;
        esac
    fi
    if [ -z "$NEXT" ] && [ -n "$d_pr" ] && [ "$d_pr" != "-" ]; then
        if [ "$d_draft" = 1 ]; then
            NEXT=wait; REASON="draft; mark ready first"
            case "$d_agent" in recent:*) REASON="$REASON (worktree touched ${d_agent#recent:}, worker may still be writing)" ;; esac
        elif [ "$d_mergeable" = CONFLICTING ] || [ "$d_mergestate" = DIRTY ]; then
            NEXT="/pr-fix $d_pr"; REASON="conflicts with base"
        elif [ "$d_checks" = fail ]; then
            NEXT="/pr-fix $d_pr"; REASON="checks failing"
        elif [ "$d_review" = CHANGES_REQUESTED ]; then
            NEXT="/pr-fix $d_pr"; REASON="changes requested"
        elif [ "$d_checks" = pending ]; then
            NEXT=wait; REASON="checks running (gh pr checks $d_pr --watch)"
        elif [ "$d_mergeable" = UNKNOWN ]; then
            NEXT=wait; REASON="mergeability not computed yet; re-run"
        elif [ "$d_review" = APPROVED ]; then
            NEXT="/pr-land $d_pr"; REASON="approved, checks green"
            [ "$d_mergestate" = BEHIND ] && REASON="$REASON; behind base, update first if protection requires"
        elif [ "$d_review" = REVIEW_REQUIRED ]; then
            NEXT="/pr-review $d_pr"; REASON="review required by branch protection; approval must come from GitHub"
        elif [ "$d_review" = NONE ]; then
            NEXT="/pr-review $d_pr"; REASON="not reviewed yet (or /pr-land $d_pr to skip review)"
        elif [ "$d_mergestate" = BLOCKED ]; then
            NEXT=wait; REASON="blocked by branch protection; see gh pr view $d_pr"
        else
            NEXT=wait; REASON="PR state $d_prstate; see gh pr view $d_pr"
        fi
    fi
    if [ -z "$NEXT" ] && [ -n "$d_wt" ] && [ "$d_wt" != "-" ]; then
        _recent=""
        case "$d_agent" in recent:*) _recent=${d_agent#recent:} ;; esac
        if [ "$d_dirty" = 1 ] && [ -n "$_recent" ]; then
            NEXT=wait; REASON="uncommitted changes, touched $_recent ago; worker may be running"
        elif [ "$d_dirty" = 1 ] && [ -n "$d_state" ] && [ "$d_state" != "-" ]; then
            NEXT="/ship-issues --resume"; REASON="uncommitted work from a ship-issues run"
        elif [ "$d_dirty" = 1 ]; then
            NEXT="/pr-ready (in $d_wt)"; REASON="uncommitted work, no PR"
        fi
    fi
    if [ -z "$NEXT" ] && [ "${d_ahead:-0}" -gt 0 ] 2>/dev/null; then
        if [ -n "$d_state" ] && [ "$d_state" != "-" ]; then
            NEXT="/ship-issues --resume"; REASON="commits without PR, listed in state file"
        elif [ -n "$d_wt" ] && [ "$d_wt" != "-" ]; then
            NEXT="/pr-ready (in $d_wt)"; REASON="commits without PR"
        else
            NEXT="/pr-ready (on $d_branch)"; REASON="commits without PR"
        fi
    fi
    if [ -z "$NEXT" ] && [ -n "$d_wt" ] && [ "$d_wt" != "-" ]; then
        case "$d_agent" in
            recent:*) NEXT=wait; REASON="fresh worktree, nothing committed yet" ;;
            *) NEXT="/worktree-sweep"; REASON="empty worktree" ;;
        esac
    fi
    if [ -z "$NEXT" ] && [ "$d_merged" = 1 ]; then
        NEXT="/worktree-sweep"; REASON="merged into $BASE"
    fi
    if [ -z "$NEXT" ] && [ "$d_gone" = 1 ]; then
        NEXT="/worktree-sweep"; REASON="upstream gone"
    fi
    if [ -z "$NEXT" ] && [ -n "$d_mergedpr" ]; then
        NEXT="-"; REASON="done: PR #$d_mergedpr merged; state file lacks DONE"
    fi
    if [ -z "$NEXT" ] && [ "$d_kind" = state ]; then
        NEXT="/ship-issues --resume"; REASON="listed in state file, no local or GitHub signal"
    fi
    if [ -z "$NEXT" ]; then
        NEXT=wait; REASON="no actionable signal"
    fi

    if [ "$_pr_known" -eq 0 ] && [ "$d_kind" != orphan ]; then
        REASON="$REASON; GitHub state unknown"
    fi
    if [ -n "$INVOKED_WT" ] && [ "$d_wt" = "$INVOKED_WT" ]; then
        case "$NEXT" in
            /worktree-sweep) REASON="$REASON; run it from outside this worktree" ;;
        esac
    fi
}

# emit_row KEY -> appends a row from the d_* globals after deciding next.
emit_row() {
    decide_next
    _wtcol=$d_wt
    if [ -n "$d_wt" ] && [ "$d_wt" != "-" ]; then
        [ "$d_dirty" = 1 ] && _wtcol="$_wtcol+dirty"
        [ "$d_orphan" = 1 ] && _wtcol="$_wtcol+orphan"
        [ "$d_wt" = "$INVOKED_WT" ] && _wtcol="$_wtcol+current"
    fi
    _ab="-"
    if [ -n "$d_branch" ] && [ "$d_branch" != "-" ] && [ "$d_branch" != "(detached)" ] && [ -n "$d_ahead" ]; then
        _ab="$d_ahead/$d_behind"
    fi
    printf 'row\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$1" "${d_issue:--}" "${d_pr:--}" "${d_prstate:--}" "${d_checks:--}" "${d_review:--}" \
        "${d_branch:--}" "$_ab" "${_wtcol:--}" "${d_agent:--}" "${d_state:--}" "$NEXT" "$REASON" >> "$ROWS"
}

reset_d() {
    d_kind=""; d_issue=""; d_pr=""; d_prstate=""; d_checks=""; d_review=""; d_draft=0
    d_mergeable=""; d_mergestate=""; d_branch=""; d_ahead=""; d_behind=""; d_merged=0; d_gone=0
    d_wt=""; d_dirty=0; d_orphan=0; d_agent="-"; d_state=""; d_mergedpr=""
}

fill_from_branch() {  # sets d_ahead d_behind d_merged d_gone from BRS
    _b=$(br_row "$1")
    if [ -n "$_b" ]; then
        d_ahead=$(printf '%s' "$_b" | cut -f2)
        d_behind=$(printf '%s' "$_b" | cut -f3)
        d_merged=$(printf '%s' "$_b" | cut -f4)
        d_gone=$(printf '%s' "$_b" | cut -f5)
    fi
}

fill_from_wt() {  # sets d_wt d_dirty d_agent d_orphan from a WTS line
    d_wt=$(printf '%s' "$1" | cut -f1)
    d_dirty=$(printf '%s' "$1" | cut -f4)
    d_agent=$(printf '%s' "$1" | cut -f6)
    d_orphan=$(printf '%s' "$1" | cut -f7)
}

unknown_pr_cols() {
    if [ "$GH_STATE" != ok ]; then
        d_prstate="?"; d_checks="?"; d_review="?"
    fi
}

# --- rows: (1) open Pull Requests -------------------------------------------

while IFS="$TAB" read -r _num _head _draft _mergeable _mergestate _review _checks _issues _updated _url; do
    [ -n "$_num" ] || continue
    reset_d
    d_kind=pr
    d_pr=$_num; d_draft=$_draft; d_mergeable=$_mergeable; d_mergestate=$_mergestate
    d_review=$_review; d_checks=$_checks; d_branch=$_head
    if [ "$_draft" = 1 ]; then d_prstate=draft
    elif [ "$_mergeable" = CONFLICTING ]; then d_prstate=conflict
    else
        case "$_mergestate" in
            DIRTY) d_prstate=dirty ;;
            BLOCKED) d_prstate=blocked ;;
            BEHIND) d_prstate=behind ;;
            CLEAN|HAS_HOOKS) d_prstate=clean ;;
            UNSTABLE) d_prstate=unstable ;;
            *) d_prstate=unknown ;;
        esac
    fi
    d_issue=${_issues%%,*}
    [ "$d_issue" != "-" ] || d_issue=$(issue_from_branch "$_head")
    fill_from_branch "$_head"
    _w=$(wt_for_branch "$_head")
    [ -z "$_w" ] || fill_from_wt "$_w"
    d_state=$(state_for_issue "$d_issue")
    claim_branch "$_head"
    claim_issue "$d_issue"
    emit_row "$_head"
done < "$PRS"

# --- rows: (2) worktrees without a PR ---------------------------------------

while IFS="$TAB" read -r _name _path _branch _dirty _recent _agent _orphan; do
    [ -n "$_name" ] || continue
    if [ -n "$_branch" ] && [ "$_branch" != "-" ] && [ "$_branch" != "(detached)" ] && branch_claimed "$_branch"; then
        continue
    fi
    reset_d
    d_kind=wt
    d_wt=$_name; d_dirty=$_dirty; d_agent=$_agent; d_orphan=$_orphan; d_branch=$_branch
    if [ "$_orphan" = 1 ]; then
        d_kind=orphan
        d_branch="-"
    else
        fill_from_branch "$_branch"
        d_issue=$(issue_from_branch "$_branch")
        d_state=$(state_for_issue "$d_issue")
        claim_branch "$_branch"
        claim_issue "$d_issue"
    fi
    unknown_pr_cols
    _key=$_branch
    [ -n "$_key" ] && [ "$_key" != "-" ] && [ "$_key" != "(detached)" ] || _key=$_name
    emit_row "$_key"
done < "$WTS"

# --- rows: (3) branches with commits, merged, or upstream gone --------------

EMPTY_AGENT_BRANCHES=0
while IFS="$TAB" read -r _br _ahead _behind _merged _gone; do
    [ -n "$_br" ] || continue
    branch_claimed "$_br" && continue
    case "$_br" in
        worktree-agent-*)
            if [ "$_ahead" -eq 0 ]; then
                EMPTY_AGENT_BRANCHES=$((EMPTY_AGENT_BRANCHES + 1))
                continue
            fi
            ;;
    esac
    if [ "$_ahead" -eq 0 ] && [ "$_merged" = 0 ] && [ "$_gone" = 0 ]; then
        continue
    fi
    reset_d
    d_kind=branch
    d_branch=$_br; d_ahead=$_ahead; d_behind=$_behind; d_merged=$_merged; d_gone=$_gone
    d_issue=$(issue_from_branch "$_br")
    d_state=$(state_for_issue "$d_issue")
    unknown_pr_cols
    claim_branch "$_br"
    claim_issue "$d_issue"
    emit_row "$_br"
done < "$BRS"

if [ "$EMPTY_AGENT_BRANCHES" -gt 0 ]; then
    note "$EMPTY_AGENT_BRANCHES leftover worktree-agent-* branch(es) with nothing ahead of $BASE; /worktree-sweep removes them"
fi

# --- rows: (4) state-file Issues not seen above -----------------------------

while IFS="$TAB" read -r _fname _stamp _started _options _issues _repo; do
    [ -n "$_fname" ] || continue
    _resolved=0; _total=0
    for _n in $_issues; do
        case "$_n" in *[!0-9]*|'') continue ;; esac
        _total=$((_total + 1))
        _mpr=$(merged_pr_for_issue "$_n")
        [ -z "$_mpr" ] || _resolved=$((_resolved + 1))
        issue_claimed "$_n" && continue
        reset_d
        d_kind=state
        d_issue=$_n; d_state=$_stamp; d_mergedpr=$_mpr
        unknown_pr_cols
        claim_issue "$_n"
        emit_row "issue-$_n"
    done
    printf 'state\t%s\t%s\t%s\t%s\t%s\t%s/%s\n' "$_fname" "$_started" "$_options" "$_issues" "$_repo" "$_resolved" "$_total" >> "$TMP/state_out"
    if [ "$_total" -gt 0 ] && [ "$_resolved" -eq "$_total" ]; then
        note "$_fname: all $_total Issue(s) have merged PRs but the file lacks DONE; /ship-issues --resume finalizes it"
    fi
done < "$STATES"

# --- output ------------------------------------------------------------------

printf '# repo\troot\trepository\tbase\tinvoked\tfetch\tgh\n'
printf 'repo\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ROOT" "${NWO:--}" "${BASE:--}" "$INVOKED" "$FETCH_STATE" "$GH_STATE"

N_ROWS=$(wc -l < "$ROWS" | tr -d " ")
if [ "$N_ROWS" -gt 0 ]; then
    printf '# row\tkey\tissue\tpr\tpr_state\tchecks\treview\tbranch\tahead/behind\tworktree\tagent\tstate\tnext\treason\n'
    cat "$ROWS"
fi

if [ -s "$TMP/state_out" ]; then
    printf '# state\tfile\tstarted\toptions\tissues\trepository\tresolved/total\n'
    cat "$TMP/state_out"
    if [ -s "$SROWS" ]; then
        printf '# srow\tfile\trow\n'
        sed 's/^/srow\t/' "$SROWS"
    fi
fi

if [ "$N_ROWS" -eq 0 ]; then
    note "nothing in flight"
fi
note "agent liveness is a heuristic: only a worktree lock whose pid is alive is a hard signal; background Agent tasks are visible only in the session that started them"

if [ -s "$NOTES" ]; then
    printf '# note\ttext\n'
    sed 's/^/note\t/' "$NOTES"
fi

if [ "$N_ROWS" -gt 0 ]; then
    awk -F'\t' '
        $13 == "wait" { w++; next }
        $13 == "/worktree-sweep" { s++; next }
        $13 == "-" { d++; next }
        { a++ }
        END { printf "summary\t%d row(s): %d actionable, %d waiting, %d sweep, %d done\n", NR, a, w, s, d }
    ' "$ROWS"
fi
