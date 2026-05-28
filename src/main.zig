const std = @import("std");
const ops = @import("ops.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const File = Io.File;
const Dir = Io.Dir;
const Writer = Io.Writer;

const MAX_ARGS = 64;

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const io = init.io;

    var args_iter = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args_iter.deinit();

    var args_buf: [MAX_ARGS][]const u8 = undefined;
    var args_len: usize = 0;
    while (args_iter.next()) |arg| {
        if (args_len >= MAX_ARGS) break;
        args_buf[args_len] = try gpa.dupe(u8, arg);
        args_len += 1;
    }
    defer for (args_buf[0..args_len]) |a| gpa.free(a);
    const args = args_buf[0..args_len];

    if (args.len < 2) {
        try usage(File.stderr(), io);
        return 1;
    }

    var file_path: ?[]const u8 = null;
    var cmd_start: usize = 1;

    if (std.mem.eql(u8, args[1], "-f") or std.mem.eql(u8, args[1], "--file")) {
        if (args.len < 4) {
            try File.writeStreamingAll(File.stderr(), io, "error: -f requires a file path\n");
            return 1;
        }
        file_path = args[2];
        cmd_start = 3;
    }

    if (cmd_start >= args.len) {
        try usage(File.stderr(), io);
        return 1;
    }

    const stdout_file = File.stdout();
    const stderr_file = File.stderr();
    const cmd = args[cmd_start];
    const cmd_args = args[cmd_start + 1 ..];

    if (std.mem.eql(u8, cmd, "-n")) {
        return cmdNew(gpa, cmd_args, stdout_file, stderr_file, io);
    }

    const root = try readInput(gpa, file_path, io);

    if (std.mem.eql(u8, cmd, "get")) {
        return cmdGet(gpa, root, cmd_args, stdout_file, stderr_file, io);
    } else if (std.mem.eql(u8, cmd, "set")) {
        return cmdSet(gpa, root, cmd_args, stdout_file, stderr_file, io);
    } else if (std.mem.eql(u8, cmd, "del")) {
        return cmdDel(gpa, root, cmd_args, stdout_file, stderr_file, io);
    } else if (std.mem.eql(u8, cmd, "push")) {
        return cmdPush(gpa, root, cmd_args, stdout_file, stderr_file, io);
    } else if (std.mem.eql(u8, cmd, "pop")) {
        return cmdPop(gpa, root, cmd_args, stdout_file, stderr_file, io);
    } else if (std.mem.eql(u8, cmd, "pick")) {
        return cmdPick(gpa, root, cmd_args, stdout_file, stderr_file, io);
    } else if (std.mem.eql(u8, cmd, "omit")) {
        return cmdOmit(gpa, root, cmd_args, stdout_file, stderr_file, io);
    } else if (std.mem.eql(u8, cmd, "pretty")) {
        return cmdPretty(gpa, root, cmd_args, stdout_file, stderr_file, io);
    } else if (std.mem.eql(u8, cmd, "compact")) {
        return cmdCompact(gpa, root, cmd_args, stdout_file, stderr_file, io);
    } else if (std.mem.eql(u8, cmd, "type")) {
        return cmdType(gpa, root, cmd_args, stdout_file, stderr_file, io);
    } else if (std.mem.eql(u8, cmd, "merge")) {
        return cmdMerge(gpa, root, cmd_args, stdout_file, stderr_file, io);
    } else {
        var root_mut = root;
        return cmdShorthand(gpa, &root_mut, cmd, cmd_args, stdout_file, stderr_file, io);
    }
}

fn usage(stderr: File, io: Io) !void {
    try File.writeStreamingAll(stderr, io,
        \\jj - shell-first JSON CLI
        \\
        \\Usage: jj <command> [args]
        \\       jj -f <file> <command> [args]
        \\       jj <path>=<value>    (shorthand set string)
        \\       jj <path>:=<value>   (shorthand set auto-type)
        \\       jj <path>+=<value>   (shorthand array push)
        \\       jj <path>-           (shorthand delete)
        \\
        \\Commands:
        \\  new object|array       Create empty JSON
        \\  get <path> [--raw]     Get value at path
        \\  set <path> <value>     Set value at path (string)
        \\  del <path>             Delete value at path
        \\  push <path> [k=v...]   Push to array
        \\  pop <path>             Pop from array
        \\  pick <key>...          Keep only specified keys
        \\  omit <key>...          Remove specified keys
        \\  pretty                 Pretty-print JSON
        \\  compact                Compact JSON output
        \\  type <path>            Get type of value at path
        \\  merge <file>           Merge with JSON from file
        \\
        \\Options:
        \\  -f, --file <path>      Read from file instead of stdin
        \\  --raw                  Output raw value (no quotes for strings)
        \\
    );
}

