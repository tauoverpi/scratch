const std = @import("std");
const meta = std.meta;
const testing = std.testing;

const Token = union(enum) {
    openbrace,
    closebrace,
    builtin: Builtin,
    reserved: Reserved,
    variable: []const u8,
    rule: []const u8,
    name: []const u8,
    native: []const u8,
    operator: std.math.CompareOperator,
    arrow,
    end,
    negation,
    disjunction,
    constraint,
    number: u32,
    pointer,
    string_line: []const u8,

    pub const Builtin = enum { reset, say, die, win, save, load, call, goto };

    pub const Reserved = enum {
        title,
        synopsis,
        description,
        start,
        @"const",
        option,
        global,
        room,
        scope,
        object,
        copyright,
    };
};

const TokenStream = struct {
    text: []const u8,
    i: usize = 0,
    state: State = .newline,
    last: ?Token = null,

    const State = enum {
        newline,
        string_line,
        string,
        comment,
        builtin,
        reserved,
        action,
        variable,
        rule,
        arrow,
        arrow_head,
        constraint,
        contoken,
        conexpr,
        connumber,
        connumber_space,
        expect_rule_or_directive,
        name_brace,
        name_list,
        call,
        native,
        native_body,
        native_variable,
        room,
        room_name,
        expect_openbrace,
    };

    pub fn next(p: *TokenStream) !?Token {
        if (p.last) |value| {
            p.last = null;
            return value;
        }

        if (p.i >= p.text.len) return null;
        var count: usize = 0;

        while (p.i < p.text.len) : (p.i += 1) {
            const c = p.text[p.i];
            std.debug.print("{c}", .{c});
            switch (p.state) {
                .newline => switch (c) {
                    ' ', '\n' => count = 1,
                    '|' => if (count == 0) {
                        count = 0;
                        p.state = .string_line;
                    } else return error.ExpectedStatement,
                    '/' => p.state = .comment,
                    '#' => {
                        p.state = .builtin;
                        count = 0;
                    },
                    'a'...'z' => {
                        p.state = .reserved;
                        count = 1;
                    },
                    '"' => {
                        count = 0;
                        p.state = .rule;
                    },
                    '[' => {
                        p.state = .constraint;
                        p.i += 1;
                        return .constraint;
                    },
                    else => @panic(""),
                },

                .constraint => switch (c) {
                    ' ' => {},

                    'a'...'z', '-' => {
                        count = 0;
                        p.state = .contoken;
                    },

                    '!' => {
                        p.i += 1;
                        return .negation;
                    },

                    '=' => {
                        p.i += 1;
                        return Token{ .operator = .eq };
                    },

                    ']' => {
                        p.i += 1;
                        p.state = .expect_rule_or_directive;
                        return .end;
                    },

                    else => @panic(" <- con"),
                },

                .expect_rule_or_directive => switch (c) {
                    ' ' => {},
                    '#' => p.state = .builtin,
                    '"' => p.state = .rule,
                    else => @panic(""),
                },

                .contoken => switch (c) {
                    'a'...'z', '-' => count += 1,

                    ',' => {
                        const text = p.text[p.i - count .. p.i];
                        p.i += 1;
                        p.state = .constraint;
                        return Token{ .variable = text };
                    },

                    ' ' => {
                        const text = p.text[p.i - count .. p.i];
                        p.i += 1;
                        p.state = .conexpr;
                        return Token{ .variable = text };
                    },

                    else => @panic(" <- token"),
                },

                .conexpr => switch (c) {
                    ' ' => {},

                    '/' => {
                        p.i += 1;
                        p.state = .constraint;
                        return .disjunction;
                    },

                    '!' => {
                        p.i += 1;
                        p.state = .connumber_space;
                        return Token{ .operator = .neq };
                    },

                    '>' => {
                        p.i += 1;
                        p.state = .connumber_space;
                        return Token{ .operator = .gt };
                    },

                    '<' => {
                        p.i += 1;
                        p.state = .connumber_space;
                        return Token{ .operator = .lt };
                    },

                    '=' => {
                        p.i += 1;
                        p.state = .connumber_space;
                        return Token{ .operator = .eq };
                    },

                    else => @panic(""),
                },

                .connumber_space => switch (c) {
                    ' ' => {},

                    '0'...'9' => {
                        count = 1;
                        p.state = .connumber;
                    },

                    else => @panic(""),
                },

                .connumber => switch (c) {
                    '0'...'9' => count += 1,

                    ',' => {
                        const text = p.text[p.i - count .. p.i];
                        p.i += 1;
                        p.state = .constraint;
                        return Token{ .number = try std.fmt.parseInt(u32, text, 10) };
                    },

                    ']' => {
                        const text = p.text[p.i - count .. p.i];
                        p.i += 1;
                        p.state = .expect_rule_or_directive;
                        p.last = .end;
                        return Token{ .number = try std.fmt.parseInt(u32, text, 10) };
                    },

                    else => @panic(""),
                },

                .comment => switch (c) {
                    '\n' => {
                        count = 0;
                        p.state = .newline;
                    },
                    else => {},
                },

                .string => switch (c) {
                    '|' => p.state = .string_line,
                    ',' => p.state = .action,
                    ';' => {
                        p.state = .newline;
                        p.i += 1;
                        return .end;
                    },
                    else => @panic(" <- string"),
                },

                .string_line => switch (c) {
                    ' ', '!', '#'...0x7e => count += 1,
                    '\n' => {
                        const text = p.text[p.i - count .. p.i];
                        p.i += 1;
                        p.state = .string;
                        return Token{ .string_line = text };
                    },
                    else => @panic(" <- line"),
                },

                .action => switch (c) {
                    ' ' => {},
                    'a'...'z', '-' => {
                        count = 0;
                        p.state = .variable;
                    },
                    ';' => {
                        p.state = .newline;
                        p.i += 1;
                        return .end;
                    },
                    else => @panic(" <- act"),
                },

                .variable => switch (c) {
                    ';' => {
                        const text = p.text[p.i - count .. p.i];
                        p.i += 1;
                        p.state = .newline;
                        p.last = .end;
                        return Token{ .variable = text };
                    },

                    ',' => @panic(" <- token"),

                    'a'...'z', '-' => count += 1,

                    else => @panic(" <- token"),
                },

                .rule => switch (c) {
                    '"' => {
                        const text = p.text[p.i - count .. p.i];
                        p.i += 1;
                        p.state = .arrow;
                        return Token{ .rule = text };
                    },

                    ' ', '!', '#'...'~' => count += 1,

                    else => @panic(""),
                },

                .arrow => switch (c) {
                    '-' => p.state = .arrow_head,
                    ' ' => {},
                    else => @panic(" <- arrow"),
                },

                .arrow_head => switch (c) {
                    '>' => {
                        p.state = .action;
                        p.i += 1;
                        return .arrow;
                    },

                    else => @panic(" <- head"),
                },

                .builtin => switch (c) {
                    'a'...'z' => count += 1,

                    '\n', ' ' => {
                        defer p.i += 1;
                        const builtin = meta.stringToEnum(
                            Token.Builtin,
                            p.text[p.i - count .. p.i],
                        ) orelse return error.UnknownBuiltin;

                        switch (builtin) {
                            .say => p.state = .string,
                            .call => p.state = .call,
                            else => @panic(""),
                        }

                        return Token{ .builtin = builtin };
                    },

                    else => @panic(""),
                },

                .call => switch (c) {
                    ' ' => {},
                    'a'...'z', 'A'...'Z' => {
                        p.state = .native;
                        count = 1;
                    },
                    else => @panic(" <- call"),
                },

                .native => switch (c) {
                    'a'...'z', 'A'...'Z', '_', '0'...'9' => count += 1,
                    '(' => {
                        const text = p.text[p.i - count .. p.i];
                        p.state = .native_body;
                        p.i += 1;
                        return Token{ .native = text };
                    },
                    else => @panic(" <-- nat"),
                },

                .native_body => switch (c) {
                    ' ' => {},
                    '&' => {
                        p.i += 1;
                        return .pointer;
                    },
                    'a'...'z', 'A'...'Z' => {
                        p.state = .native_variable;
                        count = 1;
                    },

                    ')' => {
                        p.i += 1;
                        p.state = .action;
                        return .end;
                    },

                    else => @panic(" <- body"),
                },

                .native_variable => switch (c) {
                    'a'...'z', '0'...'9', '-' => count += 1,
                    ',' => {
                        const text = p.text[p.i - count .. p.i];
                        p.i += 1;
                        p.state = .native_body;
                        return Token{ .variable = text };
                    },

                    ')' => {
                        const text = p.text[p.i - count .. p.i];
                        p.i += 1;
                        p.state = .action;
                        return Token{ .variable = text };
                    },

                    else => @panic(" <- nv"),
                },

                .reserved => switch (c) {
                    'a'...'z' => count += 1,

                    '\n', ' ' => {
                        defer p.i += 1;
                        const reserved = meta.stringToEnum(
                            Token.Reserved,
                            p.text[p.i - count .. p.i],
                        ) orelse return error.UnknownReserved;

                        switch (reserved) {
                            .title, .description, .synopsis => p.state = .string,
                            .scope, .room => p.state = .room,
                            .start => @panic(""),
                            .@"const" => @panic(""),
                            .option => @panic(""),
                            .global => @panic(""),
                            .object => @panic(""),
                            .copyright => @panic(""),
                        }

                        return Token{ .reserved = reserved };
                    },

                    else => @panic(""),
                },

                .room => switch (c) {
                    ' ' => {},
                    'a'...'z' => {
                        p.state = .room_name;
                        count = 1;
                    },
                    else => @panic(" <- room"),
                },

                .room_name => switch (c) {
                    'a'...'z', '0'...'9', '-' => count += 1,
                    ' ' => {
                        const text = p.text[p.i - count .. p.i];
                        p.i += 1;
                        p.state = .expect_openbrace;
                        return Token{ .name = text };
                    },
                    else => @panic(" <-"),
                },

                .expect_openbrace => switch (c) {
                    '{' => {
                        p.i += 1;
                        p.state = .newline;
                        return .openbrace;
                    },
                    else => return error.ExpectedOpenBrace,
                },

                .name_brace => switch (c) {
                    'a'...'z', '-' => count += 1,
                    else => @panic(" <- nameb"),
                },

                .name_list => switch (c) {
                    else => @panic(" <- name"),
                },
            }
        }

        return null;
    }
};

