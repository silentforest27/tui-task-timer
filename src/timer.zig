const std = @import("std");

pub const TimerState = enum {
    Idle,
    Running,
    Paused,
    Break,
};

pub const TaskTimer = struct {
    focus_duration_secs: u32,
    duration_secs: u32,
    remaining_secs: u32,
    state: TimerState,

    pub fn init(duration_mins: u32) TaskTimer {
        const secs = duration_mins * 60;
        return TaskTimer{
            .focus_duration_secs = secs,
            .duration_secs = secs,
            .remaining_secs = secs,
            .state = .Idle,
        };
    }

    pub fn start(self: *TaskTimer) void {
        if (self.state == .Break) {
            // Transition back from break to focus session
            self.duration_secs = self.focus_duration_secs;
            self.remaining_secs = self.focus_duration_secs;
        } else if (self.remaining_secs == 0) {
            self.remaining_secs = self.duration_secs;
        }
        self.state = .Running;
    }

    pub fn pause(self: *TaskTimer) void {
        if (self.state == .Running or self.state == .Break) {
            self.state = .Paused;
        }
    }

    pub fn reset(self: *TaskTimer) void {
        self.duration_secs = self.focus_duration_secs;
        self.remaining_secs = self.focus_duration_secs;
        self.state = .Idle;
    }

    pub fn startBreak(self: *TaskTimer, break_mins: u32) void {
        self.duration_secs = break_mins * 60;
        self.remaining_secs = break_mins * 60;
        self.state = .Break;
    }

    pub fn updateFocusDuration(self: *TaskTimer, duration_mins: u32) void {
        const secs = duration_mins * 60;
        self.focus_duration_secs = secs;
        if (self.state == .Idle) {
            self.duration_secs = secs;
            self.remaining_secs = secs;
        } else if (self.state == .Paused) {
            // Proportional adjustment of remaining time if paused
            if (self.duration_secs > 0) {
                const ratio = @as(f32, @floatFromInt(self.remaining_secs)) / @as(f32, @floatFromInt(self.duration_secs));
                self.remaining_secs = @intFromFloat(ratio * @as(f32, @floatFromInt(secs)));
                self.duration_secs = secs;
            }
        }
    }

    pub fn isFinished(self: TaskTimer) bool {
        return self.remaining_secs == 0;
    }

    pub fn tick(self: *TaskTimer) bool {
        if ((self.state == .Running or self.state == .Break) and self.remaining_secs > 0) {
            self.remaining_secs -= 1;
            if (self.remaining_secs == 0) {
                self.state = .Idle;
                return true; // Timer finished
            }
        }
        return false;
    }

    pub fn formatTime(self: TaskTimer, buf: []u8) ![]const u8 {
        return formatSeconds(buf, self.remaining_secs);
    }

    pub fn formatSeconds(buf: []u8, total_secs: u32) ![]const u8 {
        const hours = total_secs / 3600;
        const mins = (total_secs % 3600) / 60;
        const secs = total_secs % 60;
        if (hours > 0) {
            return std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}:{d:0>2}", .{ hours, mins, secs });
        } else {
            return std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}", .{ mins, secs });
        }
    }

    pub fn formatProgressBar(self: TaskTimer, buf: []u8) ![]const u8 {
        const width = 20;
        if (buf.len < 64) return error.BufferTooSmall;

        if (self.duration_secs == 0) return error.InvalidDuration;

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

        // Always apply color if we have a bar to draw
        @memcpy(buf[out_idx..][0..color_code.len], color_code);
        out_idx += color_code.len;

        for (0..width) |i| {
            if (i < filled) {
                buf[out_idx] = '=';
                out_idx += 1;
            } else {
                buf[out_idx] = '-';
                out_idx += 1;
            }
        }
        
        @memcpy(buf[out_idx..][0..reset_code.len], reset_code);
        out_idx += reset_code.len;

        buf[out_idx] = ']';
        out_idx += 1;

        const pct_str = try std.fmt.bufPrint(buf[out_idx..], " {d}%", .{percent});
        out_idx += pct_str.len;
        
        return buf[0..out_idx];
    }
};