#!/bin/sh
# label-sync.sh - Create or update the default label set on a repository.
#
# Works on GitHub (through gh) and GitLab (through glab); forge-detect.sh picks the CLI
# from the origin remote of the current directory, --forge overrides it. The label set
# lives in the LABELS table below and nowhere else. The script is idempotent: run it
# again and every line comes back as `keep`.
#
# For each label in the set:
#   - present with the same color and description  -> keep
#   - present with a different color or description -> update (gh label edit /
#                                                      glab label edit --label-id)
#   - absent, but one of its rename sources exists  -> rename (gh label edit --name /
#     glab label edit --new-name), so Issues already carrying the old label keep it
#     under the new name. When several sources exist, the first in the table is renamed
#     and the rest are left behind.
#   - absent                                        -> create (gh/glab label create)
#
# Labels outside the set are reported as `unmanaged` and left alone; a leftover rename
# source (the set label already exists next to it) is flagged `superseded by`, so
# label-apply can move its Issues over. With --prune, unmanaged labels are deleted only
# when no Issue or Pull Request (open or closed) carries them.
#
# On GitLab, labels inherited from a group are listed but never edited or deleted here
# (the project API cannot change them); they are reported as `keep`/`retain` with a note.
#
# Usage: label-sync.sh [--dry-run] [--prune] [--forge github|gitlab] [-R owner/repo]

set -eu

DRY_RUN=0
PRUNE=0
REPO=""
FORGE_OPT=""

# name|color|description|rename-from,rename-from,...
# Colors are hex without '#'. Descriptions must stay under GitHub's 100-char limit.
LABELS='
type/bug|d73a4a|Something is not working as intended|bug
type/feature|a2eeef|New capability or enhancement of existing behavior (feat)|enhancement,feature
type/refactor|c2e0c6|Internal restructuring with no behavior change|refactor,refactoring
type/perf|5319e7|Performance improvement|perf,performance
type/docs|0075ca|Documentation only|documentation,docs
type/test|bfd4f2|Adding or fixing tests only|test,tests
type/chore|ededed|Maintenance, tooling, build, CI, or dependency housekeeping|chore,ci,build
priority/high|b60205|Address before other open work|
priority/medium|fbca04|Normal priority|
priority/low|0e8a16|Nice to have; no urgency|
status/blocked|e99695|Cannot proceed until another Issue, PR, or external change lands|blocked
status/needs-info|d876e3|Waiting for more information from the reporter|question,needs-info
status/duplicate|cfd3d7|Already tracked by another Issue or PR|duplicate
status/wontfix|ffffff|Intentionally not going to be addressed|wontfix
dependencies|0366d6|Dependency updates (Dependabot / Renovate)|
security|ee0701|Security-relevant fix or hardening|
breaking-change|d93f0b|Changes behavior or interfaces incompatibly|breaking,breaking change
good first issue|7057ff|Good for newcomers|
help wanted|008672|Extra attention is needed|
'

usage() {
    cat <<'EOF'
Usage: label-sync.sh [options]

Creates or updates the default label set on a GitHub or GitLab repository. Idempotent.
GitHub's default labels (bug, enhancement, documentation, duplicate, wontfix, question)
are renamed into the set so existing Issues keep their labels.

Options:
  --dry-run       Report what would change without touching the repository.
  --prune         Delete labels outside the set that no Issue or Pull Request uses.
                  Labels in use are kept and reported. Off by default.
  --forge NAME    github or gitlab. Defaults to what forge-detect.sh says about the
                  current directory; required with -R when the current directory is
                  not a repository on the same forge.
  -R owner/repo   Target repository (group/subgroup/project on GitLab). Defaults to the
                  repository of the current directory.
  -h, --help      Show this help.
EOF
}

log() { printf '%s\n' "$*"; }

# --- argument parsing -------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --prune) PRUNE=1 ;;
        --forge)
            [ $# -ge 2 ] || { log "missing value for $1" >&2; usage >&2; exit 2; }
            FORGE_OPT=$2
            shift
            ;;
        --forge=*) FORGE_OPT=${1#--forge=} ;;
        -R|--repo)
            [ $# -ge 2 ] || { log "missing value for $1" >&2; usage >&2; exit 2; }
            REPO=$2
            shift
            ;;
        -R*) REPO=${1#-R} ;;
        --repo=*) REPO=${1#--repo=} ;;
        -h|--help) usage; exit 0 ;;
        *) log "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

