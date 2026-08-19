#!/bin/sh
# skill-lint.sh - Check that the skill definitions under a skills directory agree with
# each other and with their README.
#
# The skills are tied together by conventions nothing enforces: a frontmatter shape,
# `~/.claude/skills/...` and `~/.claude/scripts/...` references read by path, a README
# table that repeats every argument-hint, and the rule that SKILL.md is written in
# English. Each of those drifts silently when one file changes and another does not.
# This script makes the drift visible.
#
# Checks, per skill directory <skills>/<name>/SKILL.md:
#   frontmatter   starts with `---`, has `name: <name>` and `description:`; every skill
#                 except `cm` has `disable-model-invocation: true` and no
#                 `user-invocable: true`
#   options       every `--flag` / `-X` in argument-hint appears in the README table row
#                 for that skill, and vice versa (a missing argument-hint with options in
#                 the row is reported too); every option the body documents as a bullet
#                 (`- `--flag` ...`) or a heading (`### `--flag``) is in argument-hint
#   references    every `~/.claude/skills/...`, `~/.claude/scripts/...` and
#                 `~/.claude/forge/...` path in any *.md under the skill resolves to an
#                 existing file or directory
#   language      the SKILL.md body (after the frontmatter) contains no Japanese
#                 characters (kana, kanji, CJK punctuation, full-width forms); other
#                 files in the skill directory are not checked
# And for the README next to the skills:
#   table         one row per skill directory, no row without a directory, and one
#                 `## <name>` section per skill; the "`cm` 以外の N は" count matches
#   references    its `~/.claude/...` paths resolve, and every `](#anchor)` /
#                 `](<relative>.md#anchor)` link points at a heading that exists
# And for the scripts directory next to the skills (`../scripts`):
#   scripts       every *.sh there is referenced from at least one *.md under the skills
# And for the GitLab translation table (`../forge/gitlab.md`):
#   forge         every `gh <command> <subcommand>` (and `gh api`) that any *.md under
#                 the skills uses has a `### gh <command> <subcommand>` heading there,
#                 and no heading there is left unused by the skills
#
# The skills directory may be the deployed one (~/.claude/skills) or the chezmoi source
# (.../dot_claude/skills). In the source layout, `~/.claude/X` resolves under dot_claude/
# and scripts carry the `executable_` prefix; the script handles both. The README is
# not deployed, so in practice this runs against the source layout.
#
# Usage: skill-lint.sh [SKILLS_DIR]      default: ~/.claude/skills
# Exit: 0 when clean, 1 when at least one problem was reported, 2 on usage error.

set -eu

usage() {
    cat <<'EOF'
Usage: skill-lint.sh [SKILLS_DIR]

Checks SKILL.md frontmatter, argument-hint vs README table, ~/.claude/... path
references, English-only SKILL.md bodies, README table coverage and anchors,
that every script next to the skills is referenced, and that ../forge/gitlab.md
has a heading for every gh command the skills use.
SKILLS_DIR defaults to ~/.claude/skills.
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac
[ $# -le 1 ] || { usage >&2; exit 2; }

SKILLS=${1:-"$HOME/.claude/skills"}
SKILLS=$(cd "$SKILLS" 2>/dev/null && pwd -P) || { echo "not a directory: ${1:-$HOME/.claude/skills}" >&2; exit 2; }
README="$SKILLS/README.md"

# Where `~/.claude/<rest>` resolves. Source layout: <root>/dot_claude/skills.
case "$SKILLS" in
    */dot_claude/skills) CLAUDE_HOME=${SKILLS%/skills}; SOURCE_LAYOUT=1 ;;
    *)                   CLAUDE_HOME=${SKILLS%/skills}; SOURCE_LAYOUT=0 ;;
esac
SCRIPTS_DIR="$CLAUDE_HOME/scripts"
FORGE_DOC="$CLAUDE_HOME/forge/gitlab.md"

PROBLEMS=0
problem() {  # problem FILE LINE MESSAGE
    printf '%s:%s: %s\n' "$1" "$2" "$3"
    PROBLEMS=$((PROBLEMS + 1))
}

