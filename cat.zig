pub fn Semigroup(comptime T: type) type {
    return struct {
        plus: fn (T, T) T,
    };
}

pub fn Monoid(comptime T: type) type {
    return struct {
        zero: T,
        plus: Semigroup(T).plus,
    };
}

pub fn Kleisil(comptime R: type, comptime T: type) type {
    return struct {
        fish: fn (fn (T) Kleisil(R, T), fn (T) Kleisil(R, T)) Kleisil(R, T),
    };
}

test "" {
    const A = Kleisil(bool, bool);
    const a: A = .{
        fish = (struct{pub fn f(fn(T) Kleisil(R, T), (fn(T) Kleisil(R, T)))
        Kleisil(R, T) {
        }
    };
    };
}
