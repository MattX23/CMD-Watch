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

# ── .zshrc backup ─────────────────────────────────────────────────────────────
# Called before every write. Keeps one backup so the user can always recover.
_cw_backup_zshrc() {
    cp -- "$CMDWATCH_ZSHRC" "${CMDWATCH_DIR}/zshrc.bak" 2>/dev/null || true
}

# ── Alias writer (prevents duplicates, scoped to cmdwatch section) ─────────────
# Backs up .zshrc, then removes any existing cmdwatch alias for $cmd (only within
# the # cmdwatch aliases block) before appending the updated line.
_cw_write_alias() {
    local cmd="$1" expansion="$2"
    _cw_backup_zshrc
    if ! grep -qF '# cmdwatch aliases' "$CMDWATCH_ZSHRC" 2>/dev/null; then
        printf '\n# cmdwatch aliases\n' >> "$CMDWATCH_ZSHRC"
    fi
    # Remove any pre-existing alias for this command — scoped to our section so
    # we never touch aliases the user wrote themselves elsewhere in their .zshrc.
    local tmp="${CMDWATCH_ZSHRC}.cmdwatch.tmp.$$"
    awk -v cmd="alias ${cmd}='" '
        /# cmdwatch aliases/ { in_cw=1 }
        in_cw && index($0, cmd) == 1 { next }
        { print }
    ' "$CMDWATCH_ZSHRC" > "$tmp" 2>/dev/null \
        && mv -- "$tmp" "$CMDWATCH_ZSHRC" || rm -f "$tmp"
    printf "alias %s='%s'\n" "$cmd" "$expansion" >> "$CMDWATCH_ZSHRC"
}

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

# ── Alias activation ──────────────────────────────────────────────────────────
_cw_activate_alias() {
    alias "${1}=${2}"
}

_cw_print_activation_status() {
    local cmd="$1"
    if [[ -n "${aliases[$cmd]}" ]]; then
        printf '  \e[2mSaved to %s · active right now.\e[0m\n\n' "$CMDWATCH_ZSHRC"
    else
        printf '  \e[2mSaved to %s · run \e[0m\e[1msource ~/.zshrc\e[0m\e[2m to activate.\e[0m\n\n' "$CMDWATCH_ZSHRC"
    fi
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
    local cmd="$1" orig_args="$2"
    shift 2
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

    local expansion="" run_expansion=""
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#suggestions[@]} )); then
        expansion="${suggestions[$choice]}"
        # Strip user's original args so the alias is a bare command, not branch-specific.
        # e.g. "git merge main" → alias merge='git merge', auto-run "git merge main"
        [[ -n "$orig_args" && "$expansion" == *" ${orig_args}" ]] && \
            expansion="${expansion% ${orig_args}}"
        run_expansion="${expansion}${orig_args:+ ${orig_args}}"
    else
        expansion="$choice"
        run_expansion="$expansion"
    fi

    if [[ -z "$expansion" ]]; then
        printf '\n  \e[2m(skipped — nothing entered)\e[0m\n\n' >/dev/tty
        return
    fi

    _cw_write_alias "$cmd" "$expansion"
    _cw_activate_alias "$cmd" "$expansion"
    _cw_run_expansion="$run_expansion"

    printf '\n  \e[1;32m✓\e[0m  \e[1malias %s='"'"'%s'"'"'\e[0m\n' "$cmd" "$expansion" >/dev/tty
    _cw_print_activation_status "$cmd" >/dev/tty
}

