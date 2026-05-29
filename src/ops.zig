const std = @import("std");
const Allocator = std.mem.Allocator;

pub const JsonValue = union(enum) {
    null,
    boolean: bool,
    integer: i64,
    number: f64,
    string: []const u8,
    array: std.ArrayList(JsonValue),
    object: std.array_hash_map.String(JsonValue),

    pub fn deinit(self: *JsonValue, gpa: Allocator) void {
        switch (self.*) {
            .null, .boolean, .integer, .number => {},
            .string => |s| gpa.free(s),
            .array => |*arr| {
                for (arr.items) |*item| {
                    item.deinit(gpa);
                }
                arr.deinit(gpa);
            },
            .object => |*obj| {
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    gpa.free(entry.key_ptr.*);
                    var val = entry.value_ptr.*;
                    val.deinit(gpa);
                }
                obj.deinit(gpa);
            },
        }
    }

    pub fn clone(self: JsonValue, gpa: Allocator) !JsonValue {
        switch (self) {
            .null => return .null,
            .boolean => |b| return .{ .boolean = b },
            .integer => |i| return .{ .integer = i },
            .number => |f| return .{ .number = f },
            .string => |s| return .{ .string = try gpa.dupe(u8, s) },
            .array => |arr| {
                var new_arr: std.ArrayList(JsonValue) = .empty;
                errdefer new_arr.deinit(gpa);
                try new_arr.ensureTotalCapacity(gpa, arr.items.len);
                for (arr.items) |item| {
                    try new_arr.append(gpa, try item.clone(gpa));
                }
                return .{ .array = new_arr };
            },
            .object => |obj| {
                var new_obj: std.array_hash_map.String(JsonValue) = .empty;
                errdefer new_obj.deinit(gpa);
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    const key = try gpa.dupe(u8, entry.key_ptr.*);
                    const val = try entry.value_ptr.*.clone(gpa);
                    try new_obj.put(gpa, key, val);
                }
                return .{ .object = new_obj };
            },
        }
    }

    pub fn writeTo(self: JsonValue, writer: *std.Io.Writer) !void {
        switch (self) {
            .null => try writer.writeAll("null"),
            .boolean => |b| try writer.writeAll(if (b) "true" else "false"),
            .integer => |i| try writer.print("{d}", .{i}),
            .number => |f| {
                if (std.math.isFinite(f)) {
                    if (f == @trunc(f) and @abs(f) < 1e15) {
                        try writer.print("{d:.0}", .{f});
                    } else {
                        try writer.print("{d}", .{f});
                    }
                } else {
                    try writer.writeAll("null");
                }
            },
            .string => |s| {
                try writer.writeAll("\"");
                for (s) |ch| {
                    switch (ch) {
                        '"' => try writer.writeAll("\\\""),
                        '\\' => try writer.writeAll("\\\\"),
                        '\n' => try writer.writeAll("\\n"),
                        '\r' => try writer.writeAll("\\r"),
                        '\t' => try writer.writeAll("\\t"),
                        else => {
                            if (ch < 0x20) {
                                try writer.print("\\u{X:0>4}", .{ch});
                            } else {
                                try writer.writeByte(ch);
                            }
                        },
                    }
                }
                try writer.writeAll("\"");
            },
            .array => |arr| {
                try writer.writeAll("[");
                for (arr.items, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(",");
                    try item.writeTo(writer);
                }
                try writer.writeAll("]");
            },
            .object => |obj| {
                try writer.writeAll("{");
                var i: usize = 0;
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    if (i > 0) try writer.writeAll(",");
                    try writer.writeAll("\"");
                    try writer.writeAll(entry.key_ptr.*);
                    try writer.writeAll("\":");
                    try entry.value_ptr.*.writeTo(writer);
                    i += 1;
                }
                try writer.writeAll("}");
            },
        }
    }

    pub fn writePretty(self: JsonValue, writer: *std.Io.Writer, indent: usize) !void {
        switch (self) {
            .null => try writer.writeAll("null"),
            .boolean => |b| try writer.writeAll(if (b) "true" else "false"),
            .integer => |i| try writer.print("{d}", .{i}),
            .number => |f| {
                if (std.math.isFinite(f)) {
                    if (f == @trunc(f) and @abs(f) < 1e15) {
                        try writer.print("{d:.0}", .{f});
                    } else {
                        try writer.print("{d}", .{f});
                    }
                } else {
                    try writer.writeAll("null");
                }
            },
            .string => |s| {
                try writer.writeAll("\"");
                for (s) |ch| {
                    switch (ch) {
                        '"' => try writer.writeAll("\\\""),
                        '\\' => try writer.writeAll("\\\\"),
                        '\n' => try writer.writeAll("\\n"),
                        '\r' => try writer.writeAll("\\r"),
                        '\t' => try writer.writeAll("\\t"),
                        else => {
                            if (ch < 0x20) {
                                try writer.print("\\u{X:0>4}", .{ch});
                            } else {
                                try writer.writeByte(ch);
                            }
                        },
                    }
                }
                try writer.writeAll("\"");
            },
            .array => |arr| {
                if (arr.items.len == 0) {
                    try writer.writeAll("[]");
                    return;
                }
                try writer.writeAll("[\n");
                for (arr.items, 0..) |item, i| {
                    for (0..indent + 2) |_| try writer.writeByte(' ');
                    try item.writePretty(writer, indent + 2);
                    if (i < arr.items.len - 1) try writer.writeByte(',');
                    try writer.writeByte('\n');
                }
                for (0..indent) |_| try writer.writeByte(' ');
                try writer.writeAll("]");
            },
            .object => |obj| {
                if (obj.count() == 0) {
                    try writer.writeAll("{}");
                    return;
                }
                try writer.writeAll("{\n");
                var i: usize = 0;
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    for (0..indent + 2) |_| try writer.writeByte(' ');
                    try writer.writeAll("\"");
                    try writer.writeAll(entry.key_ptr.*);
                    try writer.writeAll("\": ");
                    try entry.value_ptr.*.writePretty(writer, indent + 2);
                    if (i < obj.count() - 1) try writer.writeByte(',');
                    try writer.writeByte('\n');
                    i += 1;
                }
                for (0..indent) |_| try writer.writeByte(' ');
                try writer.writeAll("}");
            },
        }
    }

    pub fn getTypeName(self: JsonValue) []const u8 {
        return switch (self) {
            .null => "null",
            .boolean => "boolean",
            .integer => "number",
            .number => "number",
            .string => "string",
            .array => "array",
            .object => "object",
        };
    }
};

