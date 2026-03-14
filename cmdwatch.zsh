#!/usr/bin/env zsh
# =============================================================================
# cmdwatch.zsh — Notices repeated mistyped commands and offers to create aliases
#
# Install:  echo 'source "/path/to/cmdwatch.zsh"' >> ~/.zshrc
# Or run:   ./install.sh
# =============================================================================

# ── Configuration (set these before sourcing to override) ─────────────────────
: "${CMDWATCH_THRESHOLD:=2}"           # how many times before asking
: "${CMDWATCH_DIR:="${HOME}/.cmdwatch"}"
: "${CMDWATCH_ZSHRC:="${HOME}/.zshrc"}"

# ── Internal paths ────────────────────────────────────────────────────────────
_cw_ignored="${CMDWATCH_DIR}/ignored"

# ── Bootstrap ─────────────────────────────────────────────────────────────────
_cw_ensure_dir() {
    [[ -d "$CMDWATCH_DIR" ]] || mkdir -p "$CMDWATCH_DIR"
    [[ -f "$_cw_ignored" ]] || : > "$_cw_ignored"
}

# ── Count tracking (one file per command, contains just the count) ─────────────
_cw_count_file() {
    # Sanitise the command name so it's safe as a filename
    local safe="${1//[^a-zA-Z0-9._-]/_}"
    echo "${CMDWATCH_DIR}/count_${safe}"
}

_cw_bump_count() {
    local f=$(_cw_count_file "$1")
    local n=0
    [[ -f "$f" ]] && n=$(<"$f")
    (( n++ ))
    echo "$n" > "$f"
    echo "$n"
}

# ── Ignore list ───────────────────────────────────────────────────────────────
_cw_is_ignored() { grep -qxF "$1" "$_cw_ignored" 2>/dev/null; }
_cw_add_ignore()  { echo "$1" >> "$_cw_ignored"; }

# ── "Did you mean?" suggestions ───────────────────────────────────────────────
_cw_git_cmds=(
    add am apply archive bisect blame branch bundle checkout cherry-pick
    citool clean clone commit describe diff fetch format-patch gc grep gui
    init log merge mergetool mv notes pull push range-diff rebase reflog
    remote repack replace request-pull reset restore revert rm send-email
    shortlog show show-ref sparse-checkout stash status submodule switch
    tag verify-commit verify-tag worktree
)

_cw_suggestions() {
    local cmd="$1"
    shift
    local args_str="$*"   # remaining args the user typed, e.g. "origin main"
    local suffix="${args_str:+ $args_str}"  # " origin main" or "" if none

    local -a out
    local -A seen   # associative array for O(1) dedup

    _cw_add_suggestion() {
        local s="$1"
        if [[ -z "${seen[$s]+_}" ]]; then
            seen[$s]=1
            out+=("$s")
        fi
    }

    if command -v git &>/dev/null; then
        local gc
        for gc in "${_cw_git_cmds[@]}"; do
            # Exact match
            [[ "$gc" == "$cmd" ]] && _cw_add_suggestion "git ${gc}${suffix}" && continue
            # Prefix match (e.g. "check" → "git checkout")
            [[ "$gc" == "${cmd}"* ]] && _cw_add_suggestion "git ${gc}${suffix}"
        done
    fi

    # npm/yarn scripts — only if package.json is in cwd or a parent
    local pkg d="$PWD"
    while [[ "$d" != "/" ]]; do
        [[ -f "$d/package.json" ]] && pkg="$d/package.json" && break
        d="${d:h}"
    done
    if [[ -n "$pkg" ]] && command -v node &>/dev/null; then
        local runner="npm run"
        command -v yarn &>/dev/null && runner="yarn"
        local scripts
        scripts=$(node -e "
            try {
                const s = require('$pkg').scripts || {};
                Object.keys(s).forEach(k => console.log(k));
            } catch(e) {}
        " 2>/dev/null)
        while IFS= read -r s; do
            [[ -z "$s" ]] && continue
            [[ "$s" == *"$cmd"* || "$cmd" == *"$s"* ]] && _cw_add_suggestion "${runner} ${s}${suffix}"
        done <<< "$scripts"
    fi

    # Emit up to 4 suggestions
    printf '%s\n' "${out[@]}" | head -4
}

# ── Ordinal helper ────────────────────────────────────────────────────────────
_cw_ordinal() {
    case "$1" in
        1) echo "1st" ;; 2) echo "2nd" ;; 3) echo "3rd" ;; *) echo "${1}th" ;;
    esac
}

