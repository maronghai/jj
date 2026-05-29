const std = @import("std");
const ops = @import("ops.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const File = Io.File;
const Dir = Io.Dir;
const Writer = Io.Writer;

const MAX_ARGS = 128;

const Cmd = enum {
    set,
    del,
    push,
    pop,
    pick,
    omit,
    pretty,
    compact,
    type,
    merge,
    @"new",
    get,
};

const CmdInfo = struct {
    cmd: Cmd,
    args_start: usize,
    args_end: usize,
};

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

    var commands: [32]CmdInfo = undefined;
    var cmd_count: usize = 0;
    var i: usize = cmd_start;

    while (i < args.len) {
        const token = args[i];
        const maybe_cmd = parseCmdName(token);
        if (maybe_cmd) |c| {
            const start = i + 1;
            i += 1;
            var end = start;
            while (end < args.len) : (end += 1) {
                if (parseCmdName(args[end]) != null) break;
            }
            if (cmd_count < commands.len) {
                commands[cmd_count] = .{ .cmd = c, .args_start = start, .args_end = end };
                cmd_count += 1;
            }
            i = end;
        } else {
            var root_mut = try readInput(gpa, file_path, io, false);
            try execShorthand(gpa, &root_mut, token, stdout_file, stderr_file, io);
            return 0;
        }
    }

    if (cmd_count == 0) {
        try usage(File.stderr(), io);
        return 1;
    }

    if (commands[0].cmd == .@"new") {
        return execNew(gpa, args[commands[0].args_start..commands[0].args_end], stdout_file, stderr_file, io);
    }

    if (commands[0].cmd == .get and cmd_count == 1) {
        const root = try readInput(gpa, file_path, io, false);
        return execGet(gpa, root, args[commands[0].args_start..commands[0].args_end], stdout_file, stderr_file, io);
    }

    var has_set = false;
    var has_push = false;
    var push_has_dot_path = false;
    for (commands[0..cmd_count]) |info| {
        if (info.cmd == .set) has_set = true;
        if (info.cmd == .push) {
            has_push = true;
            const ca = args[info.args_start..info.args_end];
            if (ca.len >= 1 and ca[0].len > 1 and ca[0][0] == '.' and ca[0][1] != '.') {
                push_has_dot_path = true;
            }
        }
    }
    const default_array = has_push and !has_set and !push_has_dot_path;

    var root_mut = try readInput(gpa, file_path, io, default_array);

    var last_was_pretty = false;
    for (commands[0..cmd_count]) |info| {
        const cmd_args = args[info.args_start..info.args_end];
        switch (info.cmd) {
            .set => try execSet(gpa, &root_mut, cmd_args, stderr_file, io),
            .del => try execDel(gpa, &root_mut, cmd_args, stderr_file, io),
            .push => try execPush(gpa, &root_mut, cmd_args, stderr_file, io),
            .pop => try execPop(gpa, &root_mut, cmd_args, stderr_file, io),
            .pick => try execPick(gpa, &root_mut, cmd_args, stderr_file, io),
            .omit => try execOmit(gpa, &root_mut, cmd_args, stderr_file, io),
            .merge => try execMerge(gpa, &root_mut, cmd_args, io, stderr_file, io),
            .pretty => last_was_pretty = true,
            .compact => last_was_pretty = false,
            .type => {
                if (cmd_count == 1) {
                    return execType(gpa, root_mut, cmd_args, stdout_file, stderr_file, io);
                }
            },
            .@"new" => {},
            .get => {
                if (cmd_count == 1) {
                    return execGet(gpa, root_mut, cmd_args, stdout_file, stderr_file, io);
                }
            },
        }
    }

    if (last_was_pretty) {
        try writeResultPretty(root_mut, gpa, stdout_file, io);
    } else {
        try writeResult(root_mut, gpa, stdout_file, io);
    }
    return 0;
}