pub const ParseError = error{
    InvalidJson,
    OutOfMemory,
};

pub fn parse(gpa: Allocator, input: []const u8) ParseError!JsonValue {
    var parser = JsonParser{ .gpa = gpa, .input = input, .pos = 0 };
    return parser.parseValue();
}

const JsonParser = struct {
    gpa: Allocator,
    input: []const u8,
    pos: usize,

    fn skipWhitespace(self: *JsonParser) void {
        while (self.pos < self.input.len) : (self.pos += 1) {
            switch (self.input[self.pos]) {
                ' ', '\t', '\n', '\r' => {},
                else => break,
            }
        }
    }

    fn peek(self: *JsonParser) ?u8 {
        self.skipWhitespace();
        if (self.pos < self.input.len) return self.input[self.pos];
        return null;
    }

    fn consume(self: *JsonParser, ch: u8) bool {
        self.skipWhitespace();
        if (self.pos < self.input.len and self.input[self.pos] == ch) {
            self.pos += 1;
            return true;
        }
        return false;
    }

    fn parseValue(self: *JsonParser) ParseError!JsonValue {
        self.skipWhitespace();
        if (self.pos >= self.input.len) return ParseError.InvalidJson;
        switch (self.input[self.pos]) {
            '"' => return self.parseString(),
            '{' => return self.parseObject(),
            '[' => return self.parseArray(),
            't', 'f' => return self.parseBool(),
            'n' => return self.parseNull(),
            '-', '0'...'9' => return self.parseNumber(),
            else => return ParseError.InvalidJson,
        }
    }

    fn parseNull(self: *JsonParser) ParseError!JsonValue {
        if (self.pos + 4 <= self.input.len and std.mem.eql(u8, self.input[self.pos .. self.pos + 4], "null")) {
            self.pos += 4;
            return .null;
        }
        return ParseError.InvalidJson;
    }

    fn parseBool(self: *JsonParser) ParseError!JsonValue {
        if (self.pos + 4 <= self.input.len and std.mem.eql(u8, self.input[self.pos .. self.pos + 4], "true")) {
            self.pos += 4;
            return .{ .boolean = true };
        }
        if (self.pos + 5 <= self.input.len and std.mem.eql(u8, self.input[self.pos .. self.pos + 5], "false")) {
            self.pos += 5;
            return .{ .boolean = false };
        }
        return ParseError.InvalidJson;
    }

    fn parseNumber(self: *JsonParser) ParseError!JsonValue {
        const start = self.pos;
        if (self.pos < self.input.len and self.input[self.pos] == '-') self.pos += 1;
        while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) : (self.pos += 1) {}
        var is_float = false;
        if (self.pos < self.input.len and self.input[self.pos] == '.') {
            is_float = true;
            self.pos += 1;
            while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) : (self.pos += 1) {}
        }
        if (self.pos < self.input.len and (self.input[self.pos] == 'e' or self.input[self.pos] == 'E')) {
            is_float = true;
            self.pos += 1;
            if (self.pos < self.input.len and (self.input[self.pos] == '+' or self.input[self.pos] == '-')) self.pos += 1;
            while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) : (self.pos += 1) {}
        }
        const num_str = self.input[start..self.pos];
        if (is_float) {
            const f = std.fmt.parseFloat(f64, num_str) catch return ParseError.InvalidJson;
            return .{ .number = f };
        } else {
            const i = std.fmt.parseInt(i64, num_str, 10) catch return ParseError.InvalidJson;
            return .{ .integer = i };
        }
    }

    fn parseString(self: *JsonParser) ParseError!JsonValue {
        if (self.input[self.pos] != '"') return ParseError.InvalidJson;
        self.pos += 1;
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(self.gpa);
        while (self.pos < self.input.len) : (self.pos += 1) {
            const ch = self.input[self.pos];
            if (ch == '"') {
                self.pos += 1;
                const result = try self.gpa.dupe(u8, buf.items);
                buf.deinit(self.gpa);
                return .{ .string = result };
            }
            if (ch == '\\') {
                self.pos += 1;
                if (self.pos >= self.input.len) return ParseError.InvalidJson;
                switch (self.input[self.pos]) {
                    '"' => try buf.append(self.gpa, '"'),
                    '\\' => try buf.append(self.gpa, '\\'),
                    '/' => try buf.append(self.gpa, '/'),
                    'n' => try buf.append(self.gpa, '\n'),
                    'r' => try buf.append(self.gpa, '\r'),
                    't' => try buf.append(self.gpa, '\t'),
                    'b' => try buf.append(self.gpa, 0x08),
                    'f' => try buf.append(self.gpa, 0x0c),
                    'u' => {
                        if (self.pos + 4 >= self.input.len) return ParseError.InvalidJson;
                        const hex = self.input[self.pos + 1 .. self.pos + 5];
                        const codepoint = std.fmt.parseInt(u16, hex, 16) catch return ParseError.InvalidJson;
                        self.pos += 4;
                        if (codepoint < 0x80) {
                            try buf.append(self.gpa, @intCast(codepoint));
                        } else if (codepoint < 0x800) {
                            try buf.append(self.gpa, @intCast(0xC0 | (codepoint >> 6)));
                            try buf.append(self.gpa, @intCast(0x80 | (codepoint & 0x3F)));
                        } else {
                            try buf.append(self.gpa, @intCast(0xE0 | (codepoint >> 12)));
                            try buf.append(self.gpa, @intCast(0x80 | ((codepoint >> 6) & 0x3F)));
                            try buf.append(self.gpa, @intCast(0x80 | (codepoint & 0x3F)));
                        }
                    },
                    else => return ParseError.InvalidJson,
                }
            } else {
                try buf.append(self.gpa, ch);
            }
        }
        return ParseError.InvalidJson;
    }

    fn parseArray(self: *JsonParser) ParseError!JsonValue {
        if (!self.consume('[')) return ParseError.InvalidJson;
        var arr: std.ArrayList(JsonValue) = .empty;
        errdefer {
            for (arr.items) |*item| item.deinit(self.gpa);
            arr.deinit(self.gpa);
        }
        if (self.peek() == ']') {
            self.pos += 1;
            return .{ .array = arr };
        }
        while (true) {
            const val = try self.parseValue();
            try arr.append(self.gpa, val);
            if (self.consume(',')) continue;
            if (self.consume(']')) return .{ .array = arr };
            return ParseError.InvalidJson;
        }
    }

    fn parseObject(self: *JsonParser) ParseError!JsonValue {
        if (!self.consume('{')) return ParseError.InvalidJson;
        var obj: std.array_hash_map.String(JsonValue) = .empty;
        errdefer {
            var it = obj.iterator();
            while (it.next()) |e| {
                self.gpa.free(e.key_ptr.*);
                var v = e.value_ptr.*;
                v.deinit(self.gpa);
            }
            obj.deinit(self.gpa);
        }
        if (self.peek() == '}') {
            self.pos += 1;
            return .{ .object = obj };
        }
        while (true) {
            self.skipWhitespace();
            if (self.pos >= self.input.len or self.input[self.pos] != '"') return ParseError.InvalidJson;
            const key_val = try self.parseString();
            const key = key_val.string;
            if (!self.consume(':')) return ParseError.InvalidJson;
            const val = try self.parseValue();
            const existing = obj.fetchPut(self.gpa, key, val) catch |err| {
                switch (err) {
                    error.OutOfMemory => return ParseError.OutOfMemory,
                }
            };
            if (existing) |old| {
                var old_val = old.value;
                old_val.deinit(self.gpa);
                self.gpa.free(key);
            }
            if (self.consume(',')) continue;
            if (self.consume('}')) return .{ .object = obj };
            return ParseError.InvalidJson;
        }
    }
};

