const std = @import("std");
const Timer = @import("timer");

// Termios imports for raw mode on Unix
const termios = std.os.linux.termios;
const tcgetattr = std.os.linux.tcgetattr;
const tcsetattr = std.os.linux.tcsetattr;
const STDIN_FILENO = std.os.linux.STDIN_FILENO;

const ECHO = @as(u32, 0x00000004);
const ICANON = @as(u32, 0x00000002);

fn enableRawMode() !void {
    var term : termios = undefined;
    _ = tcgetattr(STDIN_FILENO, &term);

    // Disable echoing and canonical mode (buffered input)
    term.c_lflag &= ~(ECHO | ICANON);
    
    _ = tcsetattr(STDIN_FILENO, 0, &term);

    // Set STDIN to non-blocking for the read call
    std.os.linux.fcntl(STDIN_FILENO, std.os.linux.F_SETFL, std.os.linux.O_NONBLOCK);
}

fn disableRawMode() !void {
    var term : termios = undefined;
    _ = tcgetattr(STDIN_FILENO, &term);

    // Restore echoing and canonical mode
    term.c_lflag |= (ECHO | ICANON);

    _ = tcsetattr(STDIN_FILENO, 0, &term);

    // Restore blocking I/O
    std.os.linux.fcntl(STDIN_FILENO, std.os.linux.F_SETFL, 0);
}

pub fn main() !void {
    var stdout = std.io.getStdOut().writer();
    var stdin = std.io.getStdIn().reader();

    var duration_mins: u32 = 25;
    var task_label: []const u8 = "Focus Session";

    const args = try std.process.argsAlloc(
        std.heap.page_allocator,
    );
    defer std.heap.page_allocator.free(args);

    if (args.len > 1) {
        if (std.fmt.parseInt(u32, args[1], 10)) |val| {
            duration_mins = val;
        } else {
            try stdout.print("Invalid duration provided. Using default 25m.\n", .{});
        }
    }

    if (args.len > 2) {
        task_label = args[2];
    }

    var timer = Timer.TaskTimer.init(duration_mins);
    var buf: [32]u8 = undefined;
    var time_buf: [16]u8 = undefined;
    var bar_buf: [64]u8 = undefined;

    // Set terminal to raw mode and non-blocking input
    enableRawMode() catch {};
    defer disableRawMode() catch {};

    // Clear screen and move cursor to top-left
    try stdout.print("\x1b[2J\x1b[H", .{});

    try stdout.print("\x1b[1m\x1b[36m╔══════════════════════════════════════════════════════╗\x1b[0m\n", .{});
    try stdout.print("\x1b[1m\x1b[36m║\x1b[0m  \x1b[1mTUI Task Timer (Zig)\x1b[0m                                  \x1b[1m\x1b[36m║\x1b[0m\n", .{});
    try stdout.print("\x1b[1m\x1b[36m╠══════════════════════════════════════════════════════╣\x1b[0m\n", .{});
    try stdout.print("\x1b[1m\x1b[36m║\x1b[0m  Task: \x1b[33m{s}\x1b[0m                                      \x1b[1m\x1b[36m║\x1b[0m\n", .{task_label});
    try stdout.print("\x1b[1m\x1b[36m║\x1b[0m  Duration: {d} minutes                                 \x1b[1m\x1b[36m║\x1b[0m\n", .{duration_mins});
    try stdout.print("\x1b[1m\x1b[36m╚══════════════════════════════════════════════════════╝\x1b[0m\n", .{});
    try stdout.print("\nControls: [s]tart, [p]ause, [r]eset, [b]reak, [q]uit\n", .{});
    try stdout.print("\x1b[2m-----------------------------------------------------\x1b[0m\n", .{});

    // Hide cursor
    try stdout.print("\x1b[?25l", .{});

    var is_running = false;
    var last_tick_time = std.time.Timer.start();

    while (true) {
        // Clear line and print status
        const formatted_time = timer.formatTime(&time_buf) catch "00:00";
        
        const status_text = switch (timer.state) {
            .Running => "\x1b[32mRUNNING\x1b[0m",
            .Paused => "\x1b[33mPAUSED\x1b[0m",
            .Break => "\x1b[35mBREAK\x1b[0m",
            .Idle => "\x1b[34mIDLE\x1b[0m",
        };

        const progress_bar = timer.formatProgressBar(&bar_buf) catch "[----------]";

        try stdout.print("\r\x1b[K\x1b[1mSession:\x1b[0m {s} | Status: {s} | Time: {s} | {s}   ", .{ 
            task_label,
            status_text,
            formatted_time,
            progress_bar
        });

        if (is_running) {
            // Tick every 1 second
            if (last_tick_time.read() >= 1 * std.time.ns_per_s) {
                last_tick_time.reset();
                if (timer.tick()) {
                    // Trigger system beep (ASCII Bell)
                    try stdout.print("\a", .{});
                    try stdout.print("\n\x1b[32m\x1b[1m Timer Finished! Time to take a break! \x1b[0m\n", .{});
                    is_running = false;
                }
            }
        }

        // Read all available input to prevent lag
        while (stdin.read(&buf) catch 0 != 0) {
            // Only process the first byte for simplicity in this TUI
            switch (buf[0]) {
                's' => {
                    if (timer.state != .Running) {
                        timer.start();
                        is_running = true;
                        last_tick_time.reset();
                    }
                },
                'p' => {
                    if (timer.state == .Running) {
                        timer.pause();
                        is_running = false;
                        try stdout.print("\x1b[5m\x1b[0m", .{});
                    }
                },
                'r' => {
                    timer.reset();
                    is_running = false;
                },
                'b' => {
                    timer.startBreak();
                    is_running = true;
                    last_tick_time.reset();
                },
                'q' => {
                    try stdout.print("\x1b[?25h\n\x1b[0mExiting...\n", .{});
                    std.process.exit(0);
                },
                else => {},
            }
        }

        // Sleep for a short duration to avoid 100% CPU usage but remain responsive
        std.time.sleep(10 * std.time.ns_per_ms);
    }

    // Restore cursor
    try stdout.print("\x1b[?25h", .{});
    try stdout.print("\nExiting...\n", .{});
}