fn parseCmdName(token: []const u8) ?Cmd {
    if (std.mem.eql(u8, token, "set")) return .set;
    if (std.mem.eql(u8, token, "del")) return .del;
    if (std.mem.eql(u8, token, "push")) return .push;
    if (std.mem.eql(u8, token, "pop")) return .pop;
    if (std.mem.eql(u8, token, "pick")) return .pick;
    if (std.mem.eql(u8, token, "omit")) return .omit;
    if (std.mem.eql(u8, token, "pretty")) return .pretty;
    if (std.mem.eql(u8, token, "compact")) return .compact;
    if (std.mem.eql(u8, token, "type")) return .type;
    if (std.mem.eql(u8, token, "merge")) return .merge;
    if (std.mem.eql(u8, token, "new")) return .@"new";
    if (std.mem.eql(u8, token, "get")) return .get;
    return null;
}

fn usage(stderr: File, io: Io) !void {
    try File.writeStreamingAll(stderr, io,
        \\jj - shell-first JSON CLI
        \\
        \\Usage: jj <command> [args] [command> [args] ...
        \\       jj -f <file> <command> [args] ...
        \\       jj <path>=<value>    (shorthand set string)
        \\       jj <path>:=<value>   (shorthand set auto-type)
        \\       jj <path>+=<value>   (shorthand array push)
        \\       jj <path>-           (shorthand delete)
        \\
        \\Multiple commands can be chained:
        \\  jj set a 1 del b push c v1 v2 omit d merge f
        \\
        \\Commands:
        \\  new object|array       Create empty JSON
        \\  get <path> [--raw]     Get value at path
        \\  set <p> <v> [p v]...   Set path=value pairs (string)
        \\  del <path>             Delete value at path
        \\  push <path> <v>...     Push values to array
        \\  push <path> <k> <v>... Push object (even key-value pairs)
        \\  push <path> <k=v>...   Push object (k=v syntax)
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

fn readInput(gpa: Allocator, file_path: ?[]const u8, io: Io, default_array: bool) !ops.JsonValue {
    if (file_path) |fp| {
        const data = readFileAlloc(gpa, io, fp) catch |err| {
            writeErrorFmt(gpa, io, "error: cannot open file: {}\n", .{err});
            std.process.exit(1);
        };
        defer gpa.free(data);
        if (data.len == 0) {
            if (default_array) {
                const arr: std.ArrayList(ops.JsonValue) = .empty;
                return .{ .array = arr };
            } else {
                const obj: std.array_hash_map.String(ops.JsonValue) = .empty;
                return .{ .object = obj };
            }
        }
        return ops.parse(gpa, data) catch |err| {
            writeErrorFmt(gpa, io, "error: parse error: {}\n", .{err});
            std.process.exit(1);
        };
    }

    const is_tty = File.stdin().isTty(io) catch false;
    if (is_tty) {
        if (default_array) {
            const arr: std.ArrayList(ops.JsonValue) = .empty;
            return .{ .array = arr };
        } else {
            const obj: std.array_hash_map.String(ops.JsonValue) = .empty;
            return .{ .object = obj };
        }
    }

    var buf: [4096]u8 = undefined;
    var file_reader = File.stdin().reader(io, &buf);
    var aw = Writer.Allocating.init(gpa);
    _ = file_reader.interface.streamRemaining(&aw.writer) catch {};
    const data = aw.writer.buffer[0..aw.writer.end];
    if (data.len == 0) {
        if (default_array) {
            const arr: std.ArrayList(ops.JsonValue) = .empty;
            return .{ .array = arr };
        } else {
            const obj: std.array_hash_map.String(ops.JsonValue) = .empty;
            return .{ .object = obj };
        }
    }
    const input = try gpa.dupe(u8, data);
    defer gpa.free(input);
    return ops.parse(gpa, input) catch |err| {
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

fn execNew(gpa: Allocator, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
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

fn execGet(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'get' requires a path\n");
        return 1;
    }
    const path = normalizePath(cmd_args[0]);
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

fn normalizePath(path: []const u8) []const u8 {
    if (path.len == 0) return path;
    if (std.mem.eql(u8, path, ".")) return "";
    if (path[0] == '.') return path[1..];
    return path;
}

fn parseValue(gpa: Allocator, str: []const u8) !ops.JsonValue {
    if (str.len > 0 and (str[0] == '{' or str[0] == '[')) {
        return ops.parse(gpa, str);
    }
    return .{ .string = try gpa.dupe(u8, str) };
}

fn execSet(gpa: Allocator, root: *ops.JsonValue, cmd_args: []const []const u8, stderr: File, io: Io) !void {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'set' requires at least one argument\n");
        return;
    }
    var i: usize = 0;
    while (i < cmd_args.len) {
        const arg = cmd_args[i];

        if (std.mem.indexOfScalar(u8, arg, '=')) |eq_pos| {
            if (eq_pos > 0 and arg[eq_pos - 1] == ':') {
                const path = normalizePath(arg[0 .. eq_pos - 1]);
                const val_str = arg[eq_pos + 1 ..];
                var value: ops.JsonValue = undefined;
                if (val_str.len > 0 and (val_str[0] == '{' or val_str[0] == '[')) {
                    var json_buf: std.ArrayList(u8) = .empty;
                    defer json_buf.deinit(gpa);
                    try json_buf.appendSlice(gpa, val_str);
                    var json_end: usize = i + 1;
                    while (json_end < cmd_args.len) {
                        if (ops.parse(gpa, json_buf.items)) |_| break else |_| {}
                        try json_buf.append(gpa, ' ');
                        try json_buf.appendSlice(gpa, cmd_args[json_end]);
                        json_end += 1;
                    }
                    value = ops.parse(gpa, json_buf.items) catch |err| {
                        writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{json_buf.items});
                        return err;
                    };
                    i = json_end;
                } else {
                    value = ops.inferType(val_str);
                    if (value == .string) {
                        value = .{ .string = try gpa.dupe(u8, value.string) };
                    }
                    i += 1;
                }
                ops.set(root, path, value, gpa) catch |err| {
                    switch (err) {
                        ops.OpError.InvalidType, ops.OpError.InvalidPath => {
                            writeErrorFmt(gpa, io, "error: invalid type/path: {s}\n", .{path});
                        },
                        else => return err,
                    }
                };
                continue;
            }
            if (eq_pos > 0 and arg[eq_pos - 1] == '+') {
                const path = normalizePath(arg[0 .. eq_pos - 1]);
                const val_str = arg[eq_pos + 1 ..];
                var value: ops.JsonValue = undefined;
                if (val_str.len > 0 and (val_str[0] == '{' or val_str[0] == '[')) {
                    var json_buf: std.ArrayList(u8) = .empty;
                    defer json_buf.deinit(gpa);
                    try json_buf.appendSlice(gpa, val_str);
                    var json_end: usize = i + 1;
                    while (json_end < cmd_args.len) {
                        if (ops.parse(gpa, json_buf.items)) |_| break else |_| {}
                        try json_buf.append(gpa, ' ');
                        try json_buf.appendSlice(gpa, cmd_args[json_end]);
                        json_end += 1;
                    }
                    value = ops.parse(gpa, json_buf.items) catch |err| {
                        writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{json_buf.items});
                        return err;
                    };
                    i = json_end;
                } else {
                    value = ops.inferType(val_str);
                    if (value == .string) {
                        value = .{ .string = try gpa.dupe(u8, value.string) };
                    }
                    i += 1;
                }
                ops.push(root, path, value, gpa) catch |err| {
                    switch (err) {
                        ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                        ops.OpError.InvalidType => writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path}),
                        else => return err,
                    }
                };
                continue;
            }
            if (eq_pos > 0) {
                const path = normalizePath(arg[0..eq_pos]);
                const val_str = arg[eq_pos + 1 ..];
                var value: ops.JsonValue = undefined;
                if (val_str.len > 0 and (val_str[0] == '{' or val_str[0] == '[')) {
                    var json_buf: std.ArrayList(u8) = .empty;
                    defer json_buf.deinit(gpa);
                    try json_buf.appendSlice(gpa, val_str);
                    var json_end: usize = i + 1;
                    while (json_end < cmd_args.len) {
                        if (ops.parse(gpa, json_buf.items)) |_| break else |_| {}
                        try json_buf.append(gpa, ' ');
                        try json_buf.appendSlice(gpa, cmd_args[json_end]);
                        json_end += 1;
                    }
                    value = ops.parse(gpa, json_buf.items) catch |err| {
                        writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{json_buf.items});
                        return err;
                    };
                    i = json_end;
                } else {
                    value = parseValue(gpa, val_str) catch |err| {
                        writeErrorFmt(gpa, io, "error: invalid value: {s}\n", .{val_str});
                        return err;
                    };
                    i += 1;
                }
                ops.set(root, path, value, gpa) catch |err| {
                    switch (err) {
                        ops.OpError.InvalidType, ops.OpError.InvalidPath => {
                            writeErrorFmt(gpa, io, "error: invalid type/path: {s}\n", .{path});
                        },
                        else => return err,
                    }
                };
                continue;
            }
        }

        if (arg.len > 0 and arg[arg.len - 1] == '-') {
            const path = normalizePath(arg[0 .. arg.len - 1]);
            ops.del(root, path, gpa) catch |err| {
                switch (err) {
                    ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                    else => return err,
                }
            };
            i += 1;
            continue;
        }

        if (i + 1 >= cmd_args.len) {
            try File.writeStreamingAll(stderr, io, "error: 'set' requires path value pairs\n");
            return;
        }
        const path = normalizePath(arg);
        const value_str = cmd_args[i + 1];
        var auto_type = false;
        if (std.mem.eql(u8, value_str, "--type") or std.mem.eql(u8, value_str, ":=")) {
            auto_type = true;
            i += 2;
            if (i >= cmd_args.len) {
                try File.writeStreamingAll(stderr, io, "error: 'set' := requires a value\n");
                return;
            }
        }
        const actual_val = if (auto_type) cmd_args[i] else value_str;
        var value: ops.JsonValue = undefined;
        if (auto_type) {
            value = ops.inferType(actual_val);
            if (value == .string) {
                value = .{ .string = try gpa.dupe(u8, value.string) };
            }
            i += 1;
        } else if (actual_val.len > 0 and (actual_val[0] == '{' or actual_val[0] == '[')) {
            var json_buf: std.ArrayList(u8) = .empty;
            defer json_buf.deinit(gpa);
            try json_buf.appendSlice(gpa, actual_val);
            var json_end: usize = i + 1;
            if (!auto_type) json_end = i + 2;
            while (json_end < cmd_args.len) {
                if (ops.parse(gpa, json_buf.items)) |_| {
                    break;
                } else |_| {}
                try json_buf.append(gpa, ' ');
                try json_buf.appendSlice(gpa, cmd_args[json_end]);
                json_end += 1;
            }
            value = ops.parse(gpa, json_buf.items) catch |err| {
                writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{json_buf.items});
                return err;
            };
            i = json_end;
        } else {
            value = parseValue(gpa, actual_val) catch |err| {
                writeErrorFmt(gpa, io, "error: invalid value: {s}\n", .{actual_val});
                return err;
            };
            if (auto_type) {
                i += 1;
            } else {
                i += 2;
            }
        }
        ops.set(root, path, value, gpa) catch |err| {
            switch (err) {
                ops.OpError.InvalidType, ops.OpError.InvalidPath => {
                    writeErrorFmt(gpa, io, "error: invalid type/path: {s}\n", .{path});
                },
                else => return err,
            }
        };
    }
}