pub const PathSegment = union(enum) {
    key: []const u8,
    index: usize,
};

pub fn parsePath(gpa: Allocator, path: []const u8) !std.ArrayList(PathSegment) {
    var segments: std.ArrayList(PathSegment) = .empty;
    errdefer segments.deinit(gpa);
    if (path.len == 0) return segments;
    var start: usize = 0;
    for (path, 0..) |ch, i| {
        if (ch == '.') {
            if (i > start) {
                const part = path[start..i];
                if (std.mem.eql(u8, part, "-")) {
                    try segments.append(gpa, .{ .index = std.math.maxInt(usize) });
                } else if (std.ascii.isDigit(part[0])) {
                    const idx = std.fmt.parseInt(usize, part, 10) catch return error.InvalidPath;
                    try segments.append(gpa, .{ .index = idx });
                } else {
                    try segments.append(gpa, .{ .key = part });
                }
            }
            start = i + 1;
        }
    }
    if (start < path.len) {
        const part = path[start..];
        if (std.mem.eql(u8, part, "-")) {
            try segments.append(gpa, .{ .index = std.math.maxInt(usize) });
        } else if (std.ascii.isDigit(part[0])) {
            const idx = std.fmt.parseInt(usize, part, 10) catch return error.InvalidPath;
            try segments.append(gpa, .{ .index = idx });
        } else {
            try segments.append(gpa, .{ .key = part });
        }
    }
    return segments;
}

