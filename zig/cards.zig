const std = @import("std");

// each card is specified by a node
// types for dates
// cards specify what they belong to (groups, decks, etc)

// #due:1995:12:20 22:00
// #topic:development
// #topic:expenses
// The day things will happen
// description follows the title header
// since I'm too lazy to make a new format
// @uuid is literally the has of the content

// #due:1990:12:20 22:00

// logically expands to

// #topic:year 1990
// #topic:month 12
// #topic:day 20
// #topic:hour 22
// #topic:minute 00

// where any more would be meaningless and thus an error

const Macro = union(enum) {
    topic: []const u8,
    due: struct {
        date: struct { year: u16, month: u5, day: u9 },
        time: ?struct { hour: u6, minute: u6 },
        pub fn read(text: []const u8) @This() {}
    },
};

const Card = struct {
    title: []const u8,
    topics: []const []const u8,
};
