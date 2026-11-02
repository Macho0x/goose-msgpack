// Times this package. One untimed batch, then batches until the window
// elapses. The sink keeps the call alive.
// Build with clang on the revision before a change, then again after:
//   goose build -o msgpack-bench bench.goose --cc clang
//   ./msgpack-bench
// Row names stay fixed. TinyCC (goose bench.goose) is not a timing result.
// ponytail: a fixed window, not a sampled harness. Rows under a microsecond
// move from run to run; lengthen the window before trusting them.

import os;
import encode;
import decode;
import value;

var small: u8[32] = [0x61; 32];
var big: u8[4096] = [0x62; 4096];
var tree: u8[>..] = [];

fn mark(b: u8, ok: bool) -> u64 {
    if !ok { return 0; }
    let v: u64 = b;
    return v + 1;
}

fn time_batch<F>(batch: i64, ms: i64) -> i64, u64 {
    var sink: u64 = 0;
    var k = 0;
    while k < batch {
        sink += F();
        k += 1;
    }
    var n: i64 = 0;
    var dt: i64 = 0;
    let end = clock_ns() + ms * 1000000;
    while true {
        let t0 = clock_ns();
        k = 0;
        while k < batch {
            sink += F();
            k += 1;
        }
        dt += clock_ns() - t0;
        n += batch;
        if clock_ns() >= end { break; }
    }
    return dt / n, sink;
}

fn row<F>(name: u8[:], batch: i64, ms: i64) -> u64 {
    let ns, part = time_batch(batch, ms, F);
    var line: u8[>..] = [];
    format(line, name);
    while line.len < 28 { line.push(' '); }
    format_int(line, ns, 10, 12, ' ');
    format(line, "\n");
    write_stdout(line);
    return part;
}

fn enc_small() -> u64 {
    small[0] += 1;
    var out: u8[>..] = [];
    encode::str(out, small);
    if out.len == 0 { return 0; }
    return mark(out[0], true);
}

fn enc_4k() -> u64 {
    big[0] += 1;
    var out: u8[>..] = [];
    encode::str(out, big);
    if out.len == 0 { return 0; }
    return mark(out[0], true);
}

fn dec_4k() -> u64 {
    big[1] += 1;
    var out: u8[>..] = [];
    encode::str(out, big);
    var at = 0;
    let s, ok = decode::str(out, at);
    if !ok || s.len != big.len { return 0; }
    return mark(s[0], true);
}

fn val_round() -> u64 {
    var pool: value::Node[>..] = [];
    if !value::decode(tree, pool) { return 0; }
    var out: u8[>..] = [];
    if !value::encode(pool, out) { return 0; }
    if out.len == 0 { return 0; }
    return mark(out[0], true);
}

fn ready() -> bool {
    var out: u8[>..] = [];
    encode::uint(out, 1);
    var at = 0;
    let n, ok = decode::uint(out, at);
    if !ok || n != 1 { return false; }
    tree.clear();
    encode::map(tree, 2);
    encode::str(tree, "z");
    encode::uint(tree, 1);
    encode::str(tree, "a");
    encode::uint(tree, 2);
    var want: u8[7] = [0x82, 0xa1, 0x7a, 0x01, 0xa1, 0x61, 0x02];
    if tree != want { return false; }
    var pool: value::Node[>..] = [];
    return value::decode(tree, pool) && value::root(pool);
}

fn ::main() {
    if !ready() { print("bench FAIL"); exit(1); }
    write_stdout("operation                       ns/call\n");
    var sink: u64 = 0;
    sink += row("encode str 32B", 32, 200, enc_small);
    sink += row("encode str 4KB", 8, 200, enc_4k);
    sink += row("decode str 4KB", 8, 200, dec_4k);
    sink += row("value roundtrip", 16, 200, val_round);
    var tail: u8[>..] = [];
    format(tail, "sink ");
    format(tail, sink);
    format(tail, "\n");
    write_stdout(tail);
}
