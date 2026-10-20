const std = @import("std");

fn scaleRemaining(remaining: u32, old_duration: u32, new_duration: u32) u32 {
    if (new_duration == 0) return 0;
    if (old_duration == 0) return new_duration;

    var rem = remaining;
    if (rem > old_duration) rem = old_duration;
    if (rem == 0) return 0;

    const scaled: u32 = @intCast((@as(u64, rem) * @as(u64, new_duration)) / @as(u64, old_duration));
    if (scaled == 0) return 1;
    if (scaled > new_duration) return new_duration;
    return scaled;
}

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
    paused_from_break: bool = false,

    pub fn init(duration_mins: u32) TaskTimer {
        const secs = duration_mins * 60;
        return TaskTimer{
            .focus_duration_secs = secs,
            .duration_secs = secs,
            .remaining_secs = secs,
            .state = .Idle,
            .paused_from_break = false,
        };
    }

    pub fn start(self: *TaskTimer) void {
        if (self.state == .Paused) {
            if (self.paused_from_break) {
                self.state = .Break;
            } else {
                self.state = .Running;
            }
            if (self.remaining_secs == 0 and self.duration_secs > 0) {
                self.remaining_secs = self.duration_secs;
            }
            self.paused_from_break = false;
            return;
        }

        if (self.state == .Break) {
            // Starting a new focus session aborts the current break.
            self.duration_secs = self.focus_duration_secs;
            self.remaining_secs = self.focus_duration_secs;
        } else if (self.remaining_secs == 0) {
            // Restore the focus duration after a completed focus or break session.
            self.duration_secs = self.focus_duration_secs;
            self.remaining_secs = self.focus_duration_secs;
        }
        self.state = .Running;
    }

    pub fn pause(self: *TaskTimer) void {
        if (self.state == .Running or self.state == .Break) {
            self.paused_from_break = self.state == .Break;
            self.state = .Paused;
        }
    }

    pub fn reset(self: *TaskTimer) void {
        self.duration_secs = self.focus_duration_secs;
        self.remaining_secs = self.focus_duration_secs;
        self.state = .Idle;
        self.paused_from_break = false;
    }

    pub fn startBreak(self: *TaskTimer, break_mins: u32) void {
        self.duration_secs = break_mins * 60;
        self.remaining_secs = break_mins * 60;
        self.state = .Break;
        self.paused_from_break = false;
    }

    pub fn updateFocusDuration(self: *TaskTimer, duration_mins: u32) void {
        const secs = duration_mins * 60;
        self.focus_duration_secs = secs;
        if (self.state == .Idle) {
            self.duration_secs = secs;
            self.remaining_secs = secs;
        } else if (self.state == .Paused and !self.paused_from_break) {
            self.remaining_secs = scaleRemaining(self.remaining_secs, self.duration_secs, secs);
            self.duration_secs = secs;
        }
    }

    pub fn updateBreakDuration(self: *TaskTimer, break_mins: u32) void {
        const secs = break_mins * 60;
        if (self.state == .Break) {
            self.remaining_secs = scaleRemaining(self.remaining_secs, self.duration_secs, secs);
            self.duration_secs = secs;
        } else if (self.state == .Paused and self.paused_from_break) {
            self.remaining_secs = scaleRemaining(self.remaining_secs, self.duration_secs, secs);
            self.duration_secs = secs;
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

        const elapsed: u32 = if (self.remaining_secs >= self.duration_secs)
            0
        else
            self.duration_secs - self.remaining_secs;
        const filled: usize = @intCast((@as(u64, elapsed) * width) / self.duration_secs);
        const percent: u32 = @intCast((@as(u64, elapsed) * 100) / self.duration_secs);

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

test "init creates an idle focus timer" {
    const timer = TaskTimer.init(25);
    try std.testing.expectEqual(@as(u32, 25 * 60), timer.remaining_secs);
    try std.testing.expectEqual(TimerState.Idle, timer.state);
    try std.testing.expectEqual(@as(u32, 25 * 60), timer.focus_duration_secs);
}

test "tick counts down and finishes" {
    var timer = TaskTimer.init(1);
    timer.state = .Running;
    timer.remaining_secs = 2;

    try std.testing.expect(!timer.tick());
    try std.testing.expectEqual(@as(u32, 1), timer.remaining_secs);
    try std.testing.expectEqual(TimerState.Running, timer.state);

    try std.testing.expect(timer.tick());
    try std.testing.expectEqual(@as(u32, 0), timer.remaining_secs);
    try std.testing.expectEqual(TimerState.Idle, timer.state);
}

test "startBreak and tick finish a break" {
    var timer = TaskTimer.init(1);
    timer.startBreak(1);
    timer.remaining_secs = 1;

    try std.testing.expect(timer.tick());
    try std.testing.expectEqual(@as(u32, 0), timer.remaining_secs);
    try std.testing.expectEqual(TimerState.Idle, timer.state);
}

test "formatTime and formatSeconds" {
    var buf: [16]u8 = undefined;
    const long = try TaskTimer.formatSeconds(&buf, 3661);
    try std.testing.expectEqualStrings("01:01:01", long);

    var timer = TaskTimer.init(1);
    timer.remaining_secs = 5;
    const short = try timer.formatTime(&buf);
    try std.testing.expectEqualStrings("00:05", short);
}

test "formatProgressBar reports elapsed percentage" {
    var timer = TaskTimer.init(1);
    timer.state = .Running;
    timer.remaining_secs = 30;

    var buf: [64]u8 = undefined;
    const bar = try timer.formatProgressBar(&buf);
    try std.testing.expect(std.mem.indexOf(u8, bar, "50%") != null);
}

test "reset restores the focus duration" {
    var timer = TaskTimer.init(2);
    timer.state = .Running;
    timer.remaining_secs = 10;

    timer.reset();
    try std.testing.expectEqual(@as(u32, 120), timer.remaining_secs);
    try std.testing.expectEqual(@as(u32, 120), timer.duration_secs);
    try std.testing.expectEqual(TimerState.Idle, timer.state);
}

test "pause and resume preserves a paused focus session" {
    var timer = TaskTimer.init(2);
    timer.state = .Running;
    timer.remaining_secs = 90;
    timer.duration_secs = 120;

    timer.pause();
    try std.testing.expectEqual(TimerState.Paused, timer.state);
    try std.testing.expect(!timer.paused_from_break);
    try std.testing.expectEqual(@as(u32, 90), timer.remaining_secs);

    timer.start();
    try std.testing.expectEqual(TimerState.Running, timer.state);
    try std.testing.expectEqual(@as(u32, 90), timer.remaining_secs);
}

test "pause and resume preserves a paused break" {
    var timer = TaskTimer.init(2);
    timer.startBreak(1);
    timer.remaining_secs = 45;
    timer.duration_secs = 60;

    timer.pause();
    try std.testing.expectEqual(TimerState.Paused, timer.state);
    try std.testing.expect(timer.paused_from_break);
    try std.testing.expectEqual(@as(u32, 45), timer.remaining_secs);

    timer.start();
    try std.testing.expectEqual(TimerState.Break, timer.state);
    try std.testing.expect(!timer.paused_from_break);
    try std.testing.expectEqual(@as(u32, 45), timer.remaining_secs);
}

test "starting after a completed break restores focus duration" {
    var timer = TaskTimer.init(3);
    timer.startBreak(2);
    timer.remaining_secs = 0;
    timer.state = .Idle;

    timer.start();
    try std.testing.expectEqual(TimerState.Running, timer.state);
    try std.testing.expectEqual(@as(u32, 3 * 60), timer.remaining_secs);
    try std.testing.expectEqual(@as(u32, 3 * 60), timer.duration_secs);
    try std.testing.expectEqual(@as(u32, 3 * 60), timer.focus_duration_secs);
}

test "focus duration updates ignore a paused break" {
    var timer = TaskTimer.init(2);
    timer.startBreak(1);
    timer.remaining_secs = 40;
    timer.duration_secs = 60;
    timer.pause();

    timer.updateFocusDuration(5);
    try std.testing.expectEqual(@as(u32, 5 * 60), timer.focus_duration_secs);
    try std.testing.expectEqual(@as(u32, 40), timer.remaining_secs);
    try std.testing.expectEqual(@as(u32, 60), timer.duration_secs);
}

test "formatProgressBar clamps when remaining exceeds duration" {
    var timer = TaskTimer.init(1);
    timer.state = .Running;
    timer.duration_secs = 60;
    timer.remaining_secs = 100;

    var buf: [64]u8 = undefined;
    const bar = try timer.formatProgressBar(&buf);
    try std.testing.expect(std.mem.indexOf(u8, bar, "0%") != null);
}

test "start restores a paused focus timer with no remaining time" {
    var timer = TaskTimer.init(2);
    timer.state = .Paused;
    timer.paused_from_break = false;
    timer.duration_secs = 120;
    timer.remaining_secs = 0;

    timer.start();
    try std.testing.expectEqual(TimerState.Running, timer.state);
    try std.testing.expectEqual(@as(u32, 120), timer.remaining_secs);
}

test "start restores a paused break with no remaining time" {
    var timer = TaskTimer.init(2);
    timer.state = .Paused;
    timer.paused_from_break = true;
    timer.duration_secs = 60;
    timer.remaining_secs = 0;

    timer.start();
    try std.testing.expectEqual(TimerState.Break, timer.state);
    try std.testing.expect(!timer.paused_from_break);
    try std.testing.expectEqual(@as(u32, 60), timer.remaining_secs);
}

test "focus duration update scales paused remaining time" {
    var timer = TaskTimer.init(2);
    timer.state = .Paused;
    timer.paused_from_break = false;
    timer.duration_secs = 120;
    timer.remaining_secs = 1;

    timer.updateFocusDuration(1);
    try std.testing.expectEqual(@as(u32, 60), timer.focus_duration_secs);
    try std.testing.expectEqual(@as(u32, 60), timer.duration_secs);
    try std.testing.expectEqual(@as(u32, 1), timer.remaining_secs);
}

test "break duration update scales an active break" {
    var timer = TaskTimer.init(2);
    timer.startBreak(2);
    timer.remaining_secs = 30;
    timer.duration_secs = 120;

    timer.updateBreakDuration(1);
    try std.testing.expectEqual(TimerState.Break, timer.state);
    try std.testing.expectEqual(@as(u32, 60), timer.duration_secs);
    try std.testing.expectEqual(@as(u32, 15), timer.remaining_secs);
}

test "break duration update scales a paused break" {
    var timer = TaskTimer.init(2);
    timer.startBreak(2);
    timer.remaining_secs = 30;
    timer.duration_secs = 120;
    timer.pause();

    timer.updateBreakDuration(1);
    try std.testing.expectEqual(TimerState.Paused, timer.state);
    try std.testing.expect(timer.paused_from_break);
    try std.testing.expectEqual(@as(u32, 60), timer.duration_secs);
    try std.testing.expectEqual(@as(u32, 15), timer.remaining_secs);
}
