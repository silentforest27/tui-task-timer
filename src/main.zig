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
    var term: termios = undefined;
    _ = tcgetattr(STDIN_FILENO, &term);

    // Disable echoing and canonical mode (buffered input)
    term.c_lflag &= ~(ECHO | ICANON);

    _ = tcsetattr(STDIN_FILENO, 0, &term);

    // Set STDIN to non-blocking for the read call
    _ = std.os.linux.fcntl(STDIN_FILENO, std.os.linux.F_SETFL, std.os.linux.O_NONBLOCK);
}

fn disableRawMode() !void {
    var term: termios = undefined;
    _ = tcgetattr(STDIN_FILENO, &term);

    // Restore echoing and canonical mode
    term.c_lflag |= (ECHO | ICANON);

    _ = tcsetattr(STDIN_FILENO, 0, &term);

    // Restore blocking I/O
    _ = std.os.linux.fcntl(STDIN_FILENO, std.os.linux.F_SETFL, 0);
}

const Stats = struct {
    sessions: u32,
    focus_secs: u32,
};

fn loadStats() Stats {
    const file = std.fs.cwd().openFile("stats.txt", .{ .mode = .read_only }) catch return Stats{ .sessions = 0, .focus_secs = 0 };
    defer file.close();

    var buf: [64]u8 = undefined;
    const bytes_read = file.readAll(&buf) catch return Stats{ .sessions = 0, .focus_secs = 0 };
    const content = buf[0..bytes_read];

    var it = std.mem.splitScalar(u8, content, ' ');
    const sessions = std.fmt.parseInt(u32, std.mem.trim(u8, it.next() orelse "0", " \t\r\n"), 10) catch 0;
    const focus_secs = std.fmt.parseInt(u32, std.mem.trim(u8, it.next() orelse "0", " \t\r\n"), 10) catch 0;

    return Stats{ .sessions = sessions, .focus_secs = focus_secs };
}

fn saveStats(sessions: u32, focus_secs: u32) void {
    var buf: [64]u8 = undefined;
    const data = std.fmt.bufPrint(&buf, "{d} {d}", .{ sessions, focus_secs }) catch return;
    std.fs.cwd().writeFile("stats.txt", data) catch {};
}