pub const OpError = error{
    PathNotFound,
    InvalidType,
    InvalidPath,
    OutOfMemory,
};

pub fn get(root: JsonValue, path: []const u8, gpa: Allocator) OpError!JsonValue {
    var segments = parsePath(gpa, path) catch return OpError.InvalidPath;
    defer segments.deinit(gpa);
    var current = root;
    for (segments.items) |seg| {
        switch (seg) {
            .key => |k| {
                switch (current) {
                    .object => |obj| {
                        current = obj.get(k) orelse return OpError.PathNotFound;
                    },
                    else => return OpError.InvalidType,
                }
            },
            .index => |idx| {
                switch (current) {
                    .array => |arr| {
                        const actual_idx = if (idx == std.math.maxInt(usize)) arr.items.len -| 1 else idx;
                        if (actual_idx >= arr.items.len) return OpError.PathNotFound;
                        current = arr.items[actual_idx];
                    },
                    else => return OpError.InvalidType,
                }
            },
        }
    }
    return try current.clone(gpa);
}

pub fn set(root: *JsonValue, path: []const u8, value: JsonValue, gpa: Allocator) OpError!void {
    var segments = parsePath(gpa, path) catch return OpError.InvalidPath;
    defer segments.deinit(gpa);
    if (segments.items.len == 0) {
        root.deinit(gpa);
        root.* = value;
        return;
    }
    try setRecursive(root, segments.items, 0, value, gpa);
}

