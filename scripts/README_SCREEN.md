# Screen Session Management System

This directory contains scripts for running processes in detached screen sessions with comprehensive logging and monitoring.

## Features

- ✅ **Detached Execution**: Run processes in screen sessions that survive disconnects
- ✅ **Full Logging**: All output (stdout, stderr) logged to timestamped files
- ✅ **Status Tracking**: JSON status files for easy monitoring
- ✅ **Independent Failures**: Each session is isolated and debuggable
- ✅ **Safe Disconnect**: Can disconnect from machine without interrupting tasks

## Scripts

### `run_in_screen.sh`
Generic runner that executes any command in a screen session with full logging.

**Usage:**
```bash
./scripts/run_in_screen.sh <screen_name> <command> [args...]
```

**Examples:**
```bash
# Run benchmark
./scripts/run_in_screen.sh hybrid-benchmark "./run_azure_benchmark.sh 64 verified"

# Run analysis
./scripts/run_in_screen.sh analysis "python comprehensive_analysis.py"

# Run with arguments
./scripts/run_in_screen.sh test-bench "./run_azure_benchmark.sh 32 verified '0:10'"
```

**Features:**
- Creates detached screen session
- Logs all output to `logs/screen_sessions/<screen_name>_<timestamp>/`
- Creates status file in `logs/status/<screen_name>.status`
- Handles existing sessions gracefully

### `monitor_screen.sh`
Live monitoring dashboard for screen sessions.

**Usage:**
```bash
# Monitor specific sessions
./scripts/monitor_screen.sh session1 session2

# Monitor all active sessions
./scripts/monitor_screen.sh
```

**Features:**
- Refreshes every 10 seconds
- Shows session status (running/attached/detached)
- Displays process status (running/success/failed)
- Shows recent log entries
- Displays log file sizes and line counts

### `status_screen.sh`
Quick status check for screen sessions.

**Usage:**
```bash
# Check specific sessions
./scripts/status_screen.sh session1 session2

# Check all active sessions
./scripts/status_screen.sh
```

**Features:**
- One-time status check (no refresh loop)
- Shows session and process status
- Displays log file information

### `kill_screen.sh`
Safely kill screen sessions.

**Usage:**
```bash
./scripts/kill_screen.sh session1 session2 session3
```

## Directory Structure

```
logs/
├── screen_sessions/
│   ├── <session_name>_<timestamp>/
│   │   ├── main.log          # Combined stdout + stderr
│   │   ├── stdout.log        # Standard output only
│   │   ├── stderr.log        # Standard error only
│   │   ├── pid               # Process ID
│   │   └── wrapper.sh        # Wrapper script
│   └── ...
└── status/
    ├── <session_name>.status # JSON status file
    └── ...
```

## Status File Format

Status files are JSON with the following structure:

```json
{
  "status": "running|success|failed|error|completed",
  "timestamp": "2025-01-27T10:30:45",
  "message": "Process started"
}
```

## Common Workflows

### Starting a Long-Running Task

```bash
# Start benchmark in screen
./scripts/run_in_screen.sh my-benchmark "./run_azure_benchmark.sh 64 verified"

# Disconnect safely - process continues running
# Can reconnect later with: screen -r my-benchmark
```

### Monitoring Progress

```bash
# Start monitoring (refreshes every 10s)
./scripts/monitor_screen.sh my-benchmark

# Or check status once
./scripts/status_screen.sh my-benchmark
```

### Viewing Logs

```bash
# Find latest log directory
LATEST=$(ls -td logs/screen_sessions/my-benchmark_* | head -1)

# View main log
tail -f "$LATEST/main.log"

# View only errors
tail -f "$LATEST/stderr.log"
```

### Attaching to Session

```bash
# Attach to see live output
screen -r my-benchmark

# Detach: Ctrl+A, then D
```

### Killing a Session

```bash
# Kill specific session
./scripts/kill_screen.sh my-benchmark

# Or manually
screen -S my-benchmark -X quit
```

## Error Handling

### Independent Failures
Each screen session runs independently. If one fails, others continue running.

### Debugging Failed Sessions

1. Check status:
   ```bash
   ./scripts/status_screen.sh failed-session
   ```

2. View error log:
   ```bash
   tail -100 logs/screen_sessions/failed-session_*/stderr.log
   ```

3. Check main log:
   ```bash
   tail -100 logs/screen_sessions/failed-session_*/main.log
   ```

4. Attach to session (if still running):
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

## Best Practices

1. **Use Descriptive Names**: Use clear, descriptive screen session names
   ```bash
   # Good
   ./scripts/run_in_screen.sh hybrid-benchmark-verified "./run_azure_benchmark.sh 64 verified"
   
   # Bad
   ./scripts/run_in_screen.sh test "./run_azure_benchmark.sh 64 verified"
   ```

2. **Check Before Starting**: Always check if session exists before starting
   ```bash
   ./scripts/status_screen.sh my-session
   ```

3. **Monitor Long Tasks**: Use monitor for long-running tasks
   ```bash
   ./scripts/monitor_screen.sh my-session
   ```

4. **Clean Up**: Kill completed sessions to avoid clutter
   ```bash
   ./scripts/kill_screen.sh completed-session
   ```

## Example: Running Hybrid Agent Benchmark

```bash
# Start benchmark
./scripts/run_in_screen.sh hybrid-benchmark \
  "./run_azure_benchmark.sh 64 verified"

# Monitor progress (in another terminal)
./scripts/monitor_screen.sh hybrid-benchmark

# Or check status
./scripts/status_screen.sh hybrid-benchmark

# View logs
tail -f logs/screen_sessions/hybrid-benchmark_*/main.log

# When complete, kill session
./scripts/kill_screen.sh hybrid-benchmark
```

## Troubleshooting

### Screen Session Not Starting
- Check if screen is installed: `which screen`
- Check if another session with same name exists
- Check logs in `logs/screen_sessions/`

### Can't Attach to Session
- Session may have exited: Check status with `./scripts/status_screen.sh`
- Session may be attached elsewhere: Use `screen -x` instead of `screen -r`

### Logs Not Appearing
- Wait a few seconds for logs to initialize
- Check if process is actually running: `./scripts/status_screen.sh`
- Check permissions on `logs/` directory

### Process Died Unexpectedly
- Check `stderr.log` for error messages
- Check system resources: `free -h`, `df -h`
- Check system logs: `dmesg | tail`, `journalctl -xe`

