const std = @import("std");
const Timer = @import("timer");

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
    var buf: [1]u8 = undefined;
    var time_buf: [16]u8 = undefined;
    var bar_buf: [64]u8 = undefined;

    try stdout.print("TUI Task Timer (Zig)\n", .{});
    try stdout.print("Task: {s}\n", .{task_label});
    try stdout.print("Duration: {d} minutes\n", .{duration_mins});
    try stdout.print("Controls: [s]tart, [p]ause, [r]eset, [q]uit\n", .{});
    try stdout.print("-----------------------------------------\n", .{});

    // Hide cursor
    try stdout.print("\x1b[?25l", .{});

    var is_running = false;

    while (true) {
        // Clear line and print status
        const formatted_time = timer.formatTime(&time_buf) catch "00:00";
        
        const status_text = switch (timer.state) {
            .Running => "\x1b[32mRUNNING\x1b[0m",
            .Paused => "\x1b[33mPAUSED\x1b[0m",
            .Idle => "\x1b[34mIDLE\x1b[0m",
        };

        const progress_bar = timer.formatProgressBar(&bar_buf) catch "[----------]";

        try stdout.print("\r\x1b[K[{s}] Status: {s} | Time: {s} | {s}   ", .{ 
            task_label,
            status_text,
            formatted_time,
            progress_bar
        });

        if (is_running) {
            if (timer.tick()) {
                // Trigger system beep (ASCII Bell)
                try stdout.print("\a", .{});
                try stdout.print("\n\x1b[32m Timer Finished! Time to take a break! \x1b[0m\n", .{});
                is_running = false;
            }
        }

        // Non-blocking input check (simplified for basic demo)
        if (try stdin.read(&buf) != 0) {
            switch (buf[0]) {
                's' => {
                    timer.start();
                    is_running = true;
                },
                'p' => {
                    timer.pause();
                    is_running = false;
                },
                'r' => {
                    timer.reset();
                    is_running = false;
                },
                'q' => break,
                else => {},
            }
        }

        std.time.sleep(1 * std.time.ns_per_s);
    }

    // Restore cursor
    try stdout.print("\x1b[?25h", .{});
    try stdout.print("\nExiting...\n", .{});
}