fn execDel(gpa: Allocator, root: *ops.JsonValue, cmd_args: []const []const u8, stderr: File, io: Io) !void {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'del' requires a path\n");
        return;
    }
    ops.del(root, normalizePath(cmd_args[0]), gpa) catch |err| {
        switch (err) {
            ops.OpError.PathNotFound => {
                writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{cmd_args[0]});
            },
            ops.OpError.InvalidType => {
                writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{cmd_args[0]});
            },
            else => return err,
        }
    };
}

fn execPush(gpa: Allocator, root: *ops.JsonValue, cmd_args: []const []const u8, stderr: File, io: Io) !void {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'push' requires at least one value\n");
        return;
    }

    const first_dot = cmd_args[0].len == 0 or std.mem.eql(u8, cmd_args[0], ".") or (cmd_args[0].len > 1 and cmd_args[0][0] == '.' and cmd_args[0][1] != '.');
    const is_root_array = root.* == .array;

    if (first_dot and cmd_args[0].len <= 1 and is_root_array) {
        const path: []const u8 = "";
        const rest = cmd_args[1..];
        if (rest.len == 0) {
            ops.push(root, path, .null, gpa) catch |err| {
                switch (err) {
                    ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                    ops.OpError.InvalidType => writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path}),
                    else => return err,
                }
            };
            return;
        }
        var obj: std.array_hash_map.String(ops.JsonValue) = .empty;
        errdefer {
            var it = obj.iterator();
            while (it.next()) |e| {
                gpa.free(e.key_ptr.*);
                var v = e.value_ptr.*;
                v.deinit(gpa);
            }
            obj.deinit(gpa);
        }
        var k: usize = 0;
        while (k + 1 < rest.len) {
            const key = rest[k];
            const val_str = rest[k + 1];
            const key_dup = try gpa.dupe(u8, key);
            var val: ops.JsonValue = undefined;
            if (looksLikeJson(val_str)) {
                var json_buf: std.ArrayList(u8) = .empty;
                defer json_buf.deinit(gpa);
                try json_buf.appendSlice(gpa, val_str);
                var j: usize = k + 2;
                while (j < rest.len) {
                    if (ops.parse(gpa, json_buf.items)) |_| break else |_| {}
                    try json_buf.append(gpa, ' ');
                    try json_buf.appendSlice(gpa, rest[j]);
                    j += 1;
                }
                val = ops.parse(gpa, json_buf.items) catch |err| {
                    writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{json_buf.items});
                    return err;
                };
                k = j;
            } else {
                val = ops.inferType(val_str);
                if (val == .string) {
                    val = .{ .string = try gpa.dupe(u8, val.string) };
                }
                k += 2;
            }
            try obj.put(gpa, key_dup, val);
        }
        if (k < rest.len and obj.count() == 0) {
            const val_str = rest[k];
            if (looksLikeJson(val_str)) {
                var json_buf: std.ArrayList(u8) = .empty;
                defer json_buf.deinit(gpa);
                for (rest[k..], 0..) |s, idx| {
                    if (idx > 0) try json_buf.append(gpa, ' ');
                    try json_buf.appendSlice(gpa, s);
                }
                const val = ops.parse(gpa, json_buf.items) catch |err| {
                    writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{json_buf.items});
                    return err;
                };
                ops.push(root, path, val, gpa) catch |err| {
                    switch (err) {
                        ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                        ops.OpError.InvalidType => writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path}),
                        else => return err,
                    }
                };
                return;
            }
        }
        ops.push(root, path, .{ .object = obj }, gpa) catch |err| {
            switch (err) {
                ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                ops.OpError.InvalidType => writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path}),
                else => return err,
            }
        };
        return;
    }

    if (first_dot and cmd_args[0].len <= 1 and !is_root_array) {
        const rest = cmd_args[1..];
        var k: usize = 0;
        while (k + 1 < rest.len) {
            const key = rest[k];
            const val_str = rest[k + 1];
            var val: ops.JsonValue = undefined;
            if (looksLikeJson(val_str)) {
                var json_buf: std.ArrayList(u8) = .empty;
                defer json_buf.deinit(gpa);
                try json_buf.appendSlice(gpa, val_str);
                var j: usize = k + 2;
                while (j < rest.len) {
                    if (ops.parse(gpa, json_buf.items)) |_| break else |_| {}
                    try json_buf.append(gpa, ' ');
                    try json_buf.appendSlice(gpa, rest[j]);
                    j += 1;
                }
                val = ops.parse(gpa, json_buf.items) catch |err| {
                    writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{json_buf.items});
                    return err;
                };
                k = j;
            } else {
                val = ops.inferType(val_str);
                if (val == .string) {
                    val = .{ .string = try gpa.dupe(u8, val.string) };
                }
                k += 2;
            }
            ops.set(root, key, val, gpa) catch |err| {
                switch (err) {
                    ops.OpError.InvalidType, ops.OpError.InvalidPath => {
                        writeErrorFmt(gpa, io, "error: invalid type/path: {s}\n", .{key});
                    },
                    else => return err,
                }
            };
        }
        return;
    }

    if (first_dot and cmd_args[0].len > 1) {
        const path = normalizePath(cmd_args[0]);
        const rest = cmd_args[1..];
        if (rest.len == 0) {
            ops.push(root, path, .null, gpa) catch |err| {
                switch (err) {
                    ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                    ops.OpError.InvalidType => writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path}),
                    else => return err,
                }
            };
            return;
        }
        var obj: std.array_hash_map.String(ops.JsonValue) = .empty;
        errdefer {
            var it = obj.iterator();
            while (it.next()) |e| {
                gpa.free(e.key_ptr.*);
                var v = e.value_ptr.*;
                v.deinit(gpa);
            }
            obj.deinit(gpa);
        }
        var k: usize = 0;
        while (k + 1 < rest.len) {
            const key = rest[k];
            const val_str = rest[k + 1];
            const key_dup = try gpa.dupe(u8, key);
            var val: ops.JsonValue = undefined;
            if (looksLikeJson(val_str)) {
                var json_buf: std.ArrayList(u8) = .empty;
                defer json_buf.deinit(gpa);
                try json_buf.appendSlice(gpa, val_str);
                var j: usize = k + 2;
                while (j < rest.len) {
                    if (ops.parse(gpa, json_buf.items)) |_| break else |_| {}
                    try json_buf.append(gpa, ' ');
                    try json_buf.appendSlice(gpa, rest[j]);
                    j += 1;
                }
                val = ops.parse(gpa, json_buf.items) catch |err| {
                    writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{json_buf.items});
                    return err;
                };
                k = j;
            } else {
                val = ops.inferType(val_str);
                if (val == .string) {
                    val = .{ .string = try gpa.dupe(u8, val.string) };
                }
                k += 2;
            }
            try obj.put(gpa, key_dup, val);
        }
        if (obj.count() > 0) {
            ops.push(root, path, .{ .object = obj }, gpa) catch |err| {
                switch (err) {
                    ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                    ops.OpError.InvalidType => writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path}),
                    else => return err,
                }
            };
        } else if (rest.len >= 1) {
            if (looksLikeJson(rest[0])) {
                var json_buf: std.ArrayList(u8) = .empty;
                defer json_buf.deinit(gpa);
                for (rest, 0..) |s, idx| {
                    if (idx > 0) try json_buf.append(gpa, ' ');
                    try json_buf.appendSlice(gpa, s);
                }
                const val = ops.parse(gpa, json_buf.items) catch |err| {
                    writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{json_buf.items});
                    return err;
                };
                ops.push(root, path, val, gpa) catch |err| {
                    switch (err) {
                        ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                        ops.OpError.InvalidType => writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path}),
                        else => return err,
                    }
                };
            } else {
                for (rest) |val_str| {
                    var val = ops.inferType(val_str);
                    if (val == .string) val = .{ .string = try gpa.dupe(u8, val.string) };
                    ops.push(root, path, val, gpa) catch |err| {
                        switch (err) {
                            ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                            ops.OpError.InvalidType => writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path}),
                            else => return err,
                        }
                    };
                }
            }
        }
        return;
    }

    const path: []const u8 = if (is_root_array) "" else normalizePath(cmd_args[0]);
    const rest = if (is_root_array) cmd_args[0..] else cmd_args[1..];

    if (rest.len == 0) {
        ops.push(root, path, .null, gpa) catch |err| {
            switch (err) {
                ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                ops.OpError.InvalidType => writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path}),
                else => return err,
            }
        };
        return;
    }

    if (rest.len >= 2 and containsEquals(rest[0])) {
        var obj: std.array_hash_map.String(ops.JsonValue) = .empty;
        for (rest) |kv| {
            if (std.mem.indexOfScalar(u8, kv, '=')) |eq_pos| {
                const key_dup = try gpa.dupe(u8, kv[0..eq_pos]);
                const val = ops.inferType(kv[eq_pos + 1 ..]);
                const val_owned: ops.JsonValue = if (val == .string) .{ .string = try gpa.dupe(u8, val.string) } else val;
                try obj.put(gpa, key_dup, val_owned);
            }
        }
        ops.push(root, path, .{ .object = obj }, gpa) catch |err| {
            switch (err) {
                ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                ops.OpError.InvalidType => writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path}),
                else => return err,
            }
        };
    } else if (looksLikeJson(rest[0])) {
        var k: usize = 0;
        while (k < rest.len) {
            if (!looksLikeJson(rest[k])) {
                var val = ops.inferType(rest[k]);
                if (val == .string) val = .{ .string = try gpa.dupe(u8, val.string) };
                ops.push(root, path, val, gpa) catch |err| {
                    switch (err) {
                        ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                        ops.OpError.InvalidType => writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path}),
                        else => return err,
                    }
                };
                k += 1;
                continue;
            }
            var json_buf: std.ArrayList(u8) = .empty;
            defer json_buf.deinit(gpa);
            try json_buf.appendSlice(gpa, rest[k]);
            k += 1;
            while (k < rest.len) {
                if (ops.parse(gpa, json_buf.items)) |_| break else |_| {}
                try json_buf.append(gpa, ' ');
                try json_buf.appendSlice(gpa, rest[k]);
                k += 1;
            }
            const value = ops.parse(gpa, json_buf.items) catch |err| {
                writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{json_buf.items});
                return err;
            };
            ops.push(root, path, value, gpa) catch |err| {
                switch (err) {
                    ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                    ops.OpError.InvalidType => writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path}),
                    else => return err,
                }
            };
        }
    } else {
        var m: usize = 0;
        while (m < rest.len) {
            if (looksLikeJson(rest[m])) {
                var json_buf: std.ArrayList(u8) = .empty;
                defer json_buf.deinit(gpa);
                try json_buf.appendSlice(gpa, rest[m]);
                m += 1;
                while (m < rest.len) {
                    if (ops.parse(gpa, json_buf.items)) |_| break else |_| {}
                    try json_buf.append(gpa, ' ');
                    try json_buf.appendSlice(gpa, rest[m]);
                    m += 1;
                }
                const value = ops.parse(gpa, json_buf.items) catch |err| {
                    writeErrorFmt(gpa, io, "error: invalid JSON value: {s}\n", .{json_buf.items});
                    return err;
                };
                ops.push(root, path, value, gpa) catch |err| {
                    switch (err) {
                        ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                        ops.OpError.InvalidType => writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path}),
                        else => return err,
                    }
                };
            } else {
                var val = ops.inferType(rest[m]);
                if (val == .string) val = .{ .string = try gpa.dupe(u8, val.string) };
                ops.push(root, path, val, gpa) catch |err| {
                    switch (err) {
                        ops.OpError.PathNotFound => writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path}),
                        ops.OpError.InvalidType => writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path}),
                        else => return err,
                    }
                };
                m += 1;
            }
        }
    }
}

