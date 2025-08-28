const std = @import("std");
const assert = std.debug.assert;
const log = @import("lib.zig").log;

const Atomic = std.atomic.Value;
const Runtime = @import("tardy").Runtime;

const Dir = @import("tardy").Dir;
const SharedParams = @import("lib.zig").SharedParams;
const FileChain = @import("file_chain.zig").FileChain;

pub const STACK_SIZE = 1024 * 1024 * 8;
threadlocal var file_chain_counter: usize = 0;

pub fn start_frame(rt: *Runtime, shared_params: *const SharedParams) !void {
    errdefer unreachable;

    const new_dir = try Dir.cwd().create_dir(rt, shared_params.seed_string);
    log.debug("created new shared dir (seed={d})", .{shared_params.seed});

    var prng = std.Random.DefaultPrng.init(shared_params.seed);
    const rand = prng.random();

    const chain_count = shared_params.size_tasks_initial * rand.intRangeAtMost(usize, 1, 2);
    file_chain_counter = chain_count;

    log.info("creating file chains... ({d})", .{chain_count});
    for (0..chain_count) |i| {
        var prng2 = std.Random.DefaultPrng.init(shared_params.seed + i);
        const rand2 = prng2.random();

        const chain_ptr = try rt.allocator.create(FileChain);
        errdefer rt.allocator.destroy(chain_ptr);

        const sub_chain = try FileChain.generate_random_chain(
            rt.allocator,
            (shared_params.seed + i) % std.math.maxInt(usize),
        );
        defer rt.allocator.free(sub_chain);

        const subpath = try std.fmt.allocPrintSentinel(rt.allocator, "{s}-{d}", .{ shared_params.seed_string, i }, 0);
        defer rt.allocator.free(subpath);

        chain_ptr.* = try FileChain.init(
            rt.allocator,
            sub_chain,
            .{ .rel = .{ .dir = new_dir.handle, .path = subpath } },
            rand2.intRangeLessThan(usize, 1, 64),
        );
        errdefer chain_ptr.deinit();

        try rt.spawn(
            .{ chain_ptr, rt, &file_chain_counter, shared_params.seed_string },
            FileChain.chain_frame,
            STACK_SIZE,
        );
    }
}