fn logSessionAppend(task_label: []const u8, duration_mins: u32) void {
    const file = std.fs.cwd().createFile("history.log", .{ .truncate = false }) catch return;
    defer file.close();

    file.seekToEnd() catch return;

    var buf: [128]u8 = undefined;
    const data = std.fmt.bufPrint(&buf, "Task: {s}, Duration: {d}m\n", .{ task_label, duration_mins }) catch return;
    _ = file.writeAll(data) catch {};
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
            if (val > 0) {
                duration_mins = val;
            } else {
                try stdout.print("Invalid duration provided. Using default 25m.\n", .{});
            }
        } else {
            try stdout.print("Invalid duration provided. Using default 25m.\n", .{});
        }
    }

    if (args.len > 2) {
        task_label = args[2];
    }

    if (args.len > 3) {
        if (std.fmt.parseInt(u32, args[3], 10)) |val| {
            if (val > 0) {
                break_mins = val;
            } else {
                try stdout.print("Invalid break duration provided. Using default 5m.\n", .{});
            }
        } else {
            try stdout.print("Invalid break duration provided. Using default 5m.\n", .{});
        }
    }

    var timer = Timer.TaskTimer.init(duration_mins);
    var buf: [32]u8 = undefined;
    var time_buf: [16]u8 = undefined;
    var bar_buf: [64]u8 = undefined;
    var total_buf: [16]u8 = undefined;
    var task_name_buf: [64]u8 = undefined;

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
    try stdout.print("\nControls: [s]tart, [p]ause, [r]eset, [b]reak, [+/-] adj focus, [U/I] adj break, [n]ame, [C]lear stats, [q]uit\n", .{});
    try stdout.print("\x1b[2m-----------------------------------------------------\x1b[0m\n", .{});

    // Hide cursor
    try stdout.print("\x1b[?25l", .{});

    var is_running = false;
    var last_tick_time = try std.time.Timer.start();

    var sessions_completed: u32 = 0;
    var total_focus_secs: u32 = 0;
    {
        const loaded = loadStats();
        sessions_completed = loaded.sessions;
        total_focus_secs = loaded.focus_secs;
    }

    while (true) {
        const formatted_time = timer.formatTime(&time_buf) catch "00:00";
        const total_formatted = Timer.formatSeconds(&total_buf, total_focus_secs) catch "00:00";

        const status_text = switch (timer.state) {
            .Running => "\x1b[32mRUNNING\x1b[0m",
            .Paused => "\x1b[33mPAUSED \x1b[0m",
            .Break => "\x1b[35mBREAK  \x1b[0m",
            .Idle => "\x1b[34mIDLE   \x1b[0m",
        };

        const type_text = if (timer.state == .Break) "\x1b[35m[Break]\x1b[0m" else "\x1b[32m[Focus]\x1b[0m";
        const progress_bar = timer.formatProgressBar(&bar_buf) catch "[----------]";

        // Move cursor to a fixed line for status and another for stats to prevent flicker/overlap
        try stdout.print("\r\x1b[K\x1b[1mSession:\x1b[0m {s: <15} | {s} Status: {s} | Time: {s} | {s} ", .{
            task_label,
            type_text,
            status_text,
            formatted_time,
            progress_bar
        });

        // Print stats on the next line, then move cursor back up
        try stdout.print("\n\x1b[K\x1b[2mTotal sessions: {d} | Total focus: {s}\x1b[0m", .{
            sessions_completed,
            total_formatted
        });
        try stdout.print("\x1b[1A", .{});

        if (is_running) {
            if (last_tick_time.read() >= 1 * std.time.ns_per_s) {
                last_tick_time.reset();

                // Preserve whether the completed tick belonged to a break before
                // tick() transitions the timer to Idle.
                const was_break = timer.state == .Break;

                // Count elapsed focus time before advancing the timer.
                if (timer.state == .Running and timer.remaining_secs > 0) {
                    total_focus_secs += 1;
                    if (total_focus_secs % 30 == 0) {
                        saveStats(sessions_completed, total_focus_secs);
                    }
                }

                if (timer.tick()) {
                    if (was_break) {
                        try stdout.print("\a", .{});
                        try stdout.print("\n\x1b[35m\x1b[1m ★ Break Finished! Ready to focus. ★ \x1b[0m\n", .{});
                        is_running = false;
                    } else {
                        timer.startBreak(break_mins);
                        try stdout.print("\a", .{});
                        try stdout.print("\n\x1b[32m\x1b[1m ★ Focus Session Complete! Starting Break... ★ \x1b[0m\n", .{});
                        sessions_completed += 1;
                        is_running = true;
                        saveStats(sessions_completed, total_focus_secs);
                        logSessionAppend(task_label, duration_mins);
                    }
                }
            }
        }

        while (true) {
            const key = stdin.readByte() catch break;
            switch (key) {
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
                        try stdout.print("\a", .{});
                    }
                },
                '-' => {
                    if (timer.state == .Idle or timer.state == .Paused) {
                        if (duration_mins > 1) {
                            duration_mins -= 1;
                            timer.updateFocusDuration(duration_mins);
                            try stdout.print("\a", .{});
                        }
                    }
                },
                'U' => {
                    if (timer.state == .Idle or timer.state == .Paused) {
                        break_mins += 1;
                        try stdout.print("\a", .{});
                    }
                },
                'I' => {
                    if (timer.state == .Idle or timer.state == .Paused) {
                        if (break_mins > 1) {
                            break_mins -= 1;
                            try stdout.print("\a", .{});
                        }
                    }
                },
                'n' => {
                    // Temporary disable raw mode to use standard input for naming
                    disableRawMode() catch {};
                    try stdout.print("\n\x1b[1mEnter new task name: \x1b[0m", .{});

                    if (stdin.readUntilDelimiterOrEof(&task_name_buf, '\n') catch null) |name| {
                        const trimmed = std.mem.trim(u8, name, "\r\n");
                        if (trimmed.len > 0) {
                            task_label = trimmed;
                        }
                    }

                    enableRawMode() catch {};
                    try stdout.print("\x1b[?25l", .{}); // Re-hide cursor
                },
                'C' => {
                    sessions_completed = 0;
                    total_focus_secs = 0;
                    saveStats(0, 0);
                    std.fs.cwd().writeFile("history.log", "") catch {};
                    try stdout.print("\n\x1b[31m\x1b[1m ★ Stats and History Cleared ★ \x1b[0m\n", .{});
                },
                'q' => {
                    saveStats(sessions_completed, total_focus_secs);
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