case "$FORGE_OPT" in
    ""|github|gitlab) ;;
    *) log "--forge must be github or gitlab, not '$FORGE_OPT'" >&2; exit 2 ;;
esac

# --- preflight --------------------------------------------------------------

_lib=$(dirname "$0")/forge-detect.sh
[ -f "$_lib" ] || _lib=$(dirname "$0")/executable_forge-detect.sh
[ -f "$_lib" ] || _lib=$HOME/.claude/scripts/forge-detect.sh
. "$_lib"

if [ -n "$FORGE_OPT" ]; then
    FORGE=$FORGE_OPT
    case "$FORGE" in github) FORGE_CLI=gh ;; gitlab) FORGE_CLI=glab ;; esac
    command -v "$FORGE_CLI" >/dev/null 2>&1 || { log "$FORGE_CLI is not installed" >&2; exit 1; }
    if [ "$FORGE" = github ]; then
        gh auth status >/dev/null 2>&1 || { log "gh is not authenticated (run: gh auth login)" >&2; exit 1; }
    else
        glab auth status >/dev/null 2>&1 || { log "glab is not authenticated (run: glab auth login --hostname <host>)" >&2; exit 1; }
    fi
    # forge_detect is still the source of the default repository path.
    forge_detect . >/dev/null 2>&1 || true
elif ! forge_detect .; then
    log "$FORGE_ERROR" >&2
    if [ -n "$REPO" ]; then log "pass --forge github|gitlab together with -R" >&2; fi
    exit 1
fi

if [ -z "$REPO" ]; then
    REPO=$FORGE_PATH
    [ -n "$REPO" ] || { log "not inside a repository with an origin remote; pass -R owner/repo" >&2; exit 1; }
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM
EXISTING="$TMP/existing"   # tab-separated: name, color (no #), description, id, scope (project|group)
MANAGED="$TMP/managed"     # lower-cased names claimed by the set (targets and consumed rename sources)

# --- forge operations ---------------------------------------------------------
# Every forge-specific command lives here; the sync logic below only calls these.

# forge_write CMD ARGS... -> runs the CLI unless --dry-run. Errors are not swallowed.
forge_write() {
    if [ "$DRY_RUN" -eq 1 ]; then
        return 0
    fi
    "$@"
}

# forge_label_list -> fills EXISTING.
forge_label_list() {
    case "$FORGE" in
        github)
            # The whole list is fetched once. GitHub caps a repository well below 500 labels.
            gh label list -R "$REPO" --limit 500 --json name,color,description \
                --jq '.[] | [.name, .color, (.description // ""), "-", "project"] | @tsv' | tr -d '\r' > "$EXISTING"
            ;;
        gitlab)
            # 100 per page is the API maximum; keep paging while pages come back full.
            : > "$EXISTING"
            _page=1
            while :; do
                _chunk=$(glab label list -R "$REPO" --per-page 100 --page "$_page" --output json \
                    --jq '.[] | [.name, (.color | ltrimstr("#")), (.description // ""), (.id | tostring), (if .is_project_label == false then "group" else "project" end)] | @tsv' | tr -d '\r' | glab_tsv)
                printf '%s\n' "$_chunk" | grep -v '^$' >> "$EXISTING" || true
                [ "$(printf '%s\n' "$_chunk" | grep -c .)" -ge 100 ] || break
                _page=$((_page + 1))
            done
            ;;
    esac
}

# forge_label_update CUR_NAME ID COLOR DESC [NEW_NAME]
forge_label_update() {
    case "$FORGE" in
        github)
            set -- gh label edit "$1" -R "$REPO" --color "$3" --description "$4" ${5:+--name "$5"}
            ;;
        gitlab)
            set -- glab label edit -R "$REPO" --label-id "$2" --color "#$3" --description "$4" ${5:+--new-name "$5"}
            ;;
    esac
    forge_write "$@"
}

# forge_label_create NAME COLOR DESC
forge_label_create() {
    case "$FORGE" in
        github) forge_write gh label create "$1" -R "$REPO" --color "$2" --description "$3" ;;
        gitlab) forge_write glab label create -R "$REPO" --name "$1" --color "#$2" --description "$3" ;;
    esac
}

# forge_label_delete NAME
forge_label_delete() {
    case "$FORGE" in
        github) forge_write gh label delete "$1" -R "$REPO" --yes ;;
        gitlab) forge_write glab label delete "$1" -R "$REPO" ;;
    esac
}

