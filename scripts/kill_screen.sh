#!/bin/bash
# =============================================================================
# Kill Screen Session(s)
# =============================================================================
# Safely kill one or more screen sessions
#
# Usage:
#   ./scripts/kill_screen.sh <screen_name> [screen_name2] ...
# =============================================================================

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ $# -eq 0 ]; then
    echo -e "${RED}Usage: $0 <screen_name> [screen_name2] ...${NC}"
    exit 1
fi

for SCREEN_NAME in "$@"; do
    if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
        echo -e "${YELLOW}Killing screen session: $SCREEN_NAME${NC}"
        screen -S "$SCREEN_NAME" -X quit
        sleep 1
        
        if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
            echo -e "${RED}✗ Failed to kill $SCREEN_NAME${NC}"
        else
            echo -e "${GREEN}✓ Killed $SCREEN_NAME${NC}"
        fi
    else
        echo -e "${YELLOW}Screen session '$SCREEN_NAME' not found${NC}"
    fi
done

