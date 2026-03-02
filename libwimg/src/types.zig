const std = @import("std");

pub const Category = enum(u8) {
    uncategorized = 0,
    groceries = 1,
    dining = 2,
    transport = 3,
    housing = 4,
    utilities = 5,
    entertainment = 6,
    shopping = 7,
    health = 8,
    insurance = 9,
    income = 10,
    transfer = 11,
    cash = 12,
    subscriptions = 13,
    travel = 14,
    education = 15,
    other = 255,

    pub fn name(self: Category) []const u8 {
        return switch (self) {
            .uncategorized => "Uncategorized",
            .groceries => "Groceries",
            .dining => "Dining",
            .transport => "Transport",
            .housing => "Housing",
            .utilities => "Utilities",
            .entertainment => "Entertainment",
            .shopping => "Shopping",
            .health => "Health",
            .insurance => "Insurance",
            .income => "Income",
            .transfer => "Transfer",
            .cash => "Cash",
            .subscriptions => "Subscriptions",
            .travel => "Travel",
            .education => "Education",
            .other => "Other",
        };
    }

    pub fn fromInt(val: u8) Category {
        return std.meta.intToEnum(Category, val) catch .uncategorized;
    }
};

pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    pub fn order(self: Date) u32 {
        return @as(u32, self.year) * 10000 + @as(u32, self.month) * 100 + @as(u32, self.day);
    }

    pub fn eql(a: Date, b: Date) bool {
        return a.year == b.year and a.month == b.month and a.day == b.day;
    }
};

pub const Transaction = struct {
    id: [32]u8, // hex-encoded hash
    date: Date,
    description: [256]u8,
    description_len: u16,
    amount_cents: i64, // stored as cents to avoid float issues
    currency: [3]u8, // "EUR"
    category: Category,

    pub fn descriptionSlice(self: *const Transaction) []const u8 {
        return self.description[0..self.description_len];
    }

    pub fn amountFloat(self: *const Transaction) f64 {
        return @as(f64, @floatFromInt(self.amount_cents)) / 100.0;
    }
};

pub const ImportResult = struct {
    total_rows: u32,
    imported: u32,
    skipped_duplicates: u32,
    errors: u32,
};
