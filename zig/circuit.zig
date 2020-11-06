const std = @import("std");
const testing = std.testing;

pub const Wire = struct {
    node: *Node,

    pub fn connect(self: Wire, node: Wire) !void {
        try self.node.inputs.append(node);
    }

    pub fn high(self: Wire) void {
        self.node.outbox = true;
    }

    pub fn low(self: Wire) void {
        self.node.outbox = false;
    }

    pub fn sample(self: Wire) bool {
        return self.node.outbox;
    }
};

pub const Node = struct {
    outbox: bool = false,

    inputs: Edges,

    // private, don't mess with it
    updateFn: fn ([]Wire) bool,

    pub const Edges = std.ArrayList(Wire);

    pub fn pulse(self: *Node) void {
        if (self.inputs.items.len != 0) {
            self.outbox = self.updateFn(self.inputs.items);
        }
    }
};

const Circuit = struct {
    graph: Graph,
    count: usize = 0,

    pub const Graph = std.ArrayList(Node);

    pub fn new(self: *Circuit, update: fn ([]Wire) bool) !Wire {
        try self.graph.append(Node{
            .updateFn = update,
            .inputs = Node.Edges.init(self.graph.allocator),
        });
        defer self.count += 1;
        return Wire{ .node = &self.graph.items[self.count] };
    }

    pub fn wire(self: *Circuit) !Wire {
        return try self.new((struct {
            pub fn update(inputs: []Wire) bool {
                for (inputs) |w| if (w.sample()) return true;
                return false;
            }
        }).update);
    }

    pub fn xorGate(self: *Circuit) !Wire {
        return try self.new((struct {
            pub fn update(inputs: []Wire) bool {
                for (inputs) |w| if (w.sample()) return true;
                return false;
            }
        }).update);
    }

    pub fn andGate(self: *Circuit) !Wire {
        return try self.new((struct {
            pub fn update(inputs: []Wire) bool {
                for (inputs) |w| if (!w.sample()) return false;
                return true;
            }
        }).update);
    }

    pub fn inverter(self: *Circuit) !Wire {
        return try self.new((struct {
            pub fn update(inputs: []Wire) bool {
                var highs: usize = 0;
                for (inputs) |w| if (w.sample()) highs += 1;
                return highs < inputs.len;
            }
        }).update);
    }

    pub fn tick(self: *Circuit) void {
        for (self.graph.items) |*w| w.pulse();
    }
};

test "smoke" {
    var circuit: Circuit = .{ .graph = Circuit.Graph.init(std.heap.page_allocator) };
    var w0 = try circuit.wire();
    var w1 = try circuit.wire();
    var w2 = try circuit.wire();
    try w0.connect(w1);
    try w1.connect(w2);
    w2.high();
    circuit.tick();
    circuit.tick();
    testing.expect(w0.sample() == true);
}

const Spi = struct {
    sclk: Wire,
    mosi: Wire,
    miso: Wire,
    ss: Wire,

    buffer: u8 = 0,
    index: u3 = 0,

    pub fn init(cir: *Circuit) !Spi {
        return Spi{
            .sclk = try cir.wire(),
            .mosi = try cir.wire(),
            .miso = try cir.wire(),
            .ss = try cir.wire(),
        };
    }

    pub fn connect(self: *Spi, other: Spi) !void {
        try self.sclk.connect(other.sclk);
        try self.mosi.connect(other.mosi);
        try other.miso.connect(self.miso);
        try self.ss.connect(other.ss);
    }
};

test "spi" {
    var circuit: Circuit = .{ .graph = Circuit.Graph.init(std.heap.page_allocator) };
    var master = try Spi.init(&circuit);
    var slave = try Spi.init(&circuit);
    try master.connect(slave);
}

const I2C = struct {
    sda: Wire,
    scl: Wire,

    pub fn connect(self: *I2C, other: I2C) !void {
        try self.sda.connect(other.sda);
        try self.scl.connect(other.scl);
    }
};

const PineTime = struct {
    pub const Display = struct {
        spi: Spi,

        pub fn init(circuit: *Circuit) !Display {
            return Display{ .spi = spi.init(&circuit) };
        }
    };

    pub const Accelerometer = struct {
        // 0x18
        i2c: I2C,
    };

    pub const HeartRateSensor = struct {
        // 0x44
        i2c: I2C,
    };

    pub const TouchController = struct {
        // 0x15
        i2c: I2C,
    };
};
