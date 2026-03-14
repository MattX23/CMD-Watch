#!/usr/bin/env zsh
# Demo environment for vhs recording.
# Simulates cmdwatch behaviour using stdin instead of /dev/tty so vhs
# can route keystrokes correctly.

CMDWATCH_DIR="${HOME}/.cmdwatch"
CMDWATCH_ZSHRC="${HOME}/.zshrc"
mkdir -p "$CMDWATCH_DIR"

# ── Colours (same as real cmdwatch) ───────────────────────────────────────────
_b=$'\e[1m' _d=$'\e[2m' _r=$'\e[0m'
_grn=$'\e[32m' _yel=$'\e[33m' _cyn=$'\e[36m' _mag=$'\e[35m' _red=$'\e[31m'

# ── Miss counter ──────────────────────────────────────────────────────────────
_miss=0

# ── Simulated command_not_found_handler ───────────────────────────────────────
push() {
    (( _miss++ ))

    if (( _miss == 1 )); then
        printf 'zsh: command not found: push\n' >&2
        return 127
    fi

    # Second miss — show the UI
    local suggestion="git push $*"
    printf '\n'
    printf '  %s⚡ cmdwatch%s\n' "${_mag}${_b}" "$_r"
    printf '  %spush%s %snot found — 2nd time you'"'"'ve typed this%s\n' \
        "$_b" "$_r" "$_d" "$_r"
    printf '\n'
    printf '  %sdid you mean?%s\n' "$_d" "$_r"
    printf '  %s[1]%s %s%s%s\n' "$_cyn" "$_r" "$_b" "$suggestion" "$_r"
    printf '\n'
    printf '  %s[1-1]%s alias it   %s[a]%s custom   %s[s]%s skip   %s[n]%s never\n' \
        "$_cyn" "$_r" "$_grn" "$_r" "$_yel" "$_r" "$_red" "$_r"
    printf '\n'

    local key
    read -rk1 key

    case "$key" in
        1)
            # Write alias to .zshrc
            if ! grep -qF '# cmdwatch aliases' "$CMDWATCH_ZSHRC" 2>/dev/null; then
                printf '\n# cmdwatch aliases\n' >> "$CMDWATCH_ZSHRC"
            fi
            printf "alias push='%s'\n" "$suggestion" >> "$CMDWATCH_ZSHRC"
            alias -- "push=${suggestion}"
            printf '\n'
            printf '  %s✓%s  %salias push='"'"'%s'"'"'%s\n' \
                "${_grn}${_b}" "$_r" "$_b" "$suggestion" "$_r"
            printf '  %sSaved to ~/.zshrc · active right now.%s\n\n' "$_d" "$_r"
            ;;
        n|N)
            printf '\n  %s(never asking again)%s\n\n' "$_d" "$_r"
            ;;
        *)
            printf '\n  %s(skipped)%s\n\n' "$_d" "$_r"
            ;;
    esac
    return 127
}

# ── Simulated cmdwatch stats ───────────────────────────────────────────────────
cmdwatch() {
    if [[ "$1" == "stats" || -z "$1" ]]; then
        printf '\n  %s⚡ cmdwatch%s\n\n' "${_mag}${_b}" "$_r"
        printf '  %sAliases created%s\n' "$_b" "$_r"
        printf "  %s✓%s  %salias push='git push'%s\n" "$_grn" "$_r" "$_b" "$_r"
        printf '\n  %sTracked misses%s\n' "$_b" "$_r"
        printf '  %s%-20s%s 2 misses\n' "$_d" "push" "$_r"
        printf '\n  %sIgnored commands%s\n' "$_b" "$_r"
        printf '  %s✗%s  push\n' "$_red" "$_r"
        printf '\n'
    fi
}
