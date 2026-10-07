const std = @import("std");
const Timer = @import("timer");

pub fn main() !void {
    var stdout = std.io.getStdOut().writer();
    var stdin = std.io.getStdIn().reader();

    var duration_mins: u32 = 25;
    const args = try std.process.argsAlloc(
        std.heap.page_allocator,
    );
    defer std.heap.page_allocator.free(args);

    if (args.len > 1) {
        if (std.fmt.parseInt(u32, args[1], 10)) catch { 
            try stdout.print("Invalid duration provided. Using default 25m.\n", .{});
            duration_mins = 25;
        } else {
            duration_mins = try std.fmt.parseInt(u32, args[1], 10);
        }
    }

    var timer = Timer.TaskTimer.init(duration_mins);
    var buf: [1]u8 = undefined;
    var time_buf: [16]u8 = undefined;

    try stdout.print("TUI Task Timer (Zig)\n", .{});
    try stdout.print("Duration: {d} minutes\n", .{duration_mins});
    try stdout.print("Controls: [s]tart, [p]ause, [r]eset, [q]uit\n", .{});

    var is_running = false;

    while (true) {
        // Clear line and print status
        const formatted_time = timer.formatTime(&time_buf) catch "00:00";
        try stdout.print("\rStatus: {s} | Time: {s}   ", .{ 
            if (timer.state == .Running) "RUNNING" else if (timer.state == .Paused) "PAUSED" else "IDLE",
            formatted_time
        });

        if (is_running) {
            if (timer.tick()) {
                try stdout.print("\nTimer Finished!\n", .{});
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

    try stdout.print("Exiting...\n", .{});
}