fn containsEquals(s: []const u8) bool {
    return std.mem.indexOfScalar(u8, s, '=') != null;
}

fn looksLikeJson(s: []const u8) bool {
    return s.len > 0 and (s[0] == '{' or s[0] == '[');
}

fn execPop(gpa: Allocator, root: *ops.JsonValue, cmd_args: []const []const u8, stderr: File, io: Io) !void {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'pop' requires a path\n");
        return;
    }
    const popped = ops.pop(root, normalizePath(cmd_args[0]), gpa) catch |err| {
        switch (err) {
            ops.OpError.PathNotFound => {
                writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{cmd_args[0]});
            },
            ops.OpError.InvalidType => {
                writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{cmd_args[0]});
            },
            else => return err,
        }
        return;
    };
    _ = popped;
}

fn execPick(gpa: Allocator, root: *ops.JsonValue, cmd_args: []const []const u8, stderr: File, io: Io) !void {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'pick' requires at least one key\n");
        return;
    }
    ops.pick(root, cmd_args, gpa) catch |err| {
        switch (err) {
            ops.OpError.InvalidType => {
                try File.writeStreamingAll(stderr, io, "error: pick requires an object\n");
            },
            else => return err,
        }
    };
}

fn execOmit(gpa: Allocator, root: *ops.JsonValue, cmd_args: []const []const u8, stderr: File, io: Io) !void {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'omit' requires at least one key\n");
        return;
    }
    ops.omit(root, cmd_args, gpa) catch |err| {
        switch (err) {
            ops.OpError.InvalidType => {
                try File.writeStreamingAll(stderr, io, "error: omit requires an object\n");
            },
            else => return err,
        }
    };
}

