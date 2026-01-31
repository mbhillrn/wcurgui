#!/bin/bash
# MBTC-DASH - UI Helper Functions
# Source this file for UI drawing functions

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/colors.sh"

# ═══════════════════════════════════════════════════════════════════════════════
# TERMINAL UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

# Get terminal width
get_term_width() {
    local width
    width=$(tput cols 2>/dev/null || echo 80)
    echo "$width"
}

# Move cursor
cursor_up() { echo -en "\033[${1:-1}A"; }
cursor_down() { echo -en "\033[${1:-1}B"; }
cursor_right() { echo -en "\033[${1:-1}C"; }
cursor_left() { echo -en "\033[${1:-1}D"; }
cursor_save() { echo -en "\033[s"; }
cursor_restore() { echo -en "\033[u"; }
cursor_hide() { echo -en "\033[?25l"; }
cursor_show() { echo -en "\033[?25h"; }
clear_line() { echo -en "\033[2K\r"; }
clear_to_end() { echo -en "\033[K"; }

# ═══════════════════════════════════════════════════════════════════════════════
# TEXT FORMATTING
# ═══════════════════════════════════════════════════════════════════════════════

# Print colored text
cprint() {
    local color="$1"
    shift
    echo -e "${color}$*${RST}"
}

# Print without newline
cprintn() {
    local color="$1"
    shift
    echo -en "${color}$*${RST}"
}