# ── Main handler ──────────────────────────────────────────────────────────────
command_not_found_handler() {
    local cmd="$1"
    local orig_args="${*:2}"   # args the user typed after the command, e.g. "origin main"

    # Only track commands typed directly at the prompt.
    # If funcstack has more than one entry, this command was invoked by a
    # script or shell function — not the user. Pass through silently.
    if (( ${#funcstack} > 1 )); then
        printf 'zsh: command not found: %s\n' "$cmd" >&2
        return 127
    fi

    _cw_ensure_dir

    # If a cmdwatch alias for this command exists in .zshrc, it was aliased in a
    # previous session but isn't loaded yet. Pass through — don't re-prompt.
    # Importantly, if the user manually removes the alias from .zshrc, this check
    # fails and cmdwatch resumes tracking automatically.
    if grep -qF "alias ${cmd}=" "$CMDWATCH_ZSHRC" 2>/dev/null; then
        printf 'zsh: command not found: %s\n' "$cmd" >&2
        return 127
    fi

    # Silently pass through if the user has asked to never be prompted (pressed 'n')
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

    local key _cw_run_expansion=""
    read -rk1 key </dev/tty

    case "$key" in
        [1-9])
            # Pick a numbered suggestion directly
            local idx=$(( key ))
            if (( idx >= 1 && idx <= ${#suggestions[@]} )); then
                local expansion="${suggestions[$idx]}"
                # Alias should be the bare command — strip the user's original args.
                # e.g. "git merge main" → alias merge='git merge', then auto-run with "main"
                local alias_expansion="$expansion"
                [[ -n "$orig_args" && "$expansion" == *" ${orig_args}" ]] && \
                    alias_expansion="${expansion% ${orig_args}}"
                printf '\n' >/dev/tty
                _cw_write_alias "$cmd" "$alias_expansion"
                _cw_activate_alias "$cmd" "$alias_expansion"
                _cw_run_expansion="$expansion"   # auto-run uses the full original invocation
                printf '  \e[1;32m✓\e[0m  \e[1malias %s='"'"'%s'"'"'\e[0m\n' "$cmd" "$alias_expansion" >/dev/tty
                _cw_print_activation_status "$cmd" >/dev/tty
            else
                printf '\n  \e[2m(skipped)\e[0m\n\n' >/dev/tty
            fi
            ;;
        a|A)
            _cw_alias_wizard "$cmd" "$orig_args" "${suggestions[@]}"
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

    if [[ -n "$_cw_run_expansion" ]]; then
        eval "$_cw_run_expansion"
        return $?
    fi
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
            local cw_aliases_block
            cw_aliases_block=$(awk '/# cmdwatch aliases/{found=1; next} found && /^alias /{print}' "$CMDWATCH_ZSHRC" 2>/dev/null)
            if [[ -n "$cw_aliases_block" ]]; then
                while IFS= read -r line; do
                    printf '  \e[32m✓\e[0m  \e[1m%s\e[0m\n' "$line"
                done <<< "$cw_aliases_block"
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

            _cw_write_alias "$cmd" "$expansion"
            aliases[$cmd]="$expansion"
            printf '  \e[1;32m✓\e[0m  \e[1malias %s='"'"'%s'"'"'\e[0m  \e[2m(active now)\e[0m\n' "$cmd" "$expansion"
            ;;

        remove)
            local cmd="$2"
            if [[ -z "$cmd" ]]; then
                printf 'Usage: cmdwatch remove <command>\n' >&2
                return 1
            fi

            # Remove from .zshrc — backup first, then remove scoped to our section
            _cw_backup_zshrc
            local tmp="${CMDWATCH_ZSHRC}.cmdwatch.tmp.$$"
            awk -v cmd="alias ${cmd}='" '
                /# cmdwatch aliases/ { in_cw=1 }
                in_cw && index($0, cmd) == 1 { next }
                { print }
            ' "$CMDWATCH_ZSHRC" > "$tmp" 2>/dev/null \
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

        reset-all)
            printf '\n  \e[1;35m⚡ cmdwatch\e[0m  \e[31mThis will remove all aliases, counts, and ignored commands.\e[0m\n'
            printf '  Are you sure? \e[2m[y/N]\e[0m '
            local yn
            read -rk1 yn
            printf '\n'
            if [[ "$yn" != y && "$yn" != Y ]]; then
                printf '  \e[2m(cancelled)\e[0m\n\n'
                return 0
            fi

            # Backup before touching anything
            _cw_backup_zshrc

            # Read the exact alias lines we wrote so we remove only those
            local -a cw_alias_lines
            local line aname
            while IFS= read -r line; do
                [[ -n "$line" ]] && cw_alias_lines+=("$line")
                aname="${line#alias }"; aname="${aname%%=*}"
                unalias "$aname" 2>/dev/null || true
            done < <(awk '/# cmdwatch aliases/{found=1; next} found && /^alias /{print}' "$CMDWATCH_ZSHRC" 2>/dev/null)

            # Remove only the exact lines we know we wrote (header + each alias).
            # grep -vxFf matches whole lines exactly — nothing else in .zshrc is touched.
            local tmp="${CMDWATCH_ZSHRC}.cmdwatch.tmp.$$"
            { printf '# cmdwatch aliases\n'; printf '%s\n' "${cw_alias_lines[@]}"; } \
                | grep -vxFf - "$CMDWATCH_ZSHRC" > "$tmp" 2>/dev/null \
                && mv -- "$tmp" "$CMDWATCH_ZSHRC" || rm -f "$tmp"

            # Wipe the state directory
            rm -f "${CMDWATCH_DIR}"/count_* "$_cw_ignored"

            printf '  \e[1;32m✓\e[0m  All cmdwatch data cleared. Backup saved to %s/zshrc.bak\n\n' "$CMDWATCH_DIR"
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
            printf '  \e[1mreset-all\e[0m                 Wipe all aliases, counts, and ignored commands\n'
            printf '  \e[1mhelp\e[0m                     Show this help\n'
            printf '\n'
            ;;

        *)
            printf 'cmdwatch: unknown subcommand "%s". Try: cmdwatch help\n' "$subcmd" >&2
            return 1
            ;;
    esac
}
