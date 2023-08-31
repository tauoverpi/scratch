const std = @import("std");
const math = std.math;

fn f(x: f64) f64 {
    return 2 * x - 2;
}

test {
    var w_0: f64 = 0;
    var b_0: f64 = 0;
    var time: f64 = 1;
    var w_old: f64 = 1;

    var m_w: f64 = 0;
    var m_b: f64 = 0;
    var v_w: f64 = 0;
    var v_b: f64 = 0;
    const beta1 = 0.9;
    const beta2 = 0.999;
    const elipsion = 1e-8;
    const alpha = 0.01;

    while (w_old != w_0) : (time += 1) {
        const w = f(w_0);
        const b = f(b_0);

        w_old = w_0;

        m_w = beta1 * m_w + (1 - beta1) * w;
        m_b = beta1 * m_b + (1 - beta1) * b;

        v_w = beta2 * v_w + (1 - beta2) * (w * w);
        v_b = beta2 * v_b + (1 - beta2) * b;

        const m_w_c = m_w / (1 - math.pow(f64, beta1, time));
        const m_b_c = m_b / (1 - math.pow(f64, beta1, time));
        const v_w_c = v_w / (1 - math.pow(f64, beta2, time));
        const v_b_c = v_b / (1 - math.pow(f64, beta2, time));

        w_0 = w_0 - alpha * (m_w_c / (@sqrt(v_w_c) + elipsion));
        b_0 = b_0 - alpha * (m_b_c / (@sqrt(v_b_c) + elipsion));
        std.debug.print("iteration {d}: weight {d}\n", .{ time, w_0 });
    }

    std.debug.print("converged {d}\n", .{time});
}