# forge_label_usage NAME -> prints "<issues> <prs>" as 0/1 counts (a limit of 1 keeps
# it cheap), or nothing when a query failed. A failed query (offline, rate limit) must
# not end the script under set -e, and must not read as "unused".
forge_label_usage() {
    case "$FORGE" in
        github)
            _ni=$(gh issue list -R "$REPO" --label "$1" --state all --limit 1 --json number --jq length 2>/dev/null | tr -d '\r') || _ni=""
            _np=$(gh pr list -R "$REPO" --label "$1" --state all --limit 1 --json number --jq length 2>/dev/null | tr -d '\r') || _np=""
            ;;
        gitlab)
            _ni=$(glab issue list -R "$REPO" --label "$1" --all --per-page 1 --output json --jq length 2>/dev/null | tr -d '\r') || _ni=""
            _np=$(glab mr list -R "$REPO" --label "$1" --all --per-page 1 --output json --jq length 2>/dev/null | tr -d '\r') || _np=""
            ;;
    esac
    [ -n "$_ni" ] && [ -n "$_np" ] || return 0
    printf '%s %s' "$_ni" "$_np"
}

forge_label_list
: > "$MANAGED"

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# existing_row NAME -> prints the tab-separated row for NAME (case-insensitive), or nothing.
existing_row() {
    awk -F'\t' -v want="$(lower "$1")" 'tolower($1) == want { print; exit }' "$EXISTING"
}

mark_managed() { lower "$1" >> "$MANAGED"; printf '\n' >> "$MANAGED"; }

is_managed() {
    grep -Fxq -- "$(lower "$1")" "$MANAGED"
}

PREFIX=""
[ "$DRY_RUN" -eq 0 ] || PREFIX="[dry-run] "

N_CREATE=0
N_RENAME=0
N_UPDATE=0
N_KEEP=0
N_UNMANAGED=0
N_SUPERSEDED=0
N_DELETE=0
N_FAIL=0

# lower-cased rename source -> target, so leftover sources can be named as such below.
SOURCES="$TMP/sources"
printf '%s\n' "$LABELS" | while IFS='|' read -r name _ _ renames; do
    [ -n "$name" ] || continue
    IFS=','; for candidate in $renames; do
        unset IFS
        [ -n "$candidate" ] || continue
        printf '%s\t%s\n' "$(lower "$candidate")" "$name"
    done
    unset IFS
done > "$SOURCES"

# superseded_by NAME -> prints the set label NAME is a rename source of, or nothing.
superseded_by() {
    awk -F'\t' -v want="$(lower "$1")" '$1 == want { print $2; exit }' "$SOURCES"
}

log "repository: $REPO ($FORGE)"

# --- sync the set -----------------------------------------------------------

printf '%s\n' "$LABELS" | while IFS='|' read -r name color desc renames; do
    [ -n "$name" ] || continue

    row=$(existing_row "$name")
    if [ -n "$row" ]; then
        cur_name=$(printf '%s' "$row" | cut -f1)
        cur_color=$(printf '%s' "$row" | cut -f2)
        cur_desc=$(printf '%s' "$row" | cut -f3)
        cur_id=$(printf '%s' "$row" | cut -f4)
        cur_scope=$(printf '%s' "$row" | cut -f5)
        mark_managed "$name"
        if [ "$(lower "$cur_color")" = "$(lower "$color")" ] && [ "$cur_desc" = "$desc" ] && [ "$cur_name" = "$name" ]; then
            log "    keep     $name"
            echo keep >> "$TMP/counts"
        elif [ "$cur_scope" = group ]; then
            log "    keep     $name (group label; differs from the set but is not editable from the project)"
            echo keep >> "$TMP/counts"
        else
            what=""
            [ "$cur_name" = "$name" ] || what="${what}name "
            [ "$(lower "$cur_color")" = "$(lower "$color")" ] || what="${what}color "
            [ "$cur_desc" = "$desc" ] || what="${what}description "
            log "    ${PREFIX}update   $name (${what% })"
            new_name=""
            [ "$cur_name" = "$name" ] || new_name=$name
            if forge_label_update "$cur_name" "$cur_id" "$color" "$desc" "$new_name"; then
                echo update >> "$TMP/counts"
            else
                log "    failed   $name ($FORGE_CLI label edit exited $?)" >&2
                echo fail >> "$TMP/counts"
            fi
        fi
        continue
    fi

    # Absent. Look for a rename source that still exists (and is editable).
    src=""; src_id=""
    IFS=','; for candidate in $renames; do
        unset IFS
        [ -n "$candidate" ] || continue
        if is_managed "$candidate"; then
            continue
        fi
        crow=$(existing_row "$candidate")
        if [ -n "$crow" ] && [ "$(printf '%s' "$crow" | cut -f5)" = project ]; then
            src=$(printf '%s' "$crow" | cut -f1)
            src_id=$(printf '%s' "$crow" | cut -f4)
            break
        fi
    done
    unset IFS

    if [ -n "$src" ]; then
        # When several rename sources exist (say `chore` and `ci`), the first one in the
        # table wins; the rest stay behind and are reported as unmanaged / superseded
        # below, so label-apply can move their Issues over.
        mark_managed "$src"
        mark_managed "$name"
        log "    ${PREFIX}rename   $src -> $name"
        if forge_label_update "$src" "$src_id" "$color" "$desc" "$name"; then
            echo rename >> "$TMP/counts"
        else
            log "    failed   $src -> $name ($FORGE_CLI label edit exited $?)" >&2
            echo fail >> "$TMP/counts"
        fi
        continue
    fi

    mark_managed "$name"
    log "    ${PREFIX}create   $name"
    if forge_label_create "$name" "$color" "$desc"; then
        echo create >> "$TMP/counts"
    else
        log "    failed   $name ($FORGE_CLI label create exited $?)" >&2
        echo fail >> "$TMP/counts"
    fi
