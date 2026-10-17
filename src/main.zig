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
    var break_mins: u32 = 5;
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

    if (args.len > 3) {
        if (std.fmt.parseInt(u32, args[3], 10)) |val| {
            break_mins = val;
        } else {
            try stdout.print("Invalid break duration provided. Using default 5m.\n", .{});
        }
    }

    var timer = Timer.TaskTimer.init(duration_mins);
    var buf: [32]u8 = undefined;
    var time_buf: [16]u8 = undefined;
    var bar_buf: [64]u8 = undefined;
    var total_buf: [16]u8 = undefined;

    // Set terminal to raw mode and non-blocking input
    enableRawMode() catch {};
    defer disableRawMode() catch {};

    // Clear screen and move cursor to top-left
    try stdout.print("\x1b[2J\x1b[H", .{});

    try stdout.print("\x1b[1m\x1b[36m╔══════════════════════════════════════════════════════╗\x1b[0m\n", .{});
    try stdout.print("\x1b[1m\x1b[36m║\x1b[0m  \x1b[1mTUI Task Timer (Zig)\x1b[0m                                  \x1b[1m\x1b[36m║\x1b[0m\n", .{});
    try stdout.print("\x1b[1m\x1b[36m╠══════════════════════════════════════════════════════╣\x1b[0m\n", .{});
    try stdout.print("\x1b[1m\x1b[36m║\x1b[0m  Task: \x1b[33m{s}\x1b[0m                                      \x1b[1m\x1b[36m║\x1b[0m\n", .{task_label});
    try stdout.print("\x1b[1m\x1b[36m║\x1b[0m  Duration: {d} mins | Break: {d} mins                \x1b[1m\x1b[36m║\x1b[0m\n", .{duration_mins, break_mins});
    try stdout.print("\x1b[1m\x1b[36m╚══════════════════════════════════════════════════════╝\x1b[0m\n", .{});
    try stdout.print("\nControls: [s]tart, [p]ause, [r]eset, [b]reak, [+/-] adj focus, [U/I] adj break, [n]ame, [q]uit\n", .{});
    try stdout.print("\x1b[2m-----------------------------------------------------\x1b[0m\n", .{});

    // Hide cursor
    try stdout.print("\x1b[?25l", .{});

    var is_running = false;
    var last_tick_time = std.time.Timer.start();
    var sessions_completed: u32 = 0;
    var total_focus_secs: u32 = 0;

    while (true) {
        const formatted_time = timer.formatTime(&time_buf) catch "00:00";
        const total_formatted = Timer.formatSeconds(&total_buf, total_focus_secs) catch "00:00";
        
        const status_text = switch (timer.state) {
            .Running => "\x1b[32mRUNNING\x1b[0m",
            .Paused => "\x1b[33mPAUSED \x1b[0m",
            .Break => "\x1b[35mBREAK  \x1b[0m",
            .Idle => "\x1b[34mIDLE   \x1b[0m",
        };

        const progress_bar = timer.formatProgressBar(&bar_buf) catch "[----------]";

        // Using \r\x1b[K to clear the line and ensure a consistent start
        try stdout.print("\r\x1b[K\x1b[1mSession:\x1b[0m {s: <15} | Status: {s} | Time: {s} | {s} | Done: {d} | Total: {s}   ", .{ 
            task_label,
            status_text,
            formatted_time,
            progress_bar,
            sessions_completed,
            total_formatted
        });

        if (is_running) {
            if (last_tick_time.read() >= 1 * std.time.ns_per_s) {
                last_tick_time.reset();
                if (timer.tick()) {
                    if (timer.state == .Idle) {
                        // If we just finished a focus session, auto-start break
                        timer.startBreak(break_mins);
                        try stdout.print("\a", .{});
                        try stdout.print("\n\x1b[32m\x1b[1m ★ Focus Session Complete! Starting Break... ★ \x1b[0m\n", .{});
                        sessions_completed += 1;
                        is_running = true; // Keep running for the break
                    } else if (timer.state == .Break) {
                        // If we just finished a break, go to Idle
                        try stdout.print("\a", .{});
                        try stdout.print("\n\x1b[35m\x1b[1m ★ Break Finished! Ready to focus. ★ \x1b[0m\n", .{});
                        is_running = false;
                    }
                }

                // Accumulate total focus time only when in Running state (not Break)
                if (timer.state == .Running) {
                    total_focus_secs += 1;
                }
            }
        }

        while (stdin.read(&buf) catch 0 != 0) {
            switch (buf[0]) {
                's' => {
                    if (timer.state != .Running) {
                        timer.start();
                        is_running = true;
                        last_tick_time.reset();
                    }
                },
                'p' => {
                    if (timer.state == .Running or timer.state == .Break) {
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
                    timer.startBreak(break_mins);
                    is_running = true;
                    last_tick_time.reset();
                },
                '+' => {
                    if (timer.state == .Idle or timer.state == .Paused) {
                        duration_mins += 1;
                        timer.updateFocusDuration(duration_mins);
                    }
                },
                '-' => {
                    if (timer.state == .Idle or timer.state == .Paused) {
                        if (duration_mins > 1) {
                            duration_mins -= 1;
                            timer.updateFocusDuration(duration_mins);
                        }
                    }
                },
                'U' => {
                    if (timer.state == .Idle or timer.state == .Paused) {
                        break_mins += 1;
                    }
                },
                'I' => {
                    if (timer.state == .Idle or timer.state == .Paused) {
                        if (break_mins > 1) {
                            break_mins -= 1;
                        }
                    }
                },
                'n' => {
                    // Temporary disable raw mode to use standard input for naming
                    disableRawMode() catch {};
                    try stdout.print("\n\x1b[1mEnter new task name: \x1b[0m", .{});
                    
                    var name_buf: [64]u8 = undefined;
                    if (stdin.readUntilDelimiterOrEof(&name_buf, '\n')) |name| {
                        task_label = std.mem.trim(u8, name, "\r\n");
                    } else _ = {};
                    
                    enableRawMode() catch {};
                    try stdout.print("\x1b[?25l", .{}); // Re-hide cursor
                },
                'q' => {
                    try stdout.print("\x1b[?25h\n\x1b[0mExiting...\n", .{});
                    std.process.exit(0);
                },
                else => {},
            }
        }

        std.time.sleep(10 * std.time.ns_per_ms);
    }

    try stdout.print("\x1b[?25h", .{});
    try stdout.print("\nExiting...\n", .{});
}