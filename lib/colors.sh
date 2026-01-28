#!/bin/bash
# MBTC-DASH - Color and Style Definitions
# Source this file to get access to colors and styling

# ═══════════════════════════════════════════════════════════════════════════════
# COLOR DEFINITIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Reset
export RST='\033[0m'

# Regular Colors
export BLACK='\033[0;30m'
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[0;37m'

# Bold Colors
export BBLACK='\033[1;30m'
export BRED='\033[1;31m'
export BGREEN='\033[1;32m'
export BYELLOW='\033[1;33m'
export BBLUE='\033[1;34m'
export BPURPLE='\033[1;35m'
export BCYAN='\033[1;36m'
export BWHITE='\033[1;37m'

# Dim Colors
export DBLACK='\033[2;30m'
export DRED='\033[2;31m'
export DGREEN='\033[2;32m'
export DYELLOW='\033[2;33m'
export DBLUE='\033[2;34m'
export DPURPLE='\033[2;35m'
export DCYAN='\033[2;36m'
export DWHITE='\033[2;37m'

# Background Colors
export BG_BLACK='\033[40m'
export BG_RED='\033[41m'
export BG_GREEN='\033[42m'
export BG_YELLOW='\033[43m'
export BG_BLUE='\033[44m'
export BG_PURPLE='\033[45m'
export BG_CYAN='\033[46m'
export BG_WHITE='\033[47m'

# Special
export BOLD='\033[1m'
export DIM='\033[2m'
export ITALIC='\033[3m'
export UNDERLINE='\033[4m'
export BLINK='\033[5m'
export REVERSE='\033[7m'

# ═══════════════════════════════════════════════════════════════════════════════
# EXTENDED BLUE PALETTE (256 colors)
# ═══════════════════════════════════════════════════════════════════════════════

export BLUE_DARK='\033[38;5;17m'
export BLUE_NAVY='\033[38;5;18m'
export BLUE_MED='\033[38;5;20m'
export BLUE_ROYAL='\033[38;5;21m'
export BLUE_BRIGHT='\033[38;5;27m'
export BLUE_DODGER='\033[38;5;33m'
export BLUE_SKY='\033[38;5;39m'
export BLUE_STEEL='\033[38;5;67m'
export BLUE_LIGHT='\033[38;5;75m'
export BLUE_ICE='\033[38;5;117m'

# Bold blues
export BBLUE_BRIGHT='\033[1;38;5;27m'
export BBLUE_DODGER='\033[1;38;5;33m'
export BBLUE_SKY='\033[1;38;5;39m'
export BBLUE_LIGHT='\033[1;38;5;75m'

# ═══════════════════════════════════════════════════════════════════════════════
# UNICODE BOX DRAWING CHARACTERS
# ═══════════════════════════════════════════════════════════════════════════════

export BOX_TL='╔'
export BOX_TR='╗'
export BOX_BL='╚'
export BOX_BR='╝'
export BOX_H='═'
export BOX_V='║'
export BOX_LT='╠'
export BOX_RT='╣'
export BOX_TT='╦'
export BOX_BT='╩'
export BOX_X='╬'

# Light box (single line)
export LBOX_TL='┌'
export LBOX_TR='┐'
export LBOX_BL='└'
export LBOX_BR='┘'
export LBOX_H='─'
export LBOX_V='│'
export LBOX_LT='├'
export LBOX_RT='┤'

# ═══════════════════════════════════════════════════════════════════════════════
# SYMBOLS
# ═══════════════════════════════════════════════════════════════════════════════

export SYM_CHECK='✓'
export SYM_CROSS='✗'
export SYM_WARN='⚠'
export SYM_INFO='ℹ'
export SYM_ARROW='→'
export SYM_BULLET='•'
export SYM_BITCOIN='₿'
export SYM_BLOCK='█'
export SYM_LIGHT='░'
export SYM_MED='▒'
export SYM_DARK='▓'
export SYM_DOT='·'
export SYM_ELLIPSIS='…'
export SYM_GEAR='⚙'
export SYM_LOCK='🔒'
export SYM_GLOBE='🌐'

# Spinner frames
export SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
export DOT_FRAMES=('   ' '.  ' '.. ' '...')

# ═══════════════════════════════════════════════════════════════════════════════
# THEME - Blue (MBTC-DASH)
# ═══════════════════════════════════════════════════════════════════════════════

# Primary theme colors - BLUE based
export T_PRIMARY="$BBLUE_DODGER"        # Main headers, banners
export T_SECONDARY="$BBLUE_SKY"         # Section headers, accents
export T_ACCENT="$BLUE_LIGHT"           # Highlights
export T_SUCCESS="$BGREEN"              # Success messages, checkmarks
export T_ERROR="$BRED"                  # Errors, failures
export T_WARN="$BYELLOW"                # Warnings
export T_INFO="$BCYAN"                  # Info messages
export T_DIM="$DWHITE"                  # Dimmed text, hints
export T_PINK="$BPURPLE"                # Occasional accent (sparingly)

# Table colors
export T_TABLE_HEADER="$BBLUE_BRIGHT"   # Table headers
export T_TABLE_BORDER="$BLUE_STEEL"     # Table borders
export T_TABLE_ROW="$WHITE"             # Table row text
export T_TABLE_ALT="$DWHITE"            # Alternating rows