# Center text
center_text() {
    local text="$1"
    local width="${2:-$(get_term_width)}"
    local text_len=${#text}
    local padding=$(( (width - text_len) / 2 ))
    printf "%*s%s%*s" "$padding" "" "$text" "$padding" ""
}

# Repeat a character
repeat_char() {
    local char="$1"
    local count="$2"
    printf '%*s' "$count" '' | tr ' ' "$char"
}

# ═══════════════════════════════════════════════════════════════════════════════
# HEADERS AND SECTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Big fancy header
print_header() {
    local title="$1"
    local width="${2:-$(get_term_width)}"
    local inner_width=$((width - 2))

    echo ""
    cprint "$T_PRIMARY" "$BOX_TL$(repeat_char "$BOX_H" "$inner_width")$BOX_TR"

    local padded_title
    padded_title=$(center_text "$title" "$inner_width")
    echo -e "${T_PRIMARY}${BOX_V}${RST}${BWHITE}${padded_title}${RST}${T_PRIMARY}${BOX_V}${RST}"

    cprint "$T_PRIMARY" "$BOX_BL$(repeat_char "$BOX_H" "$inner_width")$BOX_BR"
    echo ""
}

# Section header (lighter)
print_section() {
    local title="$1"
    local width="${2:-$(get_term_width)}"

    echo ""
    echo -e "${T_SECONDARY}${LBOX_TL}$(repeat_char "$LBOX_H" 2) ${BWHITE}${title} ${T_SECONDARY}$(repeat_char "$LBOX_H" $((width - ${#title} - 6)))${LBOX_TR}${RST}"
}

# Section footer
print_section_end() {
    local width="${1:-$(get_term_width)}"
    echo -e "${T_SECONDARY}${LBOX_BL}$(repeat_char "$LBOX_H" $((width - 2)))${LBOX_BR}${RST}"
    echo ""
}

# Simple divider line
print_divider() {
    local char="${1:-─}"
    local width="${2:-$(get_term_width)}"
    cprint "$T_DIM" "$(repeat_char "$char" "$width")"
}

# ═══════════════════════════════════════════════════════════════════════════════
# STATUS MESSAGES
# ═══════════════════════════════════════════════════════════════════════════════

# Success message
msg_ok() {
    echo -e "${T_SUCCESS}${SYM_CHECK}${RST} $*"
}

# Error message
msg_err() {
    echo -e "${T_ERROR}${SYM_CROSS}${RST} $*"
}

# Warning message
msg_warn() {
    echo -e "${T_WARN}${SYM_WARN}${RST} $*"
}

# Info message
msg_info() {
    echo -e "${T_DIM}${SYM_ARROW}${RST} $*"
}

# Bullet point
msg_bullet() {
    echo -e "  ${T_DIM}${SYM_BULLET}${RST} $*"
}

# Arrow point
msg_arrow() {
    echo -e "  ${T_SECONDARY}${SYM_ARROW}${RST} $*"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PROGRESS INDICATORS
# ═══════════════════════════════════════════════════════════════════════════════

# Spinner - starts in background, returns PID
# Usage: start_spinner "Loading..." ; do_stuff ; stop_spinner $!
SPINNER_PID=""

start_spinner() {
    local msg="${1:-Working}"
    cursor_hide
    (
        local i=0
        while true; do
            local frame="${SPINNER_FRAMES[$i]}"
            echo -en "\r${T_SECONDARY}${frame}${RST} ${msg}${SYM_ELLIPSIS}   "
            i=$(( (i + 1) % ${#SPINNER_FRAMES[@]} ))
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
}

stop_spinner() {
    local result="${1:-0}"
    local msg="${2:-Done}"

    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null
    fi
    SPINNER_PID=""

    clear_line
    cursor_show

    if [[ "$result" == "0" ]]; then
        msg_ok "$msg"
    else
        msg_err "$msg"
    fi
}

# Dot animation (simpler, inline)
# Usage: print_dots "Checking" 3
print_dots() {
    local msg="$1"
    local count="${2:-3}"

    cprintn "" "$msg"
    for ((i=0; i<count; i++)); do
        sleep 0.3
        cprintn "$T_DIM" "."
    done
    echo ""
}

# Progress bar
# Usage: progress_bar 50 100 "Downloading"
progress_bar() {
    local current="$1"
    local total="$2"
    local label="${3:-Progress}"
    local width="${4:-40}"

    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    local bar=""
    bar+="${T_SUCCESS}$(repeat_char "$SYM_BLOCK" "$filled")"
    bar+="${T_DIM}$(repeat_char "$SYM_LIGHT" "$empty")"

    echo -en "\r${label}: ${bar}${RST} ${percent}%"

    if [[ "$current" -ge "$total" ]]; then
        echo ""
    fi
}

# Step indicator
# Usage: print_step 1 5 "Checking prerequisites"
print_step() {
    local current="$1"
    local total="$2"
    local msg="$3"

    echo -e "${T_DIM}[${RST}${T_SECONDARY}${current}${RST}${T_DIM}/${total}]${RST} ${msg}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# BOXES AND PANELS
# ═══════════════════════════════════════════════════════════════════════════════

# Info box
print_box() {
    local title="$1"
    local content="$2"
    local color="${3:-$T_INFO}"
    local width="${4:-60}"

    local inner=$((width - 4))

    echo -e "${color}${LBOX_TL}$(repeat_char "$LBOX_H" 2) ${title} $(repeat_char "$LBOX_H" $((inner - ${#title} - 1)))${LBOX_TR}${RST}"

    # Handle multi-line content
    while IFS= read -r line; do
        printf "${color}${LBOX_V}${RST} %-${inner}s ${color}${LBOX_V}${RST}\n" "$line"
    done <<< "$content"

    echo -e "${color}${LBOX_BL}$(repeat_char "$LBOX_H" $((width - 2)))${LBOX_BR}${RST}"
}

# Key-value display
print_kv() {
    local key="$1"
    local value="$2"
    local key_width="${3:-20}"

    printf "  ${T_DIM}%-${key_width}s${RST} ${BWHITE}%s${RST}\n" "${key}:" "$value"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PROMPTS AND INPUT
# ═══════════════════════════════════════════════════════════════════════════════

# Yes/No prompt
# Usage: if prompt_yn "Continue?" "y"; then ...
prompt_yn() {
    local msg="$1"
    local default="${2:-n}"
    local response

    local hint="[y/N]"
    [[ "$default" == "y" ]] && hint="[Y/n]"

    echo -en "${T_WARN}?${RST} ${msg} ${T_DIM}${hint}${RST} "
    read -r response

    response="${response:-$default}"
    [[ "${response,,}" == "y" || "${response,,}" == "yes" ]]
}

# Text prompt
prompt_text() {
    local msg="$1"
    local default="$2"
    local response

    local hint=""
    [[ -n "$default" ]] && hint=" ${T_DIM}[${default}]${RST}"

    echo -en "${T_INFO}?${RST} ${msg}${hint} "
    read -r response

    echo "${response:-$default}"
}

# Selection menu
# Usage: choice=$(prompt_select "Choose:" "Option 1" "Option 2" "Option 3")
prompt_select() {
    local prompt="$1"
    shift
    local options=("$@")

    echo -e "${T_INFO}?${RST} ${prompt}"

    local i=1
    for opt in "${options[@]}"; do
        echo -e "  ${T_SECONDARY}${i})${RST} ${opt}"
        ((i++))
    done

    local choice
    echo -en "${T_DIM}Enter choice [1-${#options[@]}]:${RST} "
    read -r choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
        echo "${options[$((choice-1))]}"
    else
        echo ""
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CLEANUP
# ═══════════════════════════════════════════════════════════════════════════════

# Ensure cursor is shown on exit
trap 'cursor_show' EXIT
