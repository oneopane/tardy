const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

const Frame = @import("../frame/lib.zig").Frame;
const Runtime = @import("../runtime/lib.zig").Runtime;

const AcceptResult = @import("../aio/completion.zig").AcceptResult;
const AcceptError = @import("../aio/completion.zig").AcceptError;
const ConnectResult = @import("../aio/completion.zig").ConnectResult;
const ConnectError = @import("../aio/completion.zig").ConnectError;
const RecvResult = @import("../aio/completion.zig").RecvResult;
const RecvError = @import("../aio/completion.zig").RecvError;
const SendResult = @import("../aio/completion.zig").SendResult;
const SendError = @import("../aio/completion.zig").SendError;

const Stream = @import("../stream.zig").Stream;

pub const Socket = struct {
    pub const Kind = enum {
        tcp,
        udp,
        unix,

        pub fn listenable(self: Kind) bool {
            return switch (self) {
                .tcp, .unix => true,
                else => false,
            };
        }
    };

    const HostPort = struct {
        host: []const u8,
        port: u16,
    };

    pub const InitKind = union(Kind) {
        tcp: HostPort,
        udp: HostPort,
        unix: []const u8,
    };

    handle: std.posix.socket_t,
    addr: std.net.Address,
    kind: Kind,

    pub fn init(kind: InitKind) !Socket {
        const addr = switch (kind) {
            .tcp, .udp => |inner| blk: {
                break :blk if (comptime builtin.os.tag == .linux)
                    try std.net.Address.resolveIp(inner.host, inner.port)
                else
                    try std.net.Address.parseIp(inner.host, inner.port);
            },
            // Not supported on Windows at the moment.
            .unix => |path| if (builtin.os.tag == .windows) unreachable else try std.net.Address.initUnix(path),
        };

        return try init_with_address(kind, addr);
    }

    pub fn init_with_address(kind: Kind, addr: std.net.Address) !Socket {
        const sock_type: u32 = switch (kind) {
            .tcp, .unix => std.posix.SOCK.STREAM,
            .udp => std.posix.SOCK.DGRAM,
        };

        const protocol: u32 = switch (kind) {
            .tcp => std.posix.IPPROTO.TCP,
            .udp => std.posix.IPPROTO.UDP,
            .unix => 0,
        };

        const flags: u32 = sock_type | std.posix.SOCK.CLOEXEC | std.posix.SOCK.NONBLOCK;
        const socket = try std.posix.socket(addr.any.family, flags, protocol);

        if (kind != .unix) {
            if (@hasDecl(std.posix.SO, "REUSEPORT_LB")) {
                try std.posix.setsockopt(
                    socket,
                    std.posix.SOL.SOCKET,
                    std.posix.SO.REUSEPORT_LB,
                    &std.mem.toBytes(@as(c_int, 1)),
                );
            } else if (@hasDecl(std.posix.SO, "REUSEPORT")) {
                try std.posix.setsockopt(
                    socket,
                    std.posix.SOL.SOCKET,
                    std.posix.SO.REUSEPORT,
                    &std.mem.toBytes(@as(c_int, 1)),
                );
            } else {
                try std.posix.setsockopt(
                    socket,
                    std.posix.SOL.SOCKET,
                    std.posix.SO.REUSEADDR,
                    &std.mem.toBytes(@as(c_int, 1)),
                );
            }
        }

        return .{ .handle = socket, .addr = addr, .kind = kind };
    }

    /// Bind the current Socket
    pub fn bind(self: Socket) !void {
        try std.posix.bind(self.handle, &self.addr.any, self.addr.getOsSockLen());
    }

    /// Listen on the Current Socket.
    pub fn listen(self: Socket, backlog: usize) !void {
        assert(self.kind.listenable());
        try std.posix.listen(self.handle, @truncate(backlog));
    }

    pub fn close(self: Socket, rt: *Runtime) !void {
        if (rt.aio.features.has_capability(.close))
            try rt.scheduler.io_await(.{ .close = self.handle })
        else
            std.posix.close(self.handle);
    }

    pub fn close_blocking(self: Socket) void {
        // todo: delete the unix socket if the
        // server is being closed
        std.posix.close(self.handle);
    }

    pub fn accept(self: Socket, rt: *Runtime) !Socket {
        assert(self.kind.listenable());
        if (rt.aio.features.has_capability(.accept)) {
            try rt.scheduler.io_await(.{
                .accept = .{
                    .socket = self.handle,
                    .kind = self.kind,
                },
            });

            const index = rt.current_task.?;
            const task = rt.scheduler.tasks.get(index);
            return try task.result.accept.unwrap();
        } else {
            var addr: std.net.Address = undefined;
            var addr_len = addr.getOsSockLen();

            const socket: std.posix.socket_t = blk: while (true) {
                break :blk std.posix.accept(
                    self.handle,
                    &addr.any,
                    &addr_len,
                    std.posix.SOCK.NONBLOCK,
                ) catch |e| return switch (e) {
                    std.posix.AcceptError.WouldBlock => {
                        Frame.yield();
                        continue;
                    },
                    std.posix.AcceptError.ConnectionAborted,
                    std.posix.AcceptError.ConnectionResetByPeer,
                    => AcceptError.ConnectionAborted,
                    std.posix.AcceptError.SocketNotListening => AcceptError.NotListening,
                    std.posix.AcceptError.ProcessFdQuotaExceeded => AcceptError.ProcessFdQuotaExceeded,
                    std.posix.AcceptError.SystemFdQuotaExceeded => AcceptError.SystemFdQuotaExceeded,
                    std.posix.AcceptError.FileDescriptorNotASocket => AcceptError.NotASocket,
                    std.posix.AcceptError.OperationNotSupported => AcceptError.OperationNotSupported,
                    else => AcceptError.Unexpected,
                };
            };

            return .{
                .handle = socket,
                .addr = addr,
                .kind = self.kind,
            };
        }
    }

    pub fn connect(self: Socket, rt: *Runtime) !void {
        if (rt.aio.features.has_capability(.connect)) {
            try rt.scheduler.io_await(.{
                .connect = .{
                    .socket = self.handle,
                    .addr = self.addr,
                    .kind = self.kind,
                },
            });

            const index = rt.current_task.?;
            const task = rt.scheduler.tasks.get(index);
            try task.result.connect.unwrap();
        } else {
            while (true) {
                break std.posix.connect(
                    self.handle,
                    &self.addr.any,
                    self.addr.getOsSockLen(),
                ) catch |e| return switch (e) {
                    std.posix.ConnectError.WouldBlock => {
                        Frame.yield();
                        continue;
                    },
                    else => ConnectError.Unexpected,
                };
            }
        }
    }

    pub fn recv(self: Socket, rt: *Runtime, buffer: []u8) !usize {
        if (rt.aio.features.has_capability(.recv)) {
            try rt.scheduler.io_await(.{
                .recv = .{
                    .socket = self.handle,
                    .buffer = buffer,
                },
            });

            const index = rt.current_task.?;
            const task = rt.scheduler.tasks.get(index);
            return try task.result.recv.unwrap();
        } else {
            const count: usize = blk: while (true) {
                break :blk std.posix.recv(self.handle, buffer, 0) catch |e| return switch (e) {
                    std.posix.RecvFromError.WouldBlock => {
                        Frame.yield();
                        continue;
                    },
                    else => RecvError.Unexpected,
                };
            };

            if (count == 0) return RecvError.Closed;
            return count;
        }
    }

    pub fn recv_all(self: Socket, rt: *Runtime, buffer: []u8) !usize {
        var length: usize = 0;

        while (length < buffer.len) {
            const result = self.recv(rt, buffer[length..]) catch |e| switch (e) {
                RecvError.Closed => return length,
                else => return e,
            };

            length += result;
        }

        return length;
    }

    pub fn send(self: Socket, rt: *Runtime, buffer: []const u8) !usize {
        if (rt.aio.features.has_capability(.send)) {
            try rt.scheduler.io_await(.{
                .send = .{
                    .socket = self.handle,
                    .buffer = buffer,
                },
            });

            const index = rt.current_task.?;
            const task = rt.scheduler.tasks.get(index);
            return try task.result.send.unwrap();
        } else {
            const count: usize = blk: while (true) {
                break :blk std.posix.send(self.handle, buffer, 0) catch |e| return switch (e) {
                    std.posix.SendError.WouldBlock => {
                        Frame.yield();
                        continue;
                    },
                    std.posix.SendError.ConnectionResetByPeer,
                    std.posix.SendError.BrokenPipe,
                    => SendError.Closed,
                    else => SendError.Unexpected,
                };
            };

            return count;
        }
    }

    pub fn send_all(self: Socket, rt: *Runtime, buffer: []const u8) !usize {
        var length: usize = 0;

        while (length < buffer.len) {
            const result = self.send(rt, buffer[length..]) catch |e| switch (e) {
                SendError.Closed => return length,
                else => return e,
            };
            length += result;
        }

        return length;
    }

    const ReadWriteContext = struct { socket: Socket, rt: *Runtime };

    // Store context at the beginning of the buffer
    pub fn writer(self: Socket, rt: *Runtime, buffer: []u8) std.Io.Writer {
        // We need at least space for the context
        if (buffer.len < @sizeOf(ReadWriteContext)) {
            @panic("Buffer too small for writer context");
        }
        
        // Store context at beginning of buffer
        const ctx_ptr: *ReadWriteContext = @ptrCast(@alignCast(buffer.ptr));
        ctx_ptr.* = .{ .socket = self, .rt = rt };
        
        // Use remaining buffer for actual buffering
        const actual_buffer = buffer[@sizeOf(ReadWriteContext)..];
        
        const vtable = struct {
            pub const writer_vtable = std.Io.Writer.VTable{
                .drain = drain,
            };
            
            fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
                // Get context from before the buffer
                const ctx_ptr_inner: *ReadWriteContext = @ptrCast(@alignCast(w.buffer.ptr - @sizeOf(ReadWriteContext)));
                
                _ = splat; // Ignore splat for now
                
                var total_written: usize = 0;
                for (data) |bytes| {
                    const written = ctx_ptr_inner.socket.send(ctx_ptr_inner.rt, bytes) catch |err| switch (err) {
                        error.OutOfMemory => return error.WriteFailed,
                        else => return error.WriteFailed,
                    };
                    total_written += written;
                    if (written < bytes.len) break;
                }
                return total_written;
            }
        };
        
        return std.Io.Writer{
            .vtable = &vtable.writer_vtable,
            .buffer = actual_buffer,
            .end = 0,
        };
    }

    pub fn reader(self: Socket, rt: *Runtime, buffer: []u8) std.Io.Reader {
        // We need at least space for the context
        if (buffer.len < @sizeOf(ReadWriteContext)) {
            @panic("Buffer too small for reader context");
        }
        
        // Store context at beginning of buffer
        const ctx_ptr: *ReadWriteContext = @ptrCast(@alignCast(buffer.ptr));
        ctx_ptr.* = .{ .socket = self, .rt = rt };
        
        // Use remaining buffer for actual buffering
        const actual_buffer = buffer[@sizeOf(ReadWriteContext)..];
        
        const vtable = struct {
            pub const reader_vtable = std.Io.Reader.VTable{
                .stream = stream_impl,
            };
            
            fn stream_impl(r: *std.Io.Reader, w: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
                // Get context from before the buffer
                const ctx_ptr_inner: *ReadWriteContext = @ptrCast(@alignCast(r.buffer.ptr - @sizeOf(ReadWriteContext)));
                
                const max_read = switch (limit) {
                    .unlimited => r.buffer.len,
                    else => @min(@intFromEnum(limit), r.buffer.len),
                };
                
                if (max_read == 0) return 0;
                
                // Read into our buffer
                const bytes_read = ctx_ptr_inner.socket.recv(ctx_ptr_inner.rt, r.buffer[0..max_read]) catch {
                    // All errors must map to StreamError set: {ReadFailed, WriteFailed, EndOfStream}
                    return error.ReadFailed;
                };
                
                if (bytes_read > 0) {
                    // Update reader state
                    r.end = bytes_read;
                    r.seek = 0;
                    
                    // Write to the output writer
                    _ = w.writeAll(r.buffer[0..bytes_read]) catch return error.WriteFailed;
                }
                
                return bytes_read;
            }
        };
        
        return std.Io.Reader{
            .vtable = &vtable.reader_vtable,
            .buffer = actual_buffer,
            .seek = 0,
            .end = 0,
        };
    }

    pub fn stream(self: *const Socket) Stream {
        return Stream{
            .inner = @ptrCast(@constCast(self)),
            .vtable = .{
                .read = struct {
                    fn read(inner: *anyopaque, rt: *Runtime, buffer: []u8) !usize {
                        const socket: *Socket = @ptrCast(@alignCast(inner));
                        return try socket.recv(rt, buffer);
                    }
                }.read,
                .write = struct {
                    fn write(inner: *anyopaque, rt: *Runtime, buffer: []const u8) !usize {
                        const socket: *Socket = @ptrCast(@alignCast(inner));
                        return try socket.send(rt, buffer);
                    }
                }.write,
            },
        };
    }
};