test "" {
    const expect = testing.expect;
    var p = TokenStream{ .text = "/ comment\n" };
    testing.expect((try p.next()) == null);

    p = TokenStream{ .text = "#say\n|this\n;\n" };
    expect((try p.next()).?.builtin == .say);
    expect((try p.next()).? == .string_line);
    expect((try p.next()).? == .end);
    expect((try p.next()) == null);

    p = TokenStream{ .text = "#say\n|this\n, ok;\n" };
    expect((try p.next()).?.builtin == .say);
    expect((try p.next()).? == .string_line);
    expect((try p.next()).? == .variable);
    expect((try p.next()).? == .end);
    expect((try p.next()) == null);

    p = TokenStream{ .text = "\"rule\" -> ok;\n" };
    expect((try p.next()).? == .rule);
    expect((try p.next()).? == .arrow);
    expect((try p.next()).? == .variable);
    expect((try p.next()).? == .end);
    expect((try p.next()) == null);

    p = TokenStream{ .text = "[key, !key / key > 1, key = 0, key < 1, key ! 1]" };
    expect((try p.next()).? == .constraint);
    expect((try p.next()).? == .variable);
    expect((try p.next()).? == .negation);
    expect((try p.next()).? == .variable);
    expect((try p.next()).? == .disjunction);
    expect((try p.next()).? == .variable);
    expect((try p.next()).?.operator == .gt);
    expect((try p.next()).? == .number);
    expect((try p.next()).? == .variable);
    expect((try p.next()).?.operator == .eq);
    expect((try p.next()).? == .number);
    expect((try p.next()).? == .variable);
    expect((try p.next()).?.operator == .lt);
    expect((try p.next()).? == .number);
    expect((try p.next()).? == .variable);
    expect((try p.next()).?.operator == .neq);
    expect((try p.next()).? == .number);
    expect((try p.next()).? == .end);
    expect((try p.next()) == null);

    p = TokenStream{ .text = "[] \"\" -> ok;\n" };
    expect((try p.next()).? == .constraint);
    expect((try p.next()).? == .end);
    expect((try p.next()).? == .rule);
    expect((try p.next()).? == .arrow);
    expect((try p.next()).? == .variable);
    expect((try p.next()).? == .end);
    expect((try p.next()) == null);

    p = TokenStream{ .text = "#call foo(a, &b, c);\n" };
    expect((try p.next()).?.builtin == .call);
    expect((try p.next()).? == .native);
    expect((try p.next()).? == .variable);
    expect((try p.next()).? == .pointer);
    expect((try p.next()).? == .variable);
    expect((try p.next()).? == .variable);
    expect((try p.next()).? == .end);
    expect((try p.next()) == null);

    p = TokenStream{ .text = "room hallway {}\n" };
    expect((try p.next()).?.reserved == .room);
    expect((try p.next()).? == .name);
    expect((try p.next()).? == .openbrace);
    expect((try p.next()).? == .closebrace);
    expect((try p.next()) == null);
}
