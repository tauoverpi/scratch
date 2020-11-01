const std = @import("std");
const testing = std.testing;

pub const Ctx = struct {
    node: *Node,

    pub fn connect(self: Ctx, node: Ctx) !void {
        try self.node.inputs.append(node);
    }

    pub fn high(self: Ctx) void {
        self.node.outbox = true;
    }

    pub fn low(self: Ctx) void {
        self.node.outbox = false;
    }

    pub fn sample(self: Ctx) bool {
        return self.node.outbox;
    }
};

pub const Node = struct {
    outbox: bool = false,

    inputs: Edges,

    // private, don't mess with it
    updateFn: fn ([]Ctx) bool,

    pub const Edges = std.ArrayList(Ctx);

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

    pub fn new(self: *Circuit, update: fn ([]Ctx) bool) !Ctx {
        try self.graph.append(Node{
            .updateFn = update,
            .inputs = Node.Edges.init(self.graph.allocator),
        });
        defer self.count += 1;
        return Ctx{ .node = &self.graph.items[self.count] };
    }

    pub fn wire(self: *Circuit) !Ctx {
        return try self.new((struct {
            pub fn update(inputs: []Ctx) bool {
                for (inputs) |w| if (w.sample()) return true;
                return false;
            }
        }).update);
    }

    pub fn xorGate(self: *Circuit) !Ctx {
        return try self.new((struct {
            pub fn update(inputs: []Ctx) bool {
                for (inputs) |w| if (w.sample()) return true;
                return false;
            }
        }).update);
    }

    pub fn andGate(self: *Circuit) !Ctx {
        return try self.new((struct {
            pub fn update(inputs: []Ctx) bool {
                for (inputs) |w| if (!w.sample()) return false;
                return true;
            }
        }).update);
    }

    pub fn inverter(self: *Circuit) !Ctx {
        return try self.new((struct {
            pub fn update(inputs: []Ctx) bool {
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
    sclk: Ctx,
    mosi: Ctx,
    miso: Ctx,
    ss: Ctx,

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
