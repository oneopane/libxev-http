//! High-performance buffer management for HTTP operations
//!
//! This module provides efficient buffer management with:
//! - Reusable byte buffers for memory efficiency
//! - Thread-safe buffer pooling with atomic operations
//! - Performance statistics and monitoring
//! - Zero-copy operations where possible

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Reusable byte buffer for efficient memory management
/// Maintains a fixed-size buffer and current usage length
pub const Buffer = struct {
    data: []u8,
    len: usize,

    pub fn init(allocator: Allocator, size: usize) !Buffer {
        const data = try allocator.alloc(u8, size);
        return Buffer{
            .data = data,
            .len = 0,
        };
    }

    pub fn deinit(self: *Buffer, allocator: Allocator) void {
        allocator.free(self.data);
        self.* = undefined;
    }

    /// Get current valid data as read-only slice
    pub fn slice(self: *const Buffer) []const u8 {
        return self.data[0..self.len];
    }

    /// Get mutable slice for writing
    pub fn mutableSlice(self: *Buffer) []u8 {
        return self.data[self.len..];
    }

    /// Reset buffer, clearing all data but keeping underlying storage
    pub fn reset(self: *Buffer) void {
        self.len = 0;
    }

    /// Append data to buffer
    pub fn append(self: *Buffer, data: []const u8) !void {
        if (self.len + data.len > self.data.len) {
            return error.BufferOverflow;
        }
        @memcpy(self.data[self.len .. self.len + data.len], data);
        self.len += data.len;
    }

    /// Write data at specific offset
    pub fn writeAt(self: *Buffer, offset: usize, data: []const u8) !void {
        if (offset + data.len > self.data.len) {
            return error.BufferOverflow;
        }
        @memcpy(self.data[offset .. offset + data.len], data);
        if (offset + data.len > self.len) {
            self.len = offset + data.len;
        }
    }

    /// Get remaining capacity
    pub fn remaining(self: *const Buffer) usize {
        return self.data.len - self.len;
    }

    /// Check if buffer is full
    pub fn isFull(self: *const Buffer) bool {
        return self.len >= self.data.len;
    }

    /// Check if buffer is empty
    pub fn isEmpty(self: *const Buffer) bool {
        return self.len == 0;
    }
};

/// Buffer pool for reusing buffers to reduce memory allocation
/// Thread-safe version using mutex and atomic operations
pub const BufferPool = struct {
    allocator: Allocator,
    buffers: std.ArrayList(Buffer),
    available: std.ArrayList(usize),
    mutex: std.Thread.Mutex,
    buffer_size: usize,
    max_buffers: usize,

    // Statistics using atomic operations
    total_acquired: std.atomic.Value(usize),
    total_released: std.atomic.Value(usize),
    peak_usage: std.atomic.Value(usize),

    pub fn init(allocator: Allocator, buffer_size: usize, max_buffers: usize) !BufferPool {
        return BufferPool{
            .allocator = allocator,
            .buffers = std.ArrayList(Buffer).init(allocator),
            .available = std.ArrayList(usize).init(allocator),
            .mutex = std.Thread.Mutex{},
            .buffer_size = buffer_size,
            .max_buffers = max_buffers,
            .total_acquired = std.atomic.Value(usize).init(0),
            .total_released = std.atomic.Value(usize).init(0),
            .peak_usage = std.atomic.Value(usize).init(0),
        };
    }

    pub fn deinit(self: *BufferPool) void {
        for (self.buffers.items) |*buffer| {
            buffer.deinit(self.allocator);
        }
        self.buffers.deinit();
        self.available.deinit();
    }

    /// Acquire buffer, preferring reuse of existing buffers
    /// Thread-safe version
    pub fn acquire(self: *BufferPool) !*Buffer {
        // Atomic operation to update statistics
        _ = self.total_acquired.fetchAdd(1, .monotonic);

        // Use mutex to protect shared state
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.available.items.len > 0) {
            const index = self.available.pop();
            return &self.buffers.items[index.?];
        }

        if (self.buffers.items.len < self.max_buffers) {
            const buffer = try Buffer.init(self.allocator, self.buffer_size);
            try self.buffers.append(buffer);

            // Safely calculate current usage
            const current_usage = if (self.buffers.items.len >= self.available.items.len)
                self.buffers.items.len - self.available.items.len
            else
                0;

            // Atomic operation to update peak usage
            var current_peak = self.peak_usage.load(.monotonic);
            while (current_usage > current_peak) {
                const result = self.peak_usage.cmpxchgWeak(current_peak, current_usage, .monotonic, .monotonic);
                if (result == null) break; // Successfully updated
                current_peak = result.?; // Retry
            }

            return &self.buffers.items[self.buffers.items.len - 1];
        }

        return error.BufferPoolExhausted;
    }

    /// Release buffer back to pool
    /// Thread-safe version
    pub fn release(self: *BufferPool, buffer: *Buffer) !void {
        // Atomic operation to update statistics
        _ = self.total_released.fetchAdd(1, .monotonic);

        // Use mutex to protect shared state
        self.mutex.lock();
        defer self.mutex.unlock();

        const index = blk: {
            for (self.buffers.items, 0..) |*b, i| {
                if (b == buffer) {
                    break :blk i;
                }
            }
            return error.BufferNotInPool;
        };

        // Check if buffer is already in available list (prevent double release)
        for (self.available.items) |available_index| {
            if (available_index == index) {
                return error.BufferAlreadyReleased;
            }
        }

        buffer.reset();
        try self.available.append(index);
    }

    /// Get statistics
    /// Thread-safe version
    pub fn getStats(self: *BufferPool) BufferPoolStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        const used_buffers = if (self.buffers.items.len >= self.available.items.len)
            self.buffers.items.len - self.available.items.len
        else
            0;

        return BufferPoolStats{
            .total_buffers = self.buffers.items.len,
            .available_buffers = self.available.items.len,
            .used_buffers = used_buffers,
            .total_acquired = self.total_acquired.load(.monotonic),
            .total_released = self.total_released.load(.monotonic),
            .peak_usage = self.peak_usage.load(.monotonic),
        };
    }

    /// Preallocate buffers for better performance
    pub fn preallocate(self: *BufferPool, count: usize) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const actual_count = @min(count, self.max_buffers);

        for (0..actual_count) |_| {
            if (self.buffers.items.len >= self.max_buffers) break;

            const buffer = try Buffer.init(self.allocator, self.buffer_size);
            try self.buffers.append(buffer);
            try self.available.append(self.buffers.items.len - 1);
        }
    }
};