# ── UI ────────────────────────────────────────────────────────────────────────
_cw_show_ui() {
    local cmd="$1" count="$2"
    shift 2
    local -a suggestions=("$@")

    printf '\n' >/dev/tty

    # Header
    printf '  \e[1;35m⚡ cmdwatch\e[0m\n' >/dev/tty
    printf '  \e[1m%s\e[0m \e[2mnot found — %s time you'"'"'ve typed this\e[0m\n' \
        "$cmd" "$(_cw_ordinal "$count")" >/dev/tty

    # Suggestions
    if (( ${#suggestions[@]} > 0 )); then
        printf '\n' >/dev/tty
        printf '  \e[2mdid you mean?\e[0m\n' >/dev/tty
        local i=1
        for s in "${suggestions[@]}"; do
            printf '  \e[36m[%d]\e[0m \e[1m%s\e[0m\n' "$i" "$s" >/dev/tty
            (( i++ ))
        done
    fi

    # Menu
    printf '\n' >/dev/tty
    if (( ${#suggestions[@]} > 0 )); then
        printf '  \e[36m[1-%d]\e[0m alias it   \e[32m[a]\e[0m custom alias   \e[33m[s]\e[0m skip   \e[31m[n]\e[0m never\e[0m\n' \
            "${#suggestions[@]}" >/dev/tty
    else
        printf '  \e[32m[a]\e[0m alias it   \e[33m[s]\e[0m skip   \e[31m[n]\e[0m never ask again\e[0m\n' >/dev/tty
    fi
    printf '\n' >/dev/tty
}

# ── Alias creation wizard ─────────────────────────────────────────────────────
_cw_alias_wizard() {
    local cmd="$1"
    shift
    local -a suggestions=("$@")

    printf '\n' >/dev/tty

    if (( ${#suggestions[@]} > 0 )); then
        printf '  Pick a number or type your own expansion:\n' >/dev/tty
    else
        printf '  What should \e[1m%s\e[0m expand to? ' "$cmd" >/dev/tty
    fi

    printf '  \e[2m❯ \e[0m' >/dev/tty
    local choice
    read -r choice </dev/tty

    local expansion=""
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#suggestions[@]} )); then
        expansion="${suggestions[$choice]}"
    else
        expansion="$choice"
    fi

    if [[ -z "$expansion" ]]; then
        printf '\n  \e[2m(skipped — nothing entered)\e[0m\n\n' >/dev/tty
        return
    fi

    # Append to .zshrc under a labelled section
    if ! grep -qF '# cmdwatch aliases' "$CMDWATCH_ZSHRC" 2>/dev/null; then
        printf '\n# cmdwatch aliases\n' >> "$CMDWATCH_ZSHRC"
    fi
    printf "alias %s='%s'\n" "$cmd" "$expansion" >> "$CMDWATCH_ZSHRC"

    # Activate in the current session immediately (direct alias, no eval quoting issues)
    alias -- "${cmd}=${expansion}"

    # Ignore this command from now on — the alias handles it
    _cw_add_ignore "$cmd"

    printf '\n  \e[1;32m✓\e[0m  \e[1malias %s='"'"'%s'"'"'\e[0m\n' "$cmd" "$expansion" >/dev/tty
    printf '  \e[2mSaved to %s · active right now.\e[0m\n\n' "$CMDWATCH_ZSHRC" >/dev/tty
}

# ── Main handler ──────────────────────────────────────────────────────────────
command_not_found_handler() {
    local cmd="$1"

    _cw_ensure_dir

    # Silently pass through if on the ignore list
    if _cw_is_ignored "$cmd"; then
        printf 'zsh: command not found: %s\n' "$cmd" >&2
        return 127
    fi

    local count
    count=$(_cw_bump_count "$cmd")

    # Below threshold: standard "not found" message only
    if (( count < CMDWATCH_THRESHOLD )); then
        printf 'zsh: command not found: %s\n' "$cmd" >&2
        return 127
    fi

    # Collect suggestions (pass any args the user typed for context-aware completions)
    local -a suggestions
    while IFS= read -r line; do
        [[ -n "$line" ]] && suggestions+=("$line")
    done < <(_cw_suggestions "$@")

    _cw_show_ui "$cmd" "$count" "${suggestions[@]}"

    local key
    read -rk1 key </dev/tty

    case "$key" in
        [1-9])
            # Pick a numbered suggestion directly
            local idx=$(( key ))
            if (( idx >= 1 && idx <= ${#suggestions[@]} )); then
                local expansion="${suggestions[$idx]}"
                printf '\n' >/dev/tty
                if ! grep -qF '# cmdwatch aliases' "$CMDWATCH_ZSHRC" 2>/dev/null; then
                    printf '\n# cmdwatch aliases\n' >> "$CMDWATCH_ZSHRC"
                fi
                printf "alias %s='%s'\n" "$cmd" "$expansion" >> "$CMDWATCH_ZSHRC"
                alias -- "${cmd}=${expansion}"
                _cw_add_ignore "$cmd"
                printf '  \e[1;32m✓\e[0m  \e[1malias %s='"'"'%s'"'"'\e[0m\n' "$cmd" "$expansion" >/dev/tty
                printf '  \e[2mSaved to %s · active right now.\e[0m\n\n' "$CMDWATCH_ZSHRC" >/dev/tty
            else
                printf '\n  \e[2m(skipped)\e[0m\n\n' >/dev/tty
            fi
            ;;
        a|A)
            _cw_alias_wizard "$cmd" "${suggestions[@]}"
            ;;
        n|N)
            _cw_add_ignore "$cmd"
            printf '\n  \e[2mGot it — won'"'"'t ask about \e[0m\e[1m%s\e[0m\e[2m again.\e[0m\n\n' \
                "$cmd" >/dev/tty
            ;;
        *)
            printf '\n  \e[2m(skipped)\e[0m\n\n' >/dev/tty
            ;;
    esac

    return 127
}

# ── Management command ────────────────────────────────────────────────────────
cmdwatch() {
    local subcmd="${1:-stats}"

    case "$subcmd" in
        stats)
            printf '\n  \e[1;35m⚡ cmdwatch\e[0m\n\n'

            # Aliases created — also sync any missing entries into the ignore list
            printf '  \e[1mAliases created\e[0m\n'
            local aliases
            aliases=$(awk '/# cmdwatch aliases/{found=1; next} found && /^alias /{print}' "$CMDWATCH_ZSHRC" 2>/dev/null)
            if [[ -n "$aliases" ]]; then
                while IFS= read -r line; do
                    printf '  \e[32m✓\e[0m  \e[1m%s\e[0m\n' "$line"
                    # Extract the alias name and ensure it's in the ignore list
                    local aname="${line#alias }"
                    aname="${aname%%=*}"
                    _cw_is_ignored "$aname" || _cw_add_ignore "$aname"
                done <<< "$aliases"
            else
                printf '  \e[2m  none yet\e[0m\n'
            fi

            # Tracked commands (count files)
            printf '\n  \e[1mTracked misses\e[0m\n'
            local found_any=0
            for f in "${CMDWATCH_DIR}"/count_*(N); do
                local cmd="${f:t}"         # filename
                cmd="${cmd#count_}"        # strip prefix
                local n=$(<"$f")
                printf '  \e[2m%-20s\e[0m %s miss%s\n' "$cmd" "$n" "$([[ $n == 1 ]] && echo '' || echo 'es')"
                found_any=1
            done
            (( found_any )) || printf '  \e[2m  none yet\e[0m\n'

            # Ignored commands
            printf '\n  \e[1mIgnored commands\e[0m\n'
            if [[ -s "$_cw_ignored" ]]; then
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    printf '  \e[31m✗\e[0m  %s\n' "$line"
                done < "$_cw_ignored"
            else
                printf '  \e[2m  none\e[0m\n'
            fi

            printf '\n'
            ;;

        unignore)
            local cmd="$2"
            if [[ -z "$cmd" ]]; then
                printf 'Usage: cmdwatch unignore <command>\n' >&2
                return 1
            fi
            local tmp="${_cw_ignored}.tmp"
            grep -vxF "$cmd" "$_cw_ignored" > "$tmp" 2>/dev/null && mv -- "$tmp" "$_cw_ignored"
            printf '  \e[32m✓\e[0m  Unignored \e[1m%s\e[0m\n' "$cmd"
            ;;

        reset)
            local cmd="$2"
            if [[ -z "$cmd" ]]; then
                printf 'Usage: cmdwatch reset <command>\n' >&2
                return 1
            fi
            local f=$(_cw_count_file "$cmd")
            rm -f "$f"
            printf '  \e[32m✓\e[0m  Reset count for \e[1m%s\e[0m\n' "$cmd"
            ;;

        add)
            # cmdwatch add [<cmd> [<expansion>]]
            local cmd="$2" expansion="$3"

            if [[ -z "$cmd" ]]; then
                printf '  \e[2mCommand to alias:\e[0m '
                read -r cmd
            fi
            [[ -z "$cmd" ]] && { printf 'cmdwatch: command name required\n' >&2; return 1; }

            if [[ -z "$expansion" ]]; then
                printf '  \e[2mExpand \e[0m\e[1m%s\e[0m\e[2m to:\e[0m ' "$cmd"
                read -r expansion
            fi
            [[ -z "$expansion" ]] && { printf 'cmdwatch: expansion required\n' >&2; return 1; }

            if ! grep -qF '# cmdwatch aliases' "$CMDWATCH_ZSHRC" 2>/dev/null; then
                printf '\n# cmdwatch aliases\n' >> "$CMDWATCH_ZSHRC"
            fi
            printf "alias %s='%s'\n" "$cmd" "$expansion" >> "$CMDWATCH_ZSHRC"
            alias -- "${cmd}=${expansion}"
            _cw_add_ignore "$cmd"
            printf '  \e[1;32m✓\e[0m  \e[1malias %s='"'"'%s'"'"'\e[0m  \e[2m(active now)\e[0m\n' "$cmd" "$expansion"
            ;;

        remove)
            local cmd="$2"
            if [[ -z "$cmd" ]]; then
                printf 'Usage: cmdwatch remove <command>\n' >&2
                return 1
            fi

            # Remove from .zshrc (matches lines like: alias cmd='...')
            local tmp="${CMDWATCH_ZSHRC}.cmdwatch.tmp"
            grep -v "^alias ${cmd}='" "$CMDWATCH_ZSHRC" > "$tmp" 2>/dev/null \
                && mv -- "$tmp" "$CMDWATCH_ZSHRC" \
                || rm -f "$tmp"

            # Unalias in current session
            unalias "$cmd" 2>/dev/null || true

            # Remove from ignore list
            local itmp="${_cw_ignored}.tmp"
            grep -vxF "$cmd" "$_cw_ignored" > "$itmp" 2>/dev/null \
                && mv -- "$itmp" "$_cw_ignored" \
                || rm -f "$itmp"

            # Reset miss count
            rm -f "$(_cw_count_file "$cmd")"

            printf '  \e[1;32m✓\e[0m  Removed alias for \e[1m%s\e[0m — cmdwatch will track it again\n' "$cmd"
            ;;

        help|--help|-h|h)
            printf '\n  \e[1;35m⚡ cmdwatch\e[0m\n\n'
            printf '  \e[1mUsage:\e[0m  cmdwatch <subcommand>\n\n'
            printf '  \e[1mSubcommands:\e[0m\n'
            printf '  \e[1mstats\e[0m                    Show aliases, tracked misses, and ignored commands\n'
            printf '  \e[1madd\e[0m [<cmd> [<expansion>]] Manually create a cmdwatch-managed alias\n'
            printf '  \e[1mremove\e[0m <cmd>              Remove an alias and start tracking the command again\n'
            printf '  \e[1munignore\e[0m <cmd>            Resume watching a silenced command (no alias)\n'
            printf '  \e[1mreset\e[0m <cmd>               Reset the miss count for a command\n'
            printf '  \e[1mhelp\e[0m                     Show this help\n'
            printf '\n'
            ;;

        *)
            printf 'cmdwatch: unknown subcommand "%s". Try: cmdwatch help\n' "$subcmd" >&2
            return 1
            ;;
    esac
}