# resolve_ref REF -> prints the local path for a `~/.claude/...` reference, or nothing.
resolve_ref() {
    _rest=${1#\~/.claude/}
    _p="$CLAUDE_HOME/$_rest"
    if [ -e "$_p" ]; then printf '%s' "$_p"; return 0; fi
    if [ "$SOURCE_LAYOUT" -eq 1 ]; then
        _dir=$(dirname "$_p"); _base=$(basename "$_p")
        if [ -e "$_dir/executable_$_base" ]; then printf '%s' "$_dir/executable_$_base"; return 0; fi
    fi
    return 1
}

# check_refs FILE -> reports every `~/.claude/(skills|scripts|forge)/...` reference in
# FILE that does not resolve.
check_refs() {
    grep -n -o -E '~/\.claude/(skills|scripts|forge)/[A-Za-z0-9_./-]*' "$1" 2>/dev/null | tr -d '\r' \
        | sed 's/[.]*$//' | sort -u | while IFS=: read -r ln ref; do
            resolve_ref "$ref" >/dev/null || printf '%s:%s: reference does not resolve: %s\n' "$1" "$ln" "$ref"
        done > "$TABLE.refs" || true
    if [ -s "$TABLE.refs" ]; then
        cat "$TABLE.refs"
        PROBLEMS=$((PROBLEMS + $(wc -l < "$TABLE.refs")))
    fi
    rm -f "$TABLE.refs"
}

# slug TEXT -> the GitHub-style anchor for a heading: ASCII lowercased, ASCII and
# common full-width punctuation removed, spaces turned into `-`. Backticks and the
# like are removed rather than replaced, so "settings.json はキー単位で" becomes
# "settingsjson-はキー単位で", as GitHub renders it.
slug() {
    printf '%s' "$1" | tr 'A-Z' 'a-z' \
        | sed 's/[`.,:;!?()\[\]{}"'"'"'\/\\|<>@#$%^&*+=~]//g; s/（//g; s/）//g; s/、//g; s/。//g; s/「//g; s/」//g; s/：//g; s/／//g' \
        | tr ' ' '-'
}

# check_anchors FILE -> reports every `](#a)` and `](<rel>.md#a)` link in FILE whose
# anchor is not a heading of the target file.
check_anchors() {
    grep -n -o -E '\]\(([A-Za-z0-9_./-]*\.md)?#[^)]+\)' "$1" 2>/dev/null | tr -d '\r' \
        | sed 's/\](\(.*\))$/\1/' | while IFS=: read -r ln link; do
            _target=${link%%#*}; _anchor=${link#*#}
            if [ -z "$_target" ]; then _tf=$1; else _tf=$(dirname "$1")/$_target; fi
            if [ ! -f "$_tf" ]; then
                printf '%s:%s: link target does not exist: %s\n' "$1" "$ln" "$link"
                continue
            fi
            _found=0
            while IFS= read -r _h; do
                [ "$(slug "$_h")" = "$_anchor" ] && { _found=1; break; }
            done <<EOF
$(grep -E '^#{1,6} ' "$_tf" | sed 's/^#* *//' | tr -d '\r')
EOF
            [ "$_found" -eq 1 ] || printf '%s:%s: anchor not found in %s: #%s\n' "$1" "$ln" "$_target" "$_anchor"
        done > "$TABLE.anchors" || true
    if [ -s "$TABLE.anchors" ]; then
        cat "$TABLE.anchors"
        PROBLEMS=$((PROBLEMS + $(wc -l < "$TABLE.anchors")))
    fi
    rm -f "$TABLE.anchors"
}

# Japanese in the C locale: CJK punctuation \343\200 (U+3000-303F), hiragana/katakana
# \343\201-\203, kanji lead bytes \344-\351, full-width forms \357\274-\275. Built with
# printf so the script itself stays ASCII.
JA_PATTERN=$(printf '\343[\200-\203]|[\344-\351]|\357[\274-\275]')

# README table: `| [`name`](#name) | ... | args | ... |` -> line<TAB>name<TAB>args
TABLE=$(mktemp); trap 'rm -f "$TABLE" "$TABLE.refs" "$TABLE.anchors" "$TABLE.opts" "$TABLE.used" "$TABLE.headed"' EXIT
if [ -f "$README" ]; then
    grep -n -E '^\| \[`[^`]+`\]\(#[^)]+\)' "$README" | tr -d '\r' \
        | awk -F'|' '{ ln = $1; sub(/:.*$/, "", ln); n = $2; sub(/^ *\[`/, "", n); sub(/`.*$/, "", n); a = $4; gsub(/^ +| +$/, "", a); print ln "\t" n "\t" a }' > "$TABLE"
else
    problem "$README" 0 "README.md not found next to the skills"
fi

# option_tokens TEXT -> `--flag` and `-X` tokens, one per line, sorted unique
option_tokens() {
    printf '%s\n' "$1" | tr ' []|/`,()' '\n\n\n\n\n\n\n\n\n' | grep -E '^--?[A-Za-z][A-Za-z0-9-]*$' | sort -u || true
}

NSKILLS=0
for dir in "$SKILLS"/*/; do
    [ -d "$dir" ] || continue
    dir=${dir%/}
    NSKILLS=$((NSKILLS + 1))
    name=$(basename "$dir")
    skill="$dir/SKILL.md"
    if [ ! -f "$skill" ]; then
        problem "$dir" 0 "no SKILL.md"
        continue
    fi

    # --- frontmatter ---------------------------------------------------------
    if [ "$(head -n 1 "$skill" | tr -d '\r')" != "---" ]; then
        problem "$skill" 1 "frontmatter must start with ---"
        continue
    fi
    fm_end=$(awk 'NR > 1 && /^---\r?$/ { print NR; exit }' "$skill")
    [ -n "$fm_end" ] || { problem "$skill" 1 "frontmatter is not closed"; continue; }
    fm=$(sed -n "2,$((fm_end - 1))p" "$skill" | tr -d '\r')

    fm_name=$(printf '%s\n' "$fm" | sed -n 's/^name: *//p' | head -n 1)
    [ "$fm_name" = "$name" ] || problem "$skill" 2 "name is '${fm_name:-<missing>}', directory is '$name'"
    printf '%s\n' "$fm" | grep -q '^description: *.' || problem "$skill" 2 "description is missing"
    if [ "$name" != cm ]; then
        printf '%s\n' "$fm" | grep -q '^disable-model-invocation: *true' \
            || problem "$skill" 2 "disable-model-invocation: true is missing (only cm may be model-invocable)"
        printf '%s\n' "$fm" | grep -q '^user-invocable: *true' \
            && problem "$skill" 2 "user-invocable: true is only for cm"
    fi
    hint=$(printf '%s\n' "$fm" | sed -n 's/^argument-hint: *//p' | head -n 1 | sed 's/^"\(.*\)"$/\1/')
    hint_opts=$(option_tokens "$hint")

    # --- options vs README table -----------------------------------------------
    row_ln=$(awk -F'\t' -v n="$name" '$2 == n { print $1; exit }' "$TABLE")
    row=$(awk -F'\t' -v n="$name" '$2 == n { print $3; exit }' "$TABLE")
    if [ -z "$row_ln" ] && [ -f "$README" ]; then
        problem "$README" 0 "no table row for skill '$name'"
    elif [ -n "$row_ln" ]; then
        row_opts=$(option_tokens "$row")
        for o in $hint_opts; do
            printf '%s\n' "$row_opts" | grep -qx -- "$o" \
                || problem "$README" "$row_ln" "table row '$name': option '$o' from argument-hint is missing"
        done
        for o in $row_opts; do
            printf '%s\n' "$hint_opts" | grep -qx -- "$o" \
                || problem "$skill" 2 "argument-hint lacks '$o', which the README table row lists"
        done
    fi
    if [ -f "$README" ] && ! grep -qE "^## $name\$" "$README"; then
        problem "$README" 0 "no '## $name' section for skill '$name'"
    fi

    # --- options documented in the body vs argument-hint ---------------------------
    # A bullet or heading whose first token is a backticked option is how the skills
    # document their own options (`- `--dry-run` — ...`, `### `--merge``). gh/git flags
    # appear inside prose and code blocks, never in that position.
    tail -n +"$((fm_end + 1))" "$skill" | tr -d '\r' \
        | grep -n -E '^(- |### )`--?[A-Za-z][A-Za-z0-9-]*[` ]' \
        | sed 's/^\([0-9]*\):\(- \|### \)`\(--\{0,1\}[A-Za-z][A-Za-z0-9-]*\).*/\1\t\3/' \
        | sort -u -k2,2 > "$TABLE.opts" || true
    while IFS="$(printf '\t')" read -r oln o; do
        [ -n "$o" ] || continue
        printf '%s\n' "$hint_opts" | grep -qx -- "$o" \
            || problem "$skill" "$((oln + fm_end))" "body documents option '$o' but argument-hint does not list it"
    done < "$TABLE.opts"

    # --- ~/.claude/... references ---------------------------------------------
    for md in "$dir"/*.md; do
        [ -f "$md" ] || continue
        check_refs "$md"
    done

    # --- language ------------------------------------------------------------------
    ja=$(tail -n +"$((fm_end + 1))" "$skill" | LC_ALL=C grep -n -E "$JA_PATTERN" | head -n 3 || true)
    if [ -n "$ja" ]; then
        printf '%s\n' "$ja" | while IFS=: read -r ln _; do
            printf '%s:%s: Japanese text in SKILL.md body (author skills in English)\n' "$skill" "$((ln + fm_end))"
        done
        PROBLEMS=$((PROBLEMS + $(printf '%s\n' "$ja" | wc -l)))
    fi
done

# --- README: rows without a directory, count sentence, references, anchors ------------
if [ -f "$README" ]; then
    while IFS="$(printf '\t')" read -r ln n _; do
        [ -n "$n" ] || continue
        [ -d "$SKILLS/$n" ] || problem "$README" "$ln" "table row '$n' has no skill directory"
    done < "$TABLE"

    count_ln=$(grep -n -E '`cm` 以外の [0-9]+ は' "$README" | head -n 1 | cut -d: -f1 || true)
    if [ -n "$count_ln" ]; then
        count=$(sed -n "${count_ln}p" "$README" | LC_ALL=C grep -o -E '[0-9]+ ' | head -n 1 | tr -d ' ')
        expected=$((NSKILLS - 1))
        [ "$count" = "$expected" ] \
            || problem "$README" "$count_ln" "says '\`cm\` 以外の $count' but there are $NSKILLS skill directories ($expected besides cm)"
    fi

    check_refs "$README"
    check_anchors "$README"
fi

# --- scripts nobody references ----------------------------------------------------
if [ -d "$SCRIPTS_DIR" ]; then
    for s in "$SCRIPTS_DIR"/*.sh; do
        [ -f "$s" ] || continue
        sname=$(basename "$s"); sname=${sname#executable_}
        if ! grep -rqs -- "scripts/$sname" "$SKILLS" --include='*.md'; then
            problem "$s" 0 "script is not referenced from any *.md under $SKILLS"
        fi
    done
fi

# --- gh commands vs the GitLab translation table ---------------------------------------
# Every `gh <cmd> <sub>` the skills run (in prose or code blocks) needs a `### gh <cmd>
# <sub>` section in forge/gitlab.md, or the GitLab path has nothing to translate it with.
# `gh api` is the one two-word form. The reverse (a heading nobody uses) is reported so
# the table does not accumulate dead rows. The README describes the skills rather than
# instructing them, so it is not scanned.
GH_CMDS='gh (auth|repo|pr|issue|label|release|run|workflow|search) [a-z][a-z-]*'
if [ ! -f "$FORGE_DOC" ]; then
    problem "$FORGE_DOC" 0 "GitLab translation table is missing"
else
    grep -rhoE "(^|[^A-Za-z0-9_-])($GH_CMDS|gh api)" "$SKILLS" --include='*.md' --exclude=README.md \
        | sed 's/^[^g]*//' | tr -d '\r' | sort -u > "$TABLE.used"
    grep -E "^### gh " "$FORGE_DOC" | sed 's/^### //' | tr -d '\r' | sort -u > "$TABLE.headed"
    while IFS= read -r c; do
        [ -n "$c" ] || continue
        grep -qxF -- "$c" "$TABLE.headed" \
            || problem "$FORGE_DOC" 0 "no '### $c' section, but the skills use it"
    done < "$TABLE.used"
    while IFS= read -r c; do
        [ -n "$c" ] || continue
        grep -qxF -- "$c" "$TABLE.used" \
            || problem "$FORGE_DOC" "$(grep -n -F "### $c" "$FORGE_DOC" | head -n 1 | cut -d: -f1)" "section '### $c' is not used by any skill"
    done < "$TABLE.headed"
    rm -f "$TABLE.used" "$TABLE.headed"
fi

if [ "$PROBLEMS" -eq 0 ]; then
    echo "ok: $NSKILLS skills checked"
    exit 0
fi
echo "$PROBLEMS problem(s)" >&2
exit 1
