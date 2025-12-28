# Screen Session Execution System

Complete system for running processes in detached screen sessions with comprehensive logging and monitoring.

## Quick Start

```bash
# Run any command in a screen session
./scripts/run_in_screen.sh my-task "python my_script.py"

# Monitor progress
./scripts/monitor_screen.sh my-task

# Check status
./scripts/status_screen.sh my-task

# Kill when done
./scripts/kill_screen.sh my-task
```

## System Overview

### Components

1. **`run_in_screen.sh`** - Generic runner for any command
2. **`monitor_screen.sh`** - Live monitoring dashboard
3. **`status_screen.sh`** - Quick status checker
4. **`kill_screen.sh`** - Safe session termination

### Features

✅ **Detached Execution**: Processes run in screen sessions that survive SSH disconnects  
✅ **Full Logging**: All output (stdout, stderr) logged to timestamped files  
✅ **Status Tracking**: JSON status files for programmatic monitoring  
✅ **Independent Failures**: Each session isolated, failures don't affect others  
✅ **Safe Disconnect**: Can disconnect from machine without interrupting tasks  
✅ **Easy Debugging**: Comprehensive logs and status files for troubleshooting  

## Directory Structure

```
logs/
├── screen_sessions/
│   └── <session_name>_<timestamp>/
│       ├── main.log      # Combined stdout + stderr
│       ├── stdout.log    # Standard output
│       ├── stderr.log    # Standard error
│       ├── pid           # Process ID
│       └── wrapper.sh    # Wrapper script
└── status/
    └── <session_name>.status  # JSON status file
```

## Usage Examples

### Example 1: Run Benchmark

```bash
# Start benchmark
./scripts/run_in_screen.sh hybrid-benchmark \
  "./run_azure_benchmark.sh 64 verified"

# Monitor (in another terminal or after disconnect)
./scripts/monitor_screen.sh hybrid-benchmark

# View logs
tail -f logs/screen_sessions/hybrid-benchmark_*/main.log

# When complete
./scripts/kill_screen.sh hybrid-benchmark
```

### Example 2: Run Analysis

```bash
# Start analysis
./scripts/run_in_screen.sh analysis \
  "python comprehensive_analysis.py"

# Check status later
./scripts/status_screen.sh analysis

# View results
cat logs/screen_sessions/analysis_*/stdout.log
```

### Example 3: Multiple Sessions

```bash
# Start multiple tasks
./scripts/run_in_screen.sh task1 "python script1.py"
./scripts/run_in_screen.sh task2 "python script2.py"
./scripts/run_in_screen.sh task3 "python script3.py"

# Monitor all
./scripts/monitor_screen.sh

# Check all status
./scripts/status_screen.sh
```

## Monitoring

### Live Monitoring

```bash
# Monitor specific sessions (refreshes every 10s)
./scripts/monitor_screen.sh session1 session2

# Monitor all active sessions
./scripts/monitor_screen.sh
```

**Output shows:**
- Screen session status (running/attached/detached)
- Process status (running/success/failed)
- Recent log entries
- Log file sizes and line counts
- Process IDs

### Quick Status Check

```bash
# One-time status check
./scripts/status_screen.sh session1 session2

# Check all sessions
./scripts/status_screen.sh
```

## Logging

### Log Files

Each session creates three log files:

1. **`main.log`** - Combined stdout + stderr with timestamps
2. **`stdout.log`** - Standard output only
3. **`stderr.log`** - Standard error only

### Viewing Logs

```bash
# Find latest log directory
LATEST=$(ls -td logs/screen_sessions/my-session_* | head -1)

# View main log
tail -f "$LATEST/main.log"

# View only errors
tail -f "$LATEST/stderr.log"

# View last 100 lines
tail -100 "$LATEST/main.log"

# Search logs
grep "error" "$LATEST/main.log"
```

## Status Files

Status files are JSON format in `logs/status/<session_name>.status`:

```json
{
  "status": "running|success|failed|error|completed",
  "timestamp": "2025-01-27T10:30:45",
  "message": "Process started"
}
```

### Reading Status Programmatically

```python
import json

with open("logs/status/my-session.status") as f:
    status = json.load(f)
    print(status["status"])  # "running", "success", etc.
```

## Error Handling

### Debugging Failed Sessions

1. **Check Status**
   ```bash
   ./scripts/status_screen.sh failed-session
   ```

2. **View Error Log**
   ```bash
   tail -100 logs/screen_sessions/failed-session_*/stderr.log
   ```

3. **Check Main Log**
   ```bash
   tail -100 logs/screen_sessions/failed-session_*/main.log
   ```

4. **Attach to Session** (if still running)
   ```bash
   screen -r failed-session
   ```

### Restarting Failed Sessions

```bash
# Kill failed session
./scripts/kill_screen.sh failed-session

# Restart with same command
./scripts/run_in_screen.sh failed-session "./original-command.sh"
```

## Screen Commands

### Attach to Session

```bash
# Attach to see live output
screen -r session-name

# Detach: Ctrl+A, then D
```

### List All Sessions

```bash
screen -list
```

### Kill Session Manually

```bash
screen -S session-name -X quit
```

## Best Practices

1. **Use Descriptive Names**
   ```bash
   # Good
   ./scripts/run_in_screen.sh hybrid-benchmark-verified "./run.sh"
   
   # Bad
   ./scripts/run_in_screen.sh test "./run.sh"
   ```

2. **Check Before Starting**
   ```bash
   ./scripts/status_screen.sh my-session
   ```

3. **Monitor Long Tasks**
   ```bash
   ./scripts/monitor_screen.sh my-session
   ```

4. **Clean Up Completed Sessions**
   ```bash
   ./scripts/kill_screen.sh completed-session
   ```

5. **Use Logs for Debugging**
   - Always check `stderr.log` first for errors
   - Use `main.log` for full context
   - Check status file for process state

## Integration with Existing Scripts

### Running Hybrid Agent Benchmark

```bash
# Use convenience script
./run_hybrid_benchmark.sh 64 verified

# Or use generic runner
./scripts/run_in_screen.sh hybrid-benchmark \
  "./run_azure_benchmark.sh 64 verified"
```

### Running Analysis

```bash
./scripts/run_in_screen.sh framework-analysis \
  "python comprehensive_analysis.py"
```

## Troubleshooting

### Session Not Starting
- Check if screen is installed: `which screen`
- Check if session name already exists
- Check logs in `logs/screen_sessions/`

### Can't Attach
- Session may have exited: Check status
- Session attached elsewhere: Use `screen -x` instead

### Logs Not Appearing
- Wait a few seconds for initialization
- Check process is running: `./scripts/status_screen.sh`
- Check `logs/` directory permissions

### Process Died
- Check `stderr.log` for errors
- Check system resources: `free -h`, `df -h`
- Check system logs: `dmesg | tail`

## Summary

This system provides:

- ✅ Safe execution that survives disconnects
- ✅ Comprehensive logging for debugging
- ✅ Easy monitoring and status checking
- ✅ Independent, isolated sessions
- ✅ Simple, consistent interface

All processes run in screen sessions with full logging, making it safe to disconnect and easy to debug any issues.