fn setRecursive(current: *JsonValue, segments: []const PathSegment, depth: usize, value: JsonValue, gpa: Allocator) OpError!void {
    if (depth == segments.len) {
        current.* = value;
        return;
    }
    const seg = segments[depth];
    switch (seg) {
        .key => |k| {
            switch (current.*) {
                .object => |*obj| {
                    if (obj.getPtr(k)) |existing| {
                        if (depth == segments.len - 1) {
                            var old = existing.*;
                            old.deinit(gpa);
                            existing.* = value;
                        } else {
                            try setRecursive(existing, segments, depth + 1, value, gpa);
                        }
                    } else {
                        if (depth == segments.len - 1) {
                            const key_dup = try gpa.dupe(u8, k);
                            try obj.put(gpa, key_dup, value);
                        } else {
                            const new_obj: std.array_hash_map.String(JsonValue) = .empty;
                            const key_dup = try gpa.dupe(u8, k);
                            const placeholder: JsonValue = .{ .object = new_obj };
                            try obj.put(gpa, key_dup, placeholder);
                            if (obj.getPtr(k)) |new_entry| {
                                try setRecursive(new_entry, segments, depth + 1, value, gpa);
                            }
                        }
                    }
                },
                .null => {
                    const new_obj: std.array_hash_map.String(JsonValue) = .empty;
                    current.* = .{ .object = new_obj };
                    try setRecursive(current, segments, depth, value, gpa);
                },
                else => return OpError.InvalidType,
            }
        },
        .index => |idx| {
            switch (current.*) {
                .array => |*arr| {
                    const actual_idx = if (idx == std.math.maxInt(usize)) arr.items.len -| 1 else idx;
                    if (actual_idx >= arr.items.len) return OpError.PathNotFound;
                    if (depth == segments.len - 1) {
                        var old = arr.items[actual_idx];
                        old.deinit(gpa);
                        arr.items[actual_idx] = value;
                    } else {
                        try setRecursive(&arr.items[actual_idx], segments, depth + 1, value, gpa);
                    }
                },
                .null => {
                    const new_arr: std.ArrayList(JsonValue) = .empty;
                    current.* = .{ .array = new_arr };
                    try setRecursive(current, segments, depth, value, gpa);
                },
                else => return OpError.InvalidType,
            }
        },
    }
}

pub fn del(root: *JsonValue, path: []const u8, gpa: Allocator) OpError!void {
    var segments = parsePath(gpa, path) catch return OpError.InvalidPath;
    defer segments.deinit(gpa);
    if (segments.items.len == 0) return;
    try delRecursive(root, segments.items, gpa);
}

fn delRecursive(current: *JsonValue, segments: []const PathSegment, gpa: Allocator) OpError!void {
    if (segments.len == 0) return;
    const seg = segments[0];
    const rest = segments[1..];
    switch (seg) {
        .key => |k| {
            switch (current.*) {
                .object => |*obj| {
                    if (rest.len == 0) {
                        if (obj.fetchSwapRemove(k)) |entry| {
                            var old_val = entry.value;
                            old_val.deinit(gpa);
                            gpa.free(entry.key);
                        } else return OpError.PathNotFound;
                    } else {
                        const child = obj.getPtr(k) orelse return OpError.PathNotFound;
                        try delRecursive(child, rest, gpa);
                    }
                },
                else => return OpError.InvalidType,
            }
        },
        .index => |idx| {
            switch (current.*) {
                .array => |*arr| {
                    const actual_idx = if (idx == std.math.maxInt(usize)) arr.items.len -| 1 else idx;
                    if (actual_idx >= arr.items.len) return OpError.PathNotFound;
                    if (rest.len == 0) {
                        var old = arr.orderedRemove(actual_idx);
                        old.deinit(gpa);
                    } else {
                        try delRecursive(&arr.items[actual_idx], rest, gpa);
                    }
                },
                else => return OpError.InvalidType,
            }
        },
    }
}

