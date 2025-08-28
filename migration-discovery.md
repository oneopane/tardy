# Migration Discovery for tardy
Date: Thu Aug 28 14:28:17 PDT 2025

## ArrayList Usage
```
src/core/pool.zig:224:test "Pool: Initalization & Deinit (ArrayList)" {
src/core/pool.zig:225:    var list_pool = try Pool(std.ArrayList(u8)).init(testing.allocator, 256, .static);
src/core/pool.zig:229:        item.* = std.ArrayList(u8){};
src/aio/apis/poll.zig:45:    fd_list: std.ArrayList(std.posix.pollfd),
src/aio/apis/poll.zig:79:        var fd_list = try std.ArrayList(std.posix.pollfd).initCapacity(allocator, size);
```

## std.io Usage
```
```

## Format Strings
```
test/e2e/main.zig:108:    std.debug.print("seed={d} passed\n", .{seed});
test/e2e/tcp_chain.zig:230:        std.debug.print("failed seed: {d}\n", .{seed});
test/e2e/tcp_chain.zig:232:            std.debug.print("action={s}\n", .{@tagName(item)});
test/e2e/file_chain.zig:223:    errdefer std.debug.print("failed seed: {d}\n", .{seed});
examples/cat/main.zig:21:            std.debug.print("{s}: No such file!", .{p.file_name});
examples/channel/main.zig:35:        std.debug.print("{d} - tardy example | {d}\n", .{ std.time.milliTimestamp(), recvd });
examples/shove/main.zig:23:    std.debug.print("size: {d}\n", .{stat.size});
examples/stat/main.zig:18:    std.debug.print("stat: {any}\n", .{stat});
```

## Writer/Reader Patterns (Critical for Writergate)
### Generic IO Types (Must be converted to concrete types)
```
```

### BufferedWriter/Reader (Deleted - needs refactoring)
```
```

### Stdout/Stderr patterns (Need buffer management)
```
```

### File IO patterns
```
```

### Stream methods that changed
```
examples/cat/main.zig:36:        try writer.writeAll(buffer[0..length]);
examples/cat/main.zig:65:        try stdout.writeAll("file name not passed in: ./cat [file name]");
examples/echo/main.zig:39:        writer.writeAll(buffer[0..recv_length]) catch |e| {
examples/stream/main.zig:75:        try stdout.writeAll("file name not passed in: ./stream [file name]");
examples/shove/main.zig:50:        try stdout.writeAll("file name not passed in: ./shove [file name]");
examples/stat/main.zig:43:        try stdout.writeAll("file name not passed in: ./stat [file name]");
examples/rmdir/main.zig:40:        try stdout.writeAll("tree name not passed in: ./rmdir [tree name]");
examples/cat/main.zig:34:        const length = try reader.readAll(&buffer);
```

### Functions with anytype parameters (likely writer/reader)
```
src/runtime/scheduler.zig:93:    pub fn spawn(self: *Scheduler, frame_ctx: anytype, comptime frame_fn: anytype, stack_size: usize) !void {
src/runtime/lib.zig:91:        comptime frame_fn: anytype,
src/runtime/storage.zig:23:    pub fn store_ptr(self: *Storage, name: []const u8, item: anytype) !void {
src/runtime/storage.zig:28:    pub fn store_alloc_ret(self: *Storage, name: []const u8, item: anytype) !*@TypeOf(item) {
src/runtime/storage.zig:40:    pub fn store_alloc(self: *Storage, name: []const u8, item: anytype) !void {
src/frame/lib.zig:16:fn EntryFn(args: anytype, comptime func: anytype) FrameEntryFn {
```

## Deprecated APIs
```
build.zig:69:        .async_backend = b.option(AsyncKind, "async", "async backend to use") orelse .auto,
src/lib.zig:70:    /// will grow to fit however many tasks/async jobs
src/lib.zig:177:                .parent_async = null,
src/lib.zig:212:                            .parent_async = parent,
```

## Migration Complexity Summary

### IO/Writer/Reader Impact (Writergate)
- GenericWriter occurrences:        0
- GenericReader occurrences:        0
- AnyWriter occurrences:        0
- AnyReader occurrences:        0
- BufferedWriter/Reader usage:        0
- stdout/stderr patterns:        5
- Functions with anytype:        6

### Other Migration Items
- ArrayList usage:        5
- Format strings with {}:        0
- Deprecated APIs:        4

