#!/bin/bash
# =============================================================================
# Screen Session Status Checker
# =============================================================================
# Quick status check for one or more screen sessions
#
# Usage:
#   ./scripts/status_screen.sh [screen_name] [screen_name2] ...
#   ./scripts/status_screen.sh  # Check all active sessions
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get list of screen sessions to check
if [ $# -eq 0 ]; then
    # Check all active screen sessions
    SCREEN_NAMES=$(screen -list 2>/dev/null | grep -oP '\K[^\s]+(?=\s+\(Detached\)|\s+\(Attached\))' || echo "")
    if [ -z "$SCREEN_NAMES" ]; then
        echo -e "${YELLOW}No active screen sessions found${NC}"
        exit 0
    fi
else
    SCREEN_NAMES="$@"
fi

STATUS_DIR="$PROJECT_ROOT/logs/status"
LOGS_DIR="$PROJECT_ROOT/logs/screen_sessions"

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Screen Session Status${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

for SCREEN_NAME in $SCREEN_NAMES; do
    echo -e "${CYAN}Session: $SCREEN_NAME${NC}"
    
    # Check if screen session exists
    if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
        SCREEN_STATUS=$(screen -list 2>/dev/null | grep "$SCREEN_NAME" | grep -oP '\([^)]+\)' | head -1)
        if echo "$SCREEN_STATUS" | grep -q "Attached"; then
            echo -e "  Screen: ${GREEN}Running (Attached)${NC}"
        else
            echo -e "  Screen: ${GREEN}Running (Detached)${NC}"
        fi
    else
        echo -e "  Screen: ${RED}Not Running${NC}"
        echo ""
        continue
    fi
    
    # Check status file
    STATUS_FILE="$STATUS_DIR/${SCREEN_NAME}.status"
    if [ -f "$STATUS_FILE" ]; then
        STATUS=$(python3 -c "import json, sys; d=json.load(open('$STATUS_FILE')); print(d.get('status', 'unknown'))" 2>/dev/null || echo "unknown")
        MESSAGE=$(python3 -c "import json, sys; d=json.load(open('$STATUS_FILE')); print(d.get('message', ''))" 2>/dev/null || echo "")
        
        case "$STATUS" in
            "running")
                echo -e "  Process: ${GREEN}Running${NC}"
                ;;
            "success")
                echo -e "  Process: ${GREEN}Completed Successfully${NC}"
                ;;
            "failed"|"error")
                echo -e "  Process: ${RED}$STATUS${NC}"
                ;;
            *)
                echo -e "  Process: ${YELLOW}$STATUS${NC}"
                ;;
        esac
        
        if [ -n "$MESSAGE" ]; then
            echo "  Message: $MESSAGE"
        fi
    else
        echo -e "  Process: ${YELLOW}Status unknown${NC}"
    fi
    
    # Find latest log directory
    LATEST_LOG_DIR=$(ls -td "$LOGS_DIR/${SCREEN_NAME}_"* 2>/dev/null | head -1)
    if [ -n "$LATEST_LOG_DIR" ]; then
        MAIN_LOG="$LATEST_LOG_DIR/main.log"
        if [ -f "$MAIN_LOG" ]; then
            LOG_SIZE=$(du -h "$MAIN_LOG" | cut -f1)
            LOG_LINES=$(wc -l < "$MAIN_LOG" 2>/dev/null || echo "0")
            echo "  Log: $MAIN_LOG ($LOG_SIZE, $LOG_LINES lines)"
        fi
    fi
    
    echo ""
done

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"

