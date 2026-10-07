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
};