fn execType(gpa: Allocator, root: ops.JsonValue, cmd_args: []const []const u8, stdout: File, stderr: File, io: Io) !u8 {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'type' requires a path\n");
        return 1;
    }
    const path = normalizePath(cmd_args[0]);
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
            else => return err,
        }
    };
    defer result.deinit(gpa);
    var aw = Writer.Allocating.init(gpa);
    try aw.writer.print("{s}\n", .{result.getTypeName()});
    try File.writeStreamingAll(stdout, io, aw.writer.buffer[0..aw.writer.end]);
    return 0;
}

fn execMerge(gpa: Allocator, root: *ops.JsonValue, cmd_args: []const []const u8, io: Io, stderr: File, _: Io) !void {
    if (cmd_args.len < 1) {
        try File.writeStreamingAll(stderr, io, "error: 'merge' requires a file path\n");
        return;
    }
    const merge_input = readFileAlloc(gpa, io, cmd_args[0]) catch |err| {
        writeErrorFmt(gpa, io, "error: cannot open file: {}\n", .{err});
        return;
    };
    defer gpa.free(merge_input);

    const other = ops.parse(gpa, merge_input) catch |err| {
        writeErrorFmt(gpa, io, "error: parse error in merge file: {}\n", .{err});
        return;
    };

    switch (root.*) {
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
                },
            }
        },
        else => {
            try File.writeStreamingAll(stderr, io, "error: merge target must be an object\n");
        },
    }
}

