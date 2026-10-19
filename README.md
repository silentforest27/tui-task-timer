# TUI Task Timer

A simple, efficient terminal-based Pomodoro timer written in Zig.

## Features
- Minimalist TUI
- Low resource usage
- Standard 25-minute intervals
- Customizable task labels and durations
- Persistent session stats and history

## Building
```bash
zig build-exe src/main.zig
```

## Testing
```bash
zig test src/timer.zig
```

## Usage
Run with default settings (25 mins focus, 5 mins break, "Focus Session"):
```bash
./main
```

Specify a custom focus duration and task label:
```bash
./main 10 "Code Review"
```

Specify focus duration, task label, and break duration (e.g., 10m focus, 2m break):
```bash
./main 10 "Code Review" 2
```

## Controls
- `s`: start/resume
- `p`: pause
- `r`: reset
- `b`: start break
- `+` / `-`: adjust focus duration
- `U` / `I`: adjust break duration
- `n`: rename task
- `C`: clear stats and history
- `q`: quit
