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
#                 except `cm` has `disable-model-invocation: true`
#   options       every `--flag` / `-X` in argument-hint appears in the README table row
#                 for that skill, and vice versa
#   references    every `~/.claude/skills/...` and `~/.claude/scripts/...` path in any
#                 *.md under the skill resolves to an existing file or directory
#   language      the SKILL.md body (after the frontmatter) contains no Japanese
#                 characters; other files in the skill directory are not checked
# And for the README next to the skills:
#   table         one row per skill directory, no row without a directory, and one
#                 `## <name>` section per skill
#
# The skills directory may be the deployed one (~/.claude/skills) or the chezmoi source
# (.../dot_claude/skills). In the source layout, `~/.claude/X` resolves under dot_claude/
# and scripts carry the `executable_` prefix; the script handles both.
#
# Usage: skill-lint.sh [SKILLS_DIR]      default: ~/.claude/skills
# Exit: 0 when clean, 1 when at least one problem was reported, 2 on usage error.

set -eu

usage() {
    cat <<'EOF'
Usage: skill-lint.sh [SKILLS_DIR]

Checks SKILL.md frontmatter, argument-hint vs README table, ~/.claude/... path
references, English-only SKILL.md bodies, and README table coverage.
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

# Japanese in the C locale: hiragana/katakana lead byte 0xE3 with 0x81-0x83, kanji lead
# bytes 0xE4-0xE9. Built with printf so the script itself stays ASCII.
JA_PATTERN=$(printf '\343[\201-\203]|[\344-\351]')

# README table: `| [`name`](#name) | ... | args | ... |` -> name<TAB>args
TABLE=$(mktemp); trap 'rm -f "$TABLE"' EXIT
if [ -f "$README" ]; then
    grep -E '^\| \[`[^`]+`\]\(#[^)]+\)' "$README" | tr -d '\r' \
        | awk -F'|' '{ n = $2; sub(/^ *\[`/, "", n); sub(/`.*$/, "", n); a = $4; gsub(/^ +| +$/, "", a); print n "\t" a }' > "$TABLE"
else
    problem "$README" 0 "README.md not found next to the skills"
fi

# option_tokens TEXT -> `--flag` and `-X` tokens, one per line, sorted unique
option_tokens() {
    printf '%s\n' "$1" | tr ' []|/`,()' '\n\n\n\n\n\n\n\n\n' | grep -E '^--?[A-Za-z][A-Za-z0-9-]*$' | sort -u || true
}

for dir in "$SKILLS"/*/; do
    [ -d "$dir" ] || continue
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
    # Lines 2..(closing ---)
    fm=$(sed -n '2,/^---$/p' "$skill" | tr -d '\r' | sed '$d')
    fm_end=$(awk 'NR > 1 && /^---\r?$/ { print NR; exit }' "$skill")
    [ -n "$fm_end" ] || { problem "$skill" 1 "frontmatter is not closed"; continue; }

    fm_name=$(printf '%s\n' "$fm" | sed -n 's/^name: *//p' | head -n 1)
    [ "$fm_name" = "$name" ] || problem "$skill" 2 "name is '${fm_name:-<missing>}', directory is '$name'"
    printf '%s\n' "$fm" | grep -q '^description: *.' || problem "$skill" 2 "description is missing"
    if [ "$name" != cm ]; then
        printf '%s\n' "$fm" | grep -q '^disable-model-invocation: *true' \
            || problem "$skill" 2 "disable-model-invocation: true is missing (only cm may be model-invocable)"
    fi
    hint=$(printf '%s\n' "$fm" | sed -n 's/^argument-hint: *//p' | head -n 1 | sed 's/^"\(.*\)"$/\1/')

    # --- options vs README table -----------------------------------------------
    row=$(awk -F'\t' -v n="$name" '$1 == n { print $2; exit }' "$TABLE")
    if [ -z "$row" ] && [ -f "$README" ]; then
        problem "$README" 0 "no table row for skill '$name'"
    elif [ -n "$hint" ]; then
        hint_opts=$(option_tokens "$hint")
        row_opts=$(option_tokens "$row")
        for o in $hint_opts; do
            printf '%s\n' "$row_opts" | grep -qx -- "$o" \
                || problem "$README" 0 "table row '$name': option '$o' from argument-hint is missing"
        done
        for o in $row_opts; do
            printf '%s\n' "$hint_opts" | grep -qx -- "$o" \
                || problem "$skill" 2 "argument-hint lacks '$o', which the README table row lists"
        done
    fi
    if [ -f "$README" ] && ! grep -qE "^## $name\$" "$README"; then
        problem "$README" 0 "no '## $name' section for skill '$name'"
    fi

    # --- ~/.claude/... references ---------------------------------------------
    for md in "$dir"*.md; do
        [ -f "$md" ] || continue
        grep -n -o -E '~/\.claude/(skills|scripts)/[A-Za-z0-9_./-]*' "$md" 2>/dev/null | tr -d '\r' \
            | sed 's/[.]*$//' | sort -u | while IFS=: read -r ln ref; do
                resolve_ref "$ref" >/dev/null || printf '%s:%s: reference does not resolve: %s\n' "$md" "$ln" "$ref"
            done > "$TABLE.refs" || true
        if [ -s "$TABLE.refs" ]; then
            cat "$TABLE.refs"
            PROBLEMS=$((PROBLEMS + $(wc -l < "$TABLE.refs")))
        fi
        rm -f "$TABLE.refs"
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

# --- README rows without a directory ----------------------------------------------
if [ -f "$README" ]; then
    while IFS="$(printf '\t')" read -r n _; do
        [ -n "$n" ] || continue
        [ -d "$SKILLS/$n" ] || problem "$README" 0 "table row '$n' has no skill directory"
    done < "$TABLE"
fi

if [ "$PROBLEMS" -eq 0 ]; then
    echo "ok: $(ls -d "$SKILLS"/*/ | wc -l | tr -d ' ') skills checked"
    exit 0
fi
echo "$PROBLEMS problem(s)" >&2
exit 1
