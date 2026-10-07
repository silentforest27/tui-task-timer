const std = @import("std");
const Timer = @import("timer");

pub fn main() !void {
    var stdout = std.io.getStdOut().writer();
    var stdin = std.io.getStdIn().reader();

    var timer = Timer.TaskTimer.init(25);
    var buf: [1]u8 = undefined;

    try stdout.print("TUI Task Timer (Zig)\n", .{});
    try stdout.print("Controls: [s]tart, [p]ause, [r]eset, [q]uit\n", .{});

    var is_running = false;

    while (true) {
        // Clear line and print status
        try stdout.print("\rStatus: {s} | Time: {s}   ", .{ 
            if (timer.state == .Running) "RUNNING" else if (timer.state == .Paused) "PAUSED" else "IDLE",
            timer.formatTime()
        });

        if (is_running) {
            if (timer.tick()) {
                try stdout.print("\nTimer Finished!\n", .{});
                is_running = false;
            }
        }

        // Non-blocking input check (simplified for basic demo)
        // In a real TUI, we would use termios/raw mode
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