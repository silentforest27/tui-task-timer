const std = @import("std");

pub const TimerState = enum {
    Idle,
    Running,
    Paused,
    Break,
};

pub const TaskTimer = struct {
    duration_secs: u32,
    remaining_secs: u32,
    state: TimerState,

    pub fn init(duration_mins: u32) TaskTimer {
        return TaskTimer{
            .duration_secs = duration_mins * 60,
            .remaining_secs = duration_mins * 60,
            .state = .Idle,
        };
    }

    pub fn start(self: *TaskTimer) void {
        if (self.remaining_secs == 0) {
            self.remaining_secs = self.duration_secs;
        }
        self.state = .Running;
    }

    pub fn pause(self: *TaskTimer) void {
        if (self.state == .Running) {
            self.state = .Paused;
        }
    }

    pub fn reset(self: *TaskTimer) void {
        self.remaining_secs = self.duration_secs;
        self.state = .Idle;
    }

    pub fn startBreak(self: *TaskTimer) void {
        self.remaining_secs = 5 * 60; // Default 5 min break
        self.duration_secs = 5 * 60;
        self.state = .Running;
    }

    pub fn isFinished(self: TaskTimer) bool {
        return self.remaining_secs == 0;
    }

    pub fn tick(self: *TaskTimer) bool {
        if (self.state == .Running and self.remaining_secs > 0) {
            self.remaining_secs -= 1;
            if (self.remaining_secs == 0) {
                self.state = .Idle;
                return true; // Timer finished
            }
        }
        return false;
    }

    pub fn formatTime(self: TaskTimer, buf: []u8) ![]const u8 {
        const mins = self.remaining_secs / 60;
        const secs = self.remaining_secs % 60;
        return std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}", .{ mins, secs });
    }

    pub fn formatProgressBar(self: TaskTimer, buf: []u8) ![]const u8 {
        const width = 20;
        if (buf.len < 64) return error.BufferTooSmall;

        const elapsed = self.duration_secs - self.remaining_secs;
        const filled = (elapsed * width) / self.duration_secs;
        const percent = (elapsed * 100) / self.duration_secs;
        
        var out_idx: usize = 0;
        buf[out_idx] = '[';
        out_idx += 1;
        
        const color_code = switch (self.state) {
            .Running => "\x1b[32m",
            .Paused => "\x1b[33m",
            .Break => "\x1b[35m",
            .Idle => "\x1b[37m",
        };
        const reset_code = "\x1b[0m";

        if (filled > 0) {
            @memcpy(buf[out_idx..][0..color_code.len], color_code);
            out_idx += color_code.len;
        }

        for (0..width) |i| {
            if (i < filled) {
                buf[out_idx] = '=';
                out_idx += 1;
            } else {
                if (i == filled && filled > 0) {
                    @memcpy(buf[out_idx..][0..reset_code.len], reset_code);
                    out_idx += reset_code.len;
                }
                buf[out_idx] = '-';
                out_idx += 1;
            }
        }
        
        if (filled == width) {
            @memcpy(buf[out_idx..][0..reset_code.len], reset_code);
            out_idx += reset_code.len;
        }

        buf[out_idx] = ']';
        out_idx += 1;

        const pct_str = try std.fmt.bufPrint(buf[out_idx..], " {d}%", .{percent});
        out_idx += pct_str.len;
        
        return buf[0..out_idx];
    }
};