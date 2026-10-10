const std = @import("std");

pub const TimerState = enum {
    Idle,
    Running,
    Paused,
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
        self.state = .Paused;
    }

    pub fn reset(self: *TaskTimer) void {
        self.remaining_secs = self.duration_secs;
        self.state = .Idle;
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
        // Need space for ANSI codes: [bracket] + [color] + [width*1] + [reset] + [bracket]
        if (buf.len < width + 20) return error.BufferTooSmall;

        const elapsed = self.duration_secs - self.remaining_secs;
        const filled = (elapsed * width) / self.duration_secs;
        
        var out_idx: usize = 0;
        buf[out_idx] = '[';
        out_idx += 1;
        
        const color_code = if (self.state == .Running) "\x1b[32m" else "\x1b[37m";
        const reset_code = "\x1b[0m";

        // Add color start for filled part
        if (filled > 0) {
            const code_len = color_code.len;
            for (0..code_len) |i| {
                buf[out_idx] = color_code[i];
                out_idx += 1;
            }
        }

        for (0..width) |i| {
            if (i < filled) {
                buf[out_idx] = '=';
            } else {
                // If we just transitioned from filled to unfilled, reset color
                if (i == filled) {
                    const reset_len = reset_code.len;
                    for (0..reset_len) |j| {
                        buf[out_idx] = reset_code[j];
                        out_idx += 1;
                    }
                }
                buf[out_idx] = '-';
            }
            out_idx += 1;
        }
        
        // Ensure color is reset if the bar is completely full
        if (filled == width) {
            const reset_len = reset_code.len;
            for (0..reset_len) |i| {
                buf[out_idx] = reset_code[i];
                out_idx += 1;
            }
        }

        buf[out_idx] = ']';
        out_idx += 1;
        
        return buf[0..out_idx];
    }
};