fn execShorthand(gpa: Allocator, root: *ops.JsonValue, cmd: []const u8, stdout: File, stderr: File, io: Io) !void {
    if (cmd.len == 0) {
        try File.writeStreamingAll(stderr, io, "error: unknown command\n");
        return;
    }
    const last = cmd[cmd.len - 1];
    if (last == '-') {
        const path = cmd[0 .. cmd.len - 1];
        ops.del(root, path, gpa) catch |err| {
            switch (err) {
                ops.OpError.PathNotFound => {
                    writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{path});
                },
                else => return err,
            }
        };
        try writeResult(root.*, gpa, stdout, io);
        return;
    }
    if (std.mem.indexOfScalar(u8, cmd, '=')) |eq_pos| {
        const path = cmd[0..eq_pos];
        const rest = cmd[eq_pos + 1 ..];
        if (eq_pos > 0 and cmd[eq_pos - 1] == ':') {
            const actual_path = cmd[0 .. eq_pos - 1];
            var value = ops.inferType(rest);
            if (value == .string) {
                value = .{ .string = try gpa.dupe(u8, value.string) };
            }
            ops.set(root, actual_path, value, gpa) catch |err| {
                switch (err) {
                    ops.OpError.InvalidType => {
                        writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{actual_path});
                    },
                    else => return err,
                }
            };
        } else if (eq_pos > 0 and cmd[eq_pos - 1] == '+') {
            const actual_path = cmd[0 .. eq_pos - 1];
            const value = parseValue(gpa, rest) catch |err| {
                writeErrorFmt(gpa, io, "error: invalid value: {s}\n", .{rest});
                return err;
            };
            ops.push(root, actual_path, value, gpa) catch |err| {
                switch (err) {
                    ops.OpError.PathNotFound => {
                        writeErrorFmt(gpa, io, "error: path not found: {s}\n", .{actual_path});
                    },
                    ops.OpError.InvalidType => {
                        writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{actual_path});
                    },
                    else => return err,
                }
            };
        } else {
            const value = parseValue(gpa, rest) catch |err| {
                writeErrorFmt(gpa, io, "error: invalid value: {s}\n", .{rest});
                return err;
            };
            ops.set(root, path, value, gpa) catch |err| {
                switch (err) {
                    ops.OpError.InvalidType => {
                        writeErrorFmt(gpa, io, "error: invalid type at path: {s}\n", .{path});
                    },
                    else => return err,
                }
            };
        }
        try writeResult(root.*, gpa, stdout, io);
        return;
    }
    writeErrorFmt(gpa, io, "error: unknown command: {s}\n", .{cmd});
}