pub fn push(root: *JsonValue, path: []const u8, value: JsonValue, gpa: Allocator) OpError!void {
    var segments = parsePath(gpa, path) catch return OpError.InvalidPath;
    defer segments.deinit(gpa);
    var target = root;
    for (segments.items) |seg| {
        switch (seg) {
            .key => |k| {
                switch (target.*) {
                    .object => |*obj| {
                        if (obj.getPtr(k)) |existing| {
                            target = existing;
                        } else {
                            const new_arr: std.ArrayList(JsonValue) = .empty;
                            const key_dup = try gpa.dupe(u8, k);
                            try obj.put(gpa, key_dup, .{ .array = new_arr });
                            target = obj.getPtr(k).?;
                        }
                    },
                    else => return OpError.InvalidType,
                }
            },
            .index => |idx| {
                switch (target.*) {
                    .array => |*arr| {
                        const actual_idx = if (idx == std.math.maxInt(usize)) arr.items.len -| 1 else idx;
                        if (actual_idx >= arr.items.len) return OpError.PathNotFound;
                        target = &arr.items[actual_idx];
                    },
                    else => return OpError.InvalidType,
                }
            },
        }
    }
    switch (target.*) {
        .array => |*arr| {
            try arr.append(gpa, value);
        },
        .null => {
            var new_arr: std.ArrayList(JsonValue) = .empty;
            try new_arr.append(gpa, value);
            target.* = .{ .array = new_arr };
        },
        else => return OpError.InvalidType,
    }
}

pub fn pop(root: *JsonValue, path: []const u8, gpa: Allocator) OpError!JsonValue {
    var segments = parsePath(gpa, path) catch return OpError.InvalidPath;
    defer segments.deinit(gpa);
    var target = root;
    for (segments.items) |seg| {
        switch (seg) {
            .key => |k| {
                switch (target.*) {
                    .object => |*obj| {
                        target = obj.getPtr(k) orelse return OpError.PathNotFound;
                    },
                    else => return OpError.InvalidType,
                }
            },
            .index => |idx| {
                switch (target.*) {
                    .array => |*arr| {
                        const actual_idx = if (idx == std.math.maxInt(usize)) arr.items.len -| 1 else idx;
                        if (actual_idx >= arr.items.len) return OpError.PathNotFound;
                        target = &arr.items[actual_idx];
                    },
                    else => return OpError.InvalidType,
                }
            },
        }
    }
    switch (target.*) {
        .array => |*arr| {
            if (arr.items.len == 0) return OpError.PathNotFound;
            return arr.pop().?;
        },
        else => return OpError.InvalidType,
    }
}

pub fn pick(root: *JsonValue, keys: []const []const u8, gpa: Allocator) OpError!void {
    switch (root.*) {
        .object => |*obj| {
            var to_remove: std.ArrayList([]const u8) = .empty;
            defer to_remove.deinit(gpa);
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                var found = false;
                for (keys) |k| {
                    if (std.mem.eql(u8, entry.key_ptr.*, k)) {
                        found = true;
                        break;
                    }
                }
                if (!found) try to_remove.append(gpa, entry.key_ptr.*);
            }
            for (to_remove.items) |k| {
                if (obj.fetchSwapRemove(k)) |entry| {
                    var old_val = entry.value;
                    old_val.deinit(gpa);
                    gpa.free(entry.key);
                }
            }
        },
        else => return OpError.InvalidType,
    }
}

pub fn omit(root: *JsonValue, keys: []const []const u8, gpa: Allocator) OpError!void {
    switch (root.*) {
        .object => |*obj| {
            for (keys) |k| {
                if (obj.fetchSwapRemove(k)) |entry| {
                    var old_val = entry.value;
                    old_val.deinit(gpa);
                    gpa.free(entry.key);
                }
            }
        },
        else => return OpError.InvalidType,
    }
}

pub fn inferType(val: []const u8) JsonValue {
    if (std.mem.eql(u8, val, "true")) return .{ .boolean = true };
    if (std.mem.eql(u8, val, "false")) return .{ .boolean = false };
    if (std.mem.eql(u8, val, "null")) return .null;
    if (std.fmt.parseInt(i64, val, 10)) |i| return .{ .integer = i } else |_| {}
    if (std.fmt.parseFloat(f64, val)) |f| return .{ .number = f } else |_| {}
    return .{ .string = val };
}
