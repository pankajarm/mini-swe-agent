#!/bin/bash
# =============================================================================
# Generic Screen Session Runner with Full Logging
# =============================================================================
# Runs any command in a detached screen session with comprehensive logging
# All output is redirected to timestamped log files
#
# Usage:
#   ./scripts/run_in_screen.sh <screen_name> <command> [args...]
#
# Example:
#   ./scripts/run_in_screen.sh hybrid-benchmark "./run_azure_benchmark.sh 64 verified"
#   ./scripts/run_in_screen.sh analysis "python comprehensive_analysis.py"
#
# Features:
#   - Detached screen session (safe to disconnect)
#   - All output logged to files
#   - Automatic log rotation
#   - Error tracking
#   - Status file for monitoring
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
if [ $# -lt 2 ]; then
    echo -e "${RED}Usage: $0 <screen_name> <command> [args...]${NC}"
    echo ""
    echo "Examples:"
    echo "  $0 hybrid-benchmark './run_azure_benchmark.sh 64 verified'"
    echo "  $0 analysis 'python comprehensive_analysis.py'"
    exit 1
fi

SCREEN_NAME="$1"
shift
COMMAND="$*"

# Create directories
LOGS_DIR="$PROJECT_ROOT/logs/screen_sessions"
STATUS_DIR="$PROJECT_ROOT/logs/status"
mkdir -p "$LOGS_DIR" "$STATUS_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SESSION_LOG_DIR="$LOGS_DIR/${SCREEN_NAME}_${TIMESTAMP}"
mkdir -p "$SESSION_LOG_DIR"

# Log files
MAIN_LOG="$SESSION_LOG_DIR/main.log"
STDOUT_LOG="$SESSION_LOG_DIR/stdout.log"
STDERR_LOG="$SESSION_LOG_DIR/stderr.log"
STATUS_FILE="$STATUS_DIR/${SCREEN_NAME}.status"
PID_FILE="$SESSION_LOG_DIR/pid"

# Check if screen session already exists
if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${YELLOW}⚠ Warning: Screen session '$SCREEN_NAME' already exists${NC}"
    echo ""
    echo "Options:"
    echo "  1. Attach to it:  screen -r $SCREEN_NAME"
    echo "  2. Kill it first: screen -S $SCREEN_NAME -X quit"
    echo "  3. Use different name"
    echo ""
    read -p "Kill existing session and start new? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        screen -S "$SCREEN_NAME" -X quit 2>/dev/null || true
        sleep 1
    else
        echo "Exiting. Attach to existing session with: screen -r $SCREEN_NAME"
        exit 0
    fi
fi

# Create wrapper script that runs in screen
WRAPPER_SCRIPT="$SESSION_LOG_DIR/wrapper.sh"

cat > "$WRAPPER_SCRIPT" << EOFWRAPPER
#!/bin/bash
# Wrapper script that runs inside screen session
# All output is logged to files

set -e

SCRIPT_DIR="$PROJECT_ROOT"
cd "\$SCRIPT_DIR"

# Log files
MAIN_LOG="$MAIN_LOG"
STDOUT_LOG="$STDOUT_LOG"
STDERR_LOG="$STDERR_LOG"
STATUS_FILE="$STATUS_FILE"
PID_FILE="$PID_FILE"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$MAIN_LOG"
}

# Function to update status
update_status() {
    echo "{\"status\": \"\$1\", \"timestamp\": \"$(date -Iseconds)\", \"message\": \"\$2\"}" > "\$STATUS_FILE"
}

# Trap to log on exit
trap 'EXIT_CODE=\$?; update_status "completed" "Process exited with code: \$EXIT_CODE"; log "Process exited with code: \$EXIT_CODE"; exit \$EXIT_CODE' EXIT
trap 'update_status "error" "Process killed/interrupted"; log "Process killed/interrupted"' INT TERM

# Write PID
echo \$\$ > "\$PID_FILE"

# Initial status
update_status "running" "Process started"
log "═══════════════════════════════════════════════════════════════════════════"
log "Screen Session: $SCREEN_NAME"
log "Command: $COMMAND"
log "Start time: $(date)"
log "PID: \$\$"
log "Log directory: $SESSION_LOG_DIR"
log "═══════════════════════════════════════════════════════════════════════════"
log ""

# Run the command with all output logged
log "Executing command..."
update_status "running" "Executing: $COMMAND"

# Execute command, logging stdout and stderr separately
eval "$COMMAND" > >(tee -a "\$STDOUT_LOG" "\$MAIN_LOG") 2> >(tee -a "\$STDERR_LOG" "\$MAIN_LOG" >&2)

EXIT_CODE=\$?

log ""
log "═══════════════════════════════════════════════════════════════════════════"
log "Command completed with exit code: \$EXIT_CODE"
log "End time: $(date)"
log "═══════════════════════════════════════════════════════════════════════════"

# Final status
if [ \$EXIT_CODE -eq 0 ]; then
    update_status "success" "Command completed successfully"
else
    update_status "failed" "Command failed with exit code: \$EXIT_CODE"
fi

# Keep screen alive to view results
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Process complete. Press Enter to close this screen session..."
echo "  Logs saved to: $SESSION_LOG_DIR"
echo "═══════════════════════════════════════════════════════════════════════════"
read
EOFWRAPPER

chmod +x "$WRAPPER_SCRIPT"

# Launch screen session
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Launching Screen Session${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Screen Name:${NC} $SCREEN_NAME"
echo -e "${GREEN}Command:${NC} $COMMAND"
echo -e "${GREEN}Log Directory:${NC} $SESSION_LOG_DIR"
echo ""

screen -dmS "$SCREEN_NAME" bash "$WRAPPER_SCRIPT"

sleep 2

# Verify screen started
if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${GREEN}✓ Screen session started successfully${NC}"
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo "  Useful Commands:"
    echo ""
    echo "  Attach to session:     screen -r $SCREEN_NAME"
    echo "  Detach from session:   Ctrl+A, then D"
    echo "  Monitor progress:     ./scripts/monitor_screen.sh $SCREEN_NAME"
    echo "  Check status:         ./scripts/status_screen.sh $SCREEN_NAME"
    echo "  View logs:            tail -f $SESSION_LOG_DIR/main.log"
    echo "  Kill session:         screen -S $SCREEN_NAME -X quit"
    echo ""
    echo "  Log files:"
    echo "    Main log:   $SESSION_LOG_DIR/main.log"
    echo "    Stdout:     $SESSION_LOG_DIR/stdout.log"
    echo "    Stderr:     $SESSION_LOG_DIR/stderr.log"
    echo "    Status:     $STATUS_FILE"
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
else
    echo -e "${RED}✗ Failed to start screen session${NC}"
    exit 1
fi

