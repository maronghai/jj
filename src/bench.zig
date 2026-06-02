const std = @import("std");
const ops = @import("ops.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const File = Io.File;
const Writer = Io.Writer;

const BenchResult = struct {
    name: []const u8,
    iterations: u64,
    total_ns: i96,

    fn perOpUs(self: BenchResult) f64 {
        return @as(f64, @floatFromInt(self.total_ns)) /
            @as(f64, @floatFromInt(self.iterations)) / 1000.0;
    }
};

fn printRow(io: Io, r: BenchResult) void {
    var buf: [256]u8 = undefined;
    var w: Writer = .fixed(&buf);
    w.print("{s: <32} {d: >8} {d: >10} {d: >12.2}\n", .{
        r.name,
        r.iterations,
        @divTrunc(r.total_ns, 1_000_000),
        r.perOpUs(),
    }) catch {};
    File.writeStreamingAll(File.stdout(), io, w.buffered()) catch {};
}

fn writeHeader(io: Io, comptime msg: []const u8) void {
    var buf: [256]u8 = undefined;
    var w: Writer = .fixed(&buf);
    w.writeAll(msg) catch {};
    File.writeStreamingAll(File.stdout(), io, w.buffered()) catch {};
}

fn makeJson1K() []const u8 {
    return \\{"name":"alice","age":30,"active":true,"tags":["admin","dev","ops"],
        \\"address":{"city":"sf","zip":"94105"},"score":98.5}
    ;
}

fn makeJson100K(gpa: Allocator) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    try buf.appendSlice(gpa, "{\"items\":[");
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        if (i > 0) try buf.append(gpa, ',');
        try buf.appendSlice(gpa, makeJson1K());
    }
    try buf.appendSlice(gpa, "]}");
    return buf.toOwnedSlice(gpa);
}

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const io = init.io;

    writeHeader(io,
        \\=== jj benchmark (zig 0.16) ===
        \\{"benchmark","iterations","total_ms","per_op_us"}
        \\
    );

    const iters_parse = 10_000;
    const iters_ops = 10_000;
    const iters_pretty = 100;

    // --- parse 1KB ---
    {
        const json1k = makeJson1K();
        const t0 = Io.Timestamp.now(io, .real);
        var i: u64 = 0;
        while (i < iters_parse) : (i += 1) {
            var v = ops.parse(gpa, json1k) catch continue;
            v.deinit(gpa);
        }
        const t1 = Io.Timestamp.now(io, .real);
        const r = BenchResult{ .name = "parse 1KB JSON", .iterations = iters_parse, .total_ns = t1.nanoseconds - t0.nanoseconds };
        printRow(io, r);
    }

    // --- parse 100KB ---
    {
        const json100k = makeJson100K(gpa) catch unreachable;
        defer gpa.free(json100k);
        const t0 = Io.Timestamp.now(io, .real);
        var i: u64 = 0;
        while (i < 100) : (i += 1) {
            var v = ops.parse(gpa, json100k) catch continue;
            v.deinit(gpa);
        }
        const t1 = Io.Timestamp.now(io, .real);
        const r = BenchResult{ .name = "parse 100KB JSON", .iterations = 100, .total_ns = t1.nanoseconds - t0.nanoseconds };
        printRow(io, r);
    }

    // --- writeTo 1KB ---
    {
        var root = ops.parse(gpa, makeJson1K()) catch unreachable;
        defer root.deinit(gpa);
        const t0 = Io.Timestamp.now(io, .real);
        var i: u64 = 0;
        while (i < iters_ops) : (i += 1) {
            var aw: Writer.Allocating = .init(gpa);
            defer aw.deinit();
            _ = root.writeTo(&aw.writer) catch {};
        }
        const t1 = Io.Timestamp.now(io, .real);
        const r = BenchResult{ .name = "writeTo 1KB JSON", .iterations = iters_ops, .total_ns = t1.nanoseconds - t0.nanoseconds };
        printRow(io, r);
    }

    // --- writePretty 1KB ---
    {
        var root = ops.parse(gpa, makeJson1K()) catch unreachable;
        defer root.deinit(gpa);
        const t0 = Io.Timestamp.now(io, .real);
        var i: u64 = 0;
        while (i < iters_pretty) : (i += 1) {
            var aw: Writer.Allocating = .init(gpa);
            defer aw.deinit();
            _ = root.writePretty(&aw.writer, 0) catch {};
        }
        const t1 = Io.Timestamp.now(io, .real);
        const r = BenchResult{ .name = "writePretty 1KB JSON", .iterations = iters_pretty, .total_ns = t1.nanoseconds - t0.nanoseconds };
        printRow(io, r);
    }

    // --- set at root ---
    {
        const t0 = Io.Timestamp.now(io, .real);
        var i: u64 = 0;
        while (i < iters_ops) : (i += 1) {
            var root: ops.JsonValue = .{ .object = .empty };
            defer root.deinit(gpa);
            ops.set(&root, "a", .{ .integer = 1 }, gpa) catch continue;
        }
        const t1 = Io.Timestamp.now(io, .real);
        const r = BenchResult{ .name = "set at root", .iterations = iters_ops, .total_ns = t1.nanoseconds - t0.nanoseconds };
        printRow(io, r);
    }

    // --- set at depth-3 path ---
    {
        const t0 = Io.Timestamp.now(io, .real);
        var i: u64 = 0;
        while (i < iters_ops) : (i += 1) {
            var root: ops.JsonValue = .{ .object = .empty };
            defer root.deinit(gpa);
            ops.set(&root, "a.b.c", .{ .integer = 42 }, gpa) catch continue;
        }
        const t1 = Io.Timestamp.now(io, .real);
        const r = BenchResult{ .name = "set at depth-3 path", .iterations = iters_ops, .total_ns = t1.nanoseconds - t0.nanoseconds };
        printRow(io, r);
    }

    // --- get at depth-3 path ---
    {
        var root = ops.parse(gpa, "{\"a\":{\"b\":{\"c\":42}}}") catch unreachable;
        defer root.deinit(gpa);
        const t0 = Io.Timestamp.now(io, .real);
        var i: u64 = 0;
        while (i < iters_ops) : (i += 1) {
            var v = ops.get(root, "a.b.c", gpa) catch continue;
            v.deinit(gpa);
        }
        const t1 = Io.Timestamp.now(io, .real);
        const r = BenchResult{ .name = "get at depth-3 path", .iterations = iters_ops, .total_ns = t1.nanoseconds - t0.nanoseconds };
        printRow(io, r);
    }

    // --- push to array ---
    {
        const t0 = Io.Timestamp.now(io, .real);
        var i: u64 = 0;
        while (i < iters_ops) : (i += 1) {
            var root: ops.JsonValue = .{ .array = .empty };
            defer root.deinit(gpa);
            var k: usize = 0;
            while (k < 100) : (k += 1) {
                ops.push(&root, "", .{ .integer = @intCast(k) }, gpa) catch break;
            }
        }
        const t1 = Io.Timestamp.now(io, .real);
        const r = BenchResult{ .name = "push 100 to array (root)", .iterations = iters_ops, .total_ns = t1.nanoseconds - t0.nanoseconds };
        printRow(io, r);
    }

    // --- has ---
    {
        var root = ops.parse(gpa, "{\"a\":1,\"b\":2,\"c\":3,\"d\":4,\"e\":5}") catch unreachable;
        defer root.deinit(gpa);
        const t0 = Io.Timestamp.now(io, .real);
        var i: u64 = 0;
        while (i < iters_ops) : (i += 1) {
            _ = ops.has(root, "c", gpa);
        }
        const t1 = Io.Timestamp.now(io, .real);
        const r = BenchResult{ .name = "has existing key", .iterations = iters_ops, .total_ns = t1.nanoseconds - t0.nanoseconds };
        printRow(io, r);
    }

    // --- keys ---
    {
        var root = ops.parse(gpa, "{\"a\":1,\"b\":2,\"c\":3,\"d\":4,\"e\":5}") catch unreachable;
        defer root.deinit(gpa);
        const t0 = Io.Timestamp.now(io, .real);
        var i: u64 = 0;
        while (i < iters_ops) : (i += 1) {
            var owned = ops.keys(root, "", gpa) catch continue;
            for (owned.items) |k| gpa.free(k);
            owned.deinit(gpa);
        }
        const t1 = Io.Timestamp.now(io, .real);
        const r = BenchResult{ .name = "keys (5 entries)", .iterations = iters_ops, .total_ns = t1.nanoseconds - t0.nanoseconds };
        printRow(io, r);
    }

    // --- length ---
    {
        var root = ops.parse(gpa, "[1,2,3,4,5,6,7,8,9,10]") catch unreachable;
        defer root.deinit(gpa);
        const t0 = Io.Timestamp.now(io, .real);
        var i: u64 = 0;
        while (i < iters_ops) : (i += 1) {
            _ = ops.length(root, "", gpa) catch continue;
        }
        const t1 = Io.Timestamp.now(io, .real);
        const r = BenchResult{ .name = "length of array (10)", .iterations = iters_ops, .total_ns = t1.nanoseconds - t0.nanoseconds };
        printRow(io, r);
    }

    writeHeader(io, "\n=== done ===\n");
    return 0;
}
