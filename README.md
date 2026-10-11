# TUI Task Timer

A simple, efficient terminal-based Pomodoro timer written in Zig.

## Features
- Minimalist TUI
- Low resource usage
- Standard 25-minute intervals
- Customizable task labels and duration

## Building
```bash
zig build-exe src/main.zig
```

## Usage
Run with default settings (25 mins, "Focus Session"):
```bash
./main
```

Specify a custom duration (e.g., 10 minutes) and task label:
```bash
./main 10 "Code Review"
```