done

# --- labels outside the set --------------------------------------------------

# Rename sources that were consumed above are managed. Leftover rename sources whose
# target already existed (e.g. both `bug` and `type/bug`, or `ci` next to `chore`) show
# up here as `superseded`, so the overlap is visible even when the target needed no action.
while IFS="$(printf '\t')" read -r name color desc id scope; do
    [ -n "$name" ] || continue
    if is_managed "$name"; then
        continue
    fi
    target=$(superseded_by "$name")
    note=""
    kind=unmanaged
    if [ -n "$target" ]; then
        note=" (superseded by $target; move its Issues with label-apply, then delete it)"
        kind=superseded
    fi
    if [ "$PRUNE" -eq 0 ]; then
        log "    $kind $name$note"
        echo "$kind" >> "$TMP/counts"
        continue
    fi
    if [ "$scope" = group ]; then
        log "    retain   $name ($kind, group label; not deletable from the project)$note"
        echo "$kind" >> "$TMP/counts"
        continue
    fi
    usage_counts=$(forge_label_usage "$name")
    if [ -z "$usage_counts" ]; then
        log "    retain   $name ($kind, usage unknown: $FORGE_CLI query failed)$note"
        echo "$kind" >> "$TMP/counts"
        continue
    fi
    n_issues=${usage_counts% *}
    n_prs=${usage_counts#* }
    if [ "$n_issues" -eq 0 ] && [ "$n_prs" -eq 0 ]; then
        log "    ${PREFIX}delete   $name (unmanaged, unused)"
        if forge_label_delete "$name"; then
            echo delete >> "$TMP/counts"
        else
            log "    failed   $name ($FORGE_CLI label delete exited $?)" >&2
            echo fail >> "$TMP/counts"
        fi
    else
        log "    retain   $name ($kind, in use)$note"
        echo "$kind" >> "$TMP/counts"
    fi
done < "$EXISTING"

# --- summary ----------------------------------------------------------------

if [ -f "$TMP/counts" ]; then
    N_CREATE=$(grep -c '^create$' "$TMP/counts" || true)
    N_RENAME=$(grep -c '^rename$' "$TMP/counts" || true)
    N_UPDATE=$(grep -c '^update$' "$TMP/counts" || true)
    N_KEEP=$(grep -c '^keep$' "$TMP/counts" || true)
    N_UNMANAGED=$(grep -c '^unmanaged$' "$TMP/counts" || true)
    N_SUPERSEDED=$(grep -c '^superseded$' "$TMP/counts" || true)
    N_DELETE=$(grep -c '^delete$' "$TMP/counts" || true)
    N_FAIL=$(grep -c '^fail$' "$TMP/counts" || true)
fi

log "${PREFIX}created $N_CREATE, renamed $N_RENAME, updated $N_UPDATE, kept $N_KEEP, unmanaged $N_UNMANAGED, superseded $N_SUPERSEDED, deleted $N_DELETE, failed $N_FAIL"

[ "$N_FAIL" -eq 0 ] || exit 1
exit 0