fn readFileAlloc(gpa: Allocator, io: Io, path: []const u8) ![]const u8 {
    const f = try Dir.cwd().openFile(io, path, .{});
    defer f.close(io);
    var buf: [4096]u8 = undefined;
    var file_reader = f.reader(io, &buf);
    var aw = Writer.Allocating.init(gpa);
    _ = try file_reader.interface.streamRemaining(&aw.writer);
    return try gpa.dupe(u8, aw.writer.buffer[0..aw.writer.end]);
}

fn readInput(gpa: Allocator, file_path: ?[]const u8, io: Io) !ops.JsonValue {
    var input: ?[]const u8 = null;
    defer if (input) |s| gpa.free(s);

    if (file_path) |fp| {
        input = readFileAlloc(gpa, io, fp) catch |err| {
            writeErrorFmt(gpa, io, "error: cannot open file: {}\n", .{err});
            std.process.exit(1);
        };
    } else {
        var buf: [4096]u8 = undefined;
        var file_reader = File.stdin().reader(io, &buf);
        var aw = Writer.Allocating.init(gpa);
        _ = file_reader.interface.streamRemaining(&aw.writer) catch {};
        input = try gpa.dupe(u8, aw.writer.buffer[0..aw.writer.end]);
    }

    const data = input orelse "";
    if (data.len == 0) {
        const obj: std.array_hash_map.String(ops.JsonValue) = .empty;
        return .{ .object = obj };
    }
    return ops.parse(gpa, data) catch |err| {
        writeErrorFmt(gpa, io, "error: parse error: {}\n", .{err});
        std.process.exit(1);
    };
}

fn writeErrorFmt(gpa: Allocator, io: Io, comptime fmt: []const u8, args: anytype) void {
    var aw = Writer.Allocating.init(gpa);
    aw.writer.print(fmt, args) catch {};
    File.writeStreamingAll(File.stderr(), io, aw.writer.buffer[0..aw.writer.end]) catch {};
}

fn writeResult(root: ops.JsonValue, gpa: Allocator, stdout: File, io: Io) !void {
    var aw = Writer.Allocating.init(gpa);
    try root.writeTo(&aw.writer);
    try aw.writer.writeByte('\n');
    try File.writeStreamingAll(stdout, io, aw.writer.buffer[0..aw.writer.end]);
}

fn writeResultPretty(root: ops.JsonValue, gpa: Allocator, stdout: File, io: Io) !void {
    var aw = Writer.Allocating.init(gpa);
    try root.writePretty(&aw.writer, 0);
    try aw.writer.writeByte('\n');
    try File.writeStreamingAll(stdout, io, aw.writer.buffer[0..aw.writer.end]);
}

fn cmdNew(gpa: Allocator, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'new' requires 'object' or 'array'\n");
        return 1;
    }
    if (std.mem.eql(u8, cmd_args[0], "object")) {
        const obj: std.array_hash_map.String(ops.JsonValue) = .empty;
        try writeResult(.{ .object = obj }, gpa, stdout, io);
        return 0;
    } else if (std.mem.eql(u8, cmd_args[0], "array")) {
        const arr: std.ArrayList(ops.JsonValue) = .empty;
        try writeResult(.{ .array = arr }, gpa, stdout, io);
        return 0;
    } else {
        try File.writeStreamingAll(stderr, io, "error: 'new' requires 'object' or 'array'\n");
        return 1;
    }
}

fn cmdGet(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'get' requires a path\n");
        return 1;
    }
    const path = cmd_args[0];
    var is_raw = false;
    for (cmd_args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--raw")) is_raw = true;
    }
    var result = ops.get(root, path, gpa) catch |err| {
        switch (err) {
            ops.OpError.PathNotFound => {
                writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path});
                return 2;
            },
            ops.OpError.InvalidType => {
                writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path});
                return 3;
            },
            ops.OpError.InvalidPath => {
                writeErrorFmt(gpa, io, "error: invalid path: {s}\n", .{path});
                return 3;
            },
            else => return err,
        }
    };
    defer result.deinit(gpa);
    var aw = Writer.Allocating.init(gpa);
    if (is_raw) {
        switch (result) {
            .string => |s| try aw.writer.print("{s}\n", .{s}),
            .integer => |i| try aw.writer.print("{d}\n", .{i}),
            .number => |f| try aw.writer.print("{d}\n", .{f}),
            .boolean => |b| try aw.writer.print("{s}\n", .{if (b) "true" else "false"}),
            .null => try aw.writer.writeAll("null\n"),
            else => {
                try result.writeTo(&aw.writer);
                try aw.writer.writeByte('\n');
            },
        }
    } else {
        switch (result) {
            .string => |s| try aw.writer.print("\"{s}\"\n", .{s}),
            else => {
                try result.writeTo(&aw.writer);
                try aw.writer.writeByte('\n');
            },
        }
    }
    try File.writeStreamingAll(stdout, io, aw.writer.buffer[0..aw.writer.end]);
    return 0;
}