/// Buffer pool statistics
pub const BufferPoolStats = struct {
    total_buffers: usize,
    available_buffers: usize,
    used_buffers: usize,
    total_acquired: usize,
    total_released: usize,
    peak_usage: usize,

    pub fn format(self: BufferPoolStats, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("BufferPoolStats{{ total: {}, available: {}, used: {}, acquired: {}, released: {}, peak: {} }}", .{
            self.total_buffers,
            self.available_buffers,
            self.used_buffers,
            self.total_acquired,
            self.total_released,
            self.peak_usage,
        });
    }
};

// Tests
test "Buffer initialization and basic operations" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test Buffer initialization
    var buffer = try Buffer.init(allocator, 1024);
    defer buffer.deinit(allocator);

    // Verify initial state
    try testing.expect(buffer.data.len == 1024);
    try testing.expect(buffer.len == 0);
    try testing.expect(buffer.isEmpty());
    try testing.expect(!buffer.isFull());

    // Test slice method
    const slice = buffer.slice();
    try testing.expect(slice.len == 0);

    // Test append
    const test_data = "Hello, World!";
    try buffer.append(test_data);
    try testing.expect(buffer.len == test_data.len);
    try testing.expectEqualStrings(test_data, buffer.slice());

    // Test remaining capacity
    try testing.expect(buffer.remaining() == 1024 - test_data.len);

    // Test reset
    buffer.reset();
    try testing.expect(buffer.len == 0);
    try testing.expect(buffer.slice().len == 0);
    try testing.expect(buffer.isEmpty());
}

test "BufferPool acquire and release" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pool = try BufferPool.init(allocator, 256, 2);
    defer pool.deinit();

    // Acquire first buffer
    const buffer1 = try pool.acquire();
    try testing.expect(buffer1.data.len == 256);
    try testing.expect(buffer1.len == 0);
    try testing.expect(pool.buffers.items.len == 1);

    // Acquire second buffer
    const buffer2 = try pool.acquire();
    try testing.expect(buffer2.data.len == 256);
    try testing.expect(pool.buffers.items.len == 2);

    // Try to acquire third buffer (should fail)
    try testing.expectError(error.BufferPoolExhausted, pool.acquire());

    // Release first buffer
    try pool.release(buffer1);
    try testing.expect(pool.available.items.len == 1);

    // Reacquire buffer (should reuse)
    const reused_buffer = try pool.acquire();
    try testing.expect(reused_buffer == buffer1);
}

test "BufferPool statistics" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pool = try BufferPool.init(allocator, 128, 3);
    defer pool.deinit();

    // Initial stats
    var stats = pool.getStats();
    try testing.expect(stats.total_buffers == 0);
    try testing.expect(stats.used_buffers == 0);
    try testing.expect(stats.total_acquired == 0);

    // Acquire buffer
    const buffer = try pool.acquire();
    stats = pool.getStats();
    try testing.expect(stats.total_buffers == 1);
    try testing.expect(stats.used_buffers == 1);
    try testing.expect(stats.total_acquired == 1);

    // Release buffer
    try pool.release(buffer);
    stats = pool.getStats();
    try testing.expect(stats.used_buffers == 0);
    try testing.expect(stats.available_buffers == 1);
    try testing.expect(stats.total_released == 1);
}

test "Buffer overflow protection" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buffer = try Buffer.init(allocator, 10);
    defer buffer.deinit(allocator);

    // Test normal append
    try buffer.append("Hello");
    try testing.expect(buffer.len == 5);

    // Test overflow protection
    try testing.expectError(error.BufferOverflow, buffer.append("World!!!!"));

    // Buffer should remain unchanged after failed append
    try testing.expect(buffer.len == 5);
    try testing.expectEqualStrings("Hello", buffer.slice());
}
