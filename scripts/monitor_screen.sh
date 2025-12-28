#!/bin/bash
# =============================================================================
# Screen Session Monitor
# =============================================================================
# Monitors one or more screen sessions, showing status, progress, and logs
#
# Usage:
#   ./scripts/monitor_screen.sh [screen_name] [screen_name2] ...
#   ./scripts/monitor_screen.sh  # Monitor all active sessions
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

REFRESH_INTERVAL=10

# Get list of screen sessions to monitor
if [ $# -eq 0 ]; then
    # Monitor all active screen sessions
    SCREEN_NAMES=$(screen -list 2>/dev/null | grep -oP '\K[^\s]+(?=\s+\(Detached\)|\s+\(Attached\))' || echo "")
    if [ -z "$SCREEN_NAMES" ]; then
        echo -e "${YELLOW}No active screen sessions found${NC}"
        exit 0
    fi
else
    SCREEN_NAMES="$@"
fi

# Trap Ctrl+C to exit cleanly
trap 'echo ""; echo "Monitoring stopped."; exit 0' INT

while true; do
    clear
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Screen Session Monitor${NC}"
    echo -e "${CYAN}  (Refreshing every ${REFRESH_INTERVAL}s - Press Ctrl+C to stop)${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    STATUS_DIR="$PROJECT_ROOT/logs/status"
    LOGS_DIR="$PROJECT_ROOT/logs/screen_sessions"
    
    for SCREEN_NAME in $SCREEN_NAMES; do
        echo -e "${MAGENTA}──────────────────────────────────────────────────────────────────────────${NC}"
        echo -e "${CYAN}Session: $SCREEN_NAME${NC}"
        echo -e "${MAGENTA}──────────────────────────────────────────────────────────────────────────${NC}"
        
        # Check if screen session exists
        if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
            SCREEN_STATUS=$(screen -list 2>/dev/null | grep "$SCREEN_NAME" | grep -oP '\([^)]+\)' | head -1)
            if echo "$SCREEN_STATUS" | grep -q "Attached"; then
                echo -e "${GREEN}  Status: Running (Attached)${NC}"
            else
                echo -e "${GREEN}  Status: Running (Detached)${NC}"
            fi
        else
            echo -e "${RED}  Status: Not Running${NC}"
            echo ""
            continue
        fi
        
        # Find latest log directory for this session
        LATEST_LOG_DIR=$(ls -td "$LOGS_DIR/${SCREEN_NAME}_"* 2>/dev/null | head -1)
        
        if [ -n "$LATEST_LOG_DIR" ]; then
            # Read status file
            STATUS_FILE="$STATUS_DIR/${SCREEN_NAME}.status"
            if [ -f "$STATUS_FILE" ]; then
                STATUS=$(python3 -c "import json, sys; d=json.load(open('$STATUS_FILE')); print(d.get('status', 'unknown'))" 2>/dev/null || echo "unknown")
                MESSAGE=$(python3 -c "import json, sys; d=json.load(open('$STATUS_FILE')); print(d.get('message', ''))" 2>/dev/null || echo "")
                TIMESTAMP=$(python3 -c "import json, sys; d=json.load(open('$STATUS_FILE')); print(d.get('timestamp', ''))" 2>/dev/null || echo "")
                
                case "$STATUS" in
                    "running")
                        echo -e "${GREEN}  Process Status: Running${NC}"
                        ;;
                    "success")
                        echo -e "${GREEN}  Process Status: Completed Successfully${NC}"
                        ;;
                    "failed")
                        echo -e "${RED}  Process Status: Failed${NC}"
                        ;;
                    "error")
                        echo -e "${RED}  Process Status: Error${NC}"
                        ;;
                    *)
                        echo -e "${YELLOW}  Process Status: $STATUS${NC}"
                        ;;
                esac
                
                if [ -n "$MESSAGE" ]; then
                    echo "  Message: $MESSAGE"
                fi
                if [ -n "$TIMESTAMP" ]; then
                    echo "  Last Update: $TIMESTAMP"
                fi
            fi
            
            # Show log file info
            MAIN_LOG="$LATEST_LOG_DIR/main.log"
            if [ -f "$MAIN_LOG" ]; then
                LOG_SIZE=$(du -h "$MAIN_LOG" | cut -f1)
                LOG_LINES=$(wc -l < "$MAIN_LOG" 2>/dev/null || echo "0")
                echo "  Log: $MAIN_LOG ($LOG_SIZE, $LOG_LINES lines)"
                
                # Show recent log entries
                echo ""
                echo -e "${BLUE}  Recent Log Entries:${NC}"
                tail -3 "$MAIN_LOG" 2>/dev/null | sed 's/^/    /' || echo "    (no log entries yet)"
            fi
            
            # Show PID if available
            PID_FILE="$LATEST_LOG_DIR/pid"
            if [ -f "$PID_FILE" ]; then
                PID=$(cat "$PID_FILE" 2>/dev/null)
                if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
                    echo "  PID: $PID (running)"
                else
                    echo "  PID: $PID (not running)"
                fi
            fi
        else
            echo -e "${YELLOW}  No log directory found${NC}"
        fi
        
        echo ""
    done
    
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Commands:"
    echo "    Attach: screen -r <session_name>"
    echo "    View logs: tail -f logs/screen_sessions/<session_name>_*/main.log"
    echo "    Kill: screen -S <session_name> -X quit"
    echo ""
    echo "  Next refresh in ${REFRESH_INTERVAL} seconds..."
    echo "  Press Ctrl+C to stop monitoring"
    
    sleep "$REFRESH_INTERVAL"
done