fn cmdSet(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
    if (cmd_args.len < 2) {
        try File.writeStreamingAll(stderr, io, "error: 'set' requires a path and a value\n");
        return 1;
    }
    const path = cmd_args[0];
    const value_str = cmd_args[1];
    var value: ops.JsonValue = undefined;
    var auto_type = false;
    if (cmd_args.len > 2) {
        for (cmd_args[2..]) |arg| {
            if (std.mem.eql(u8, arg, "--type") or std.mem.eql(u8, arg, ":=")) {
                auto_type = true;
                break;
            }
        }
    }
    if (auto_type) {
        value = ops.inferType(value_str);
    } else {
        value = .{ .string = value_str };
    }
    var root_mut = root;
    ops.set(&root_mut, path, value, gpa) catch |err| {
        switch (err) {
            ops.OpError.InvalidType, ops.OpError.InvalidPath => {
                writeErrorFmt(gpa, io, "error: invalid type/path: {s}\n", .{path});
                return 3;
            },
            else => return err,
        }
    };
    try writeResult(root_mut, gpa, stdout, io);
    return 0;
}

fn cmdDel(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'del' requires a path\n");
        return 1;
    }
    var root_mut = root;
    ops.del(&root_mut, cmd_args[0], gpa) catch |err| {
        switch (err) {
            ops.OpError.PathNotFound => {
                writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{cmd_args[0]});
                return 2;
            },
            ops.OpError.InvalidType => {
                writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{cmd_args[0]});
                return 3;
            },
            else => return err,
        }
    };
    try writeResult(root_mut, gpa, stdout, io);
    return 0;
}

fn cmdPush(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'push' requires a path\n");
        return 1;
    }
    const path = cmd_args[0];
    var root_mut = root;

    var value: ops.JsonValue = undefined;
    if (cmd_args.len >= 3 and containsEquals(cmd_args[1])) {
        var obj: std.array_hash_map.String(ops.JsonValue) = .empty;
        for (cmd_args[1..]) |kv| {
            if (std.mem.indexOfScalar(u8, kv, '=')) |eq_pos| {
                const k = kv[0..eq_pos];
                const v = kv[eq_pos + 1 ..];
                const key_dup = try gpa.dupe(u8, k);
                try obj.put(gpa, key_dup, .{ .string = v });
            }
        }
        value = .{ .object = obj };
    } else if (cmd_args.len >= 2) {
        value = .{ .string = cmd_args[1] };
    } else {
        value = .null;
    }

    ops.push(&root_mut, path, value, gpa) catch |err| {
        switch (err) {
            ops.OpError.PathNotFound => {
                writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path});
                return 2;
            },
            ops.OpError.InvalidType => {
                writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path});
                return 3;
            },
            else => return err,
        }
    };
    try writeResult(root_mut, gpa, stdout, io);
    return 0;
}

fn containsEquals(s: []const u8) bool {
    return std.mem.indexOfScalar(u8, s, '=') != null;
}

fn cmdPop(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'pop' requires a path\n");
        return 1;
    }
    var root_mut = root;
    const popped = ops.pop(&root_mut, cmd_args[0], gpa) catch |err| {
        switch (err) {
            ops.OpError.PathNotFound => {
                writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{cmd_args[0]});
                return 2;
            },
            ops.OpError.InvalidType => {
                writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{cmd_args[0]});
                return 3;
            },
            else => return err,
        }
    };
    try writeResult(root_mut, gpa, stdout, io);
    _ = popped;
    return 0;
}

fn cmdPick(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'pick' requires at least one key\n");
        return 1;
    }
    var root_mut = root;
    ops.pick(&root_mut, cmd_args, gpa) catch |err| {
        switch (err) {
            ops.OpError.InvalidType => {
                try File.writeStreamingAll(stderr, io, "error: pick requires an object\n");
                return 3;
            },
            else => return err,
        }
    };
    try writeResult(root_mut, gpa, stdout, io);
    return 0;
}

fn cmdOmit(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'omit' requires at least one key\n");
        return 1;
    }
    var root_mut = root;
    ops.omit(&root_mut, cmd_args, gpa) catch |err| {
        switch (err) {
            ops.OpError.InvalidType => {
                try File.writeStreamingAll(stderr, io, "error: omit requires an object\n");
                return 3;
            },
            else => return err,
        }
    };
    try writeResult(root_mut, gpa, stdout, io);
    return 0;
}

fn cmdPretty(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, _: File, io: Io) !u8 {
    _ = cmd_args;
    try writeResultPretty(root, gpa, stdout, io);
    return 0;
}

fn cmdCompact(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, _: File, io: Io) !u8 {
    _ = cmd_args;
    try writeResult(root, gpa, stdout, io);
    return 0;
}

fn cmdType(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'type' requires a path\n");
        return 1;
    }
    var result = ops.get(root, cmd_args[0], gpa) catch |err| {
        switch (err) {
            ops.OpError.PathNotFound => {
                writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{cmd_args[0]});
                return 2;
            },
            ops.OpError.InvalidType => {
                writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{cmd_args[0]});
                return 3;
            },
            else => return err,
        }
    };
    defer result.deinit(gpa);
    var aw = Writer.Allocating.init(gpa);
    try aw.writer.print("{s}\n", .{result.getTypeName()});
    try File.writeStreamingAll(stdout, io, aw.writer.buffer[0..aw.writer.end]);
    return 0;
}

fn cmdMerge(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'merge' requires a file path\n");
        return 1;
    }
    const merge_input = readFileAlloc(gpa, io, cmd_args[0]) catch |err| {
        writeErrorFmt(gpa, io, "error: cannot open file: {}\n", .{err});
        return 1;
    };
    defer gpa.free(merge_input);

    const other = ops.parse(gpa, merge_input) catch |err| {
        writeErrorFmt(gpa, io, "error: parse error in merge file: {}\n", .{err});
        return 1;
    };

    var root_mut = root;
    switch (root_mut) {
        .object => |*obj| {
            switch (other) {
                .object => |other_obj| {
                    var iter = other_obj.iterator();
                    while (iter.next()) |entry| {
                        const key_dup = try gpa.dupe(u8, entry.key_ptr.*);
                        const val_dup = try entry.value_ptr.*.clone(gpa);
                        const existing = try obj.fetchPut(gpa, key_dup, val_dup);
                        if (existing) |old| {
                            var old_val = old.value;
                            old_val.deinit(gpa);
                            gpa.free(old.key);
                        }
                    }
                },
                else => {
                    try File.writeStreamingAll(stderr, io, "error: merge source must be an object\n");
                    return 3;
                },
            }
        },
        else => {
            try File.writeStreamingAll(stderr, io, "error: merge target must be an object\n");
            return 3;
        },
    }
    try writeResult(root_mut, gpa, stdout, io);
    return 0;
}

fn cmdShorthand(gpa: Allocator, root: *ops.JsonValue, cmd: []const u8, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
    _ = cmd_args;
    if (cmd.len == 0) {
        try File.writeStreamingAll(stderr, io, "error: unknown command\n");
        return 1;
    }
    const last = cmd[cmd.len - 1];
    if (last == '-') {
        const path = cmd[0 .. cmd.len - 1];
        ops.del(root, path, gpa) catch |err| {
            switch (err) {
                ops.OpError.PathNotFound => {
                    writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path});
                    return 2;
                },
                else => return err,
            }
        };
        try writeResult(root.*, gpa, stdout, io);
        return 0;
    }
    if (std.mem.indexOfScalar(u8, cmd, '=')) |eq_pos| {
        const path = cmd[0..eq_pos];
        const rest = cmd[eq_pos + 1 ..];
        if (eq_pos > 0 and cmd[eq_pos - 1] == ':') {
            const actual_path = cmd[0 .. eq_pos - 1];
            const value = ops.inferType(rest);
            ops.set(root, actual_path, value, gpa) catch |err| {
                switch (err) {
                    ops.OpError.InvalidType => {
                        writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{actual_path});
                        return 3;
                    },
                    else => return err,
                }
            };
        } else if (eq_pos > 0 and cmd[eq_pos - 1] == '+') {
            const actual_path = cmd[0 .. eq_pos - 1];
            const value: ops.JsonValue = .{ .string = rest };
            ops.push(root, actual_path, value, gpa) catch |err| {
                switch (err) {
                    ops.OpError.PathNotFound => {
                        writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{actual_path});
                        return 2;
                    },
                    ops.OpError.InvalidType => {
                        writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{actual_path});
                        return 3;
                    },
                    else => return err,
                }
            };
        } else {
            const value: ops.JsonValue = .{ .string = rest };
            ops.set(root, path, value, gpa) catch |err| {
                switch (err) {
                    ops.OpError.InvalidType => {
                        writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path});
                        return 3;
                    },
                    else => return err,
                }
            };
        }
        try writeResult(root.*, gpa, stdout, io);
        return 0;
    }
    writeErrorFmt(gpa, io, "error: unknown command: {s}\n", .{cmd});
    return 1;
}
