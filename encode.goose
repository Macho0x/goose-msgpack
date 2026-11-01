// MessagePack writers.
// Spec: https://github.com/msgpack/msgpack/blob/master/spec.md
// Integers use the shortest form, the same choice as rmp's write_sint and
// write_uint. A positive value uses the unsigned family. A negative value
// uses negative fixint, int8, int16, int32, or int64. Floats are IEEE-754
// big-endian. str, bin, array, map, and ext use the shortest header.
// map appends pairs in the order the caller writes them. String keys in
// that order are the bytes rmp_serde::to_vec_named writes for a struct.
// Width follows the value, so this is not constant-time.
//
// nil, boolean, int, uint, float32, float64, str, bin, array, map, ext.
// Each appends to a caller-owned u8[>..]. A length outside 0 .. 2^32-1 aborts.

import std;

namespace encode;

const MAX_LEN: i64 = 4294967295;

fn fits(n: i64) -> bool { n >= 0 && n <= MAX_LEN }

fn put_u16(out: u8[>..]&, v: u16) {
    out.push((v >> 8) as! u8);
    out.push((v & 0xff) as! u8);
}

fn put_u32(out: u8[>..]&, v: u32) {
    out.push((v >> 24) as! u8);
    out.push(((v >> 16) & 0xff) as! u8);
    out.push(((v >> 8) & 0xff) as! u8);
    out.push((v & 0xff) as! u8);
}

fn put_u64(out: u8[>..]&, v: u64) {
    out.push((v >> 56) as! u8);
    out.push(((v >> 48) & 0xff) as! u8);
    out.push(((v >> 40) & 0xff) as! u8);
    out.push(((v >> 32) & 0xff) as! u8);
    out.push(((v >> 24) & 0xff) as! u8);
    out.push(((v >> 16) & 0xff) as! u8);
    out.push(((v >> 8) & 0xff) as! u8);
    out.push((v & 0xff) as! u8);
}

// to_bytes prefixes a uleb length. One f32 is length 4, then four
// little-endian IEEE-754 bytes. MessagePack wants those bytes reversed.
fn f32_bits(v: f32) -> u32 {
    var a: f32[1] = [v];
    let b = a.to_bytes();
    if b.len != 5 || b[0] != 4 { abort("msgpack: float image"); }
    return b[1] | (b[2] as u32) << 8 | (b[3] as u32) << 16 | (b[4] as u32) << 24;
}

fn f64_bits(v: f64) -> u64 {
    var a: f64[1] = [v];
    let b = a.to_bytes();
    if b.len != 9 || b[0] != 8 { abort("msgpack: float image"); }
    var u: u64 = 0;
    for i in 0..8 { u = u | (b[1 + i] as u64) << (i * 8); }
    return u;
}

fn nil(out: u8[>..]&) { out.push(0xc0); }

fn boolean(out: u8[>..]&, v: bool) {
    if v { out.push(0xc3); } else { out.push(0xc2); }
}

fn uint(out: u8[>..]&, v: u64) {
    if v <= 127 { out.push(v as u8); return; }
    if v <= 255 { out.push(0xcc); out.push(v as u8); return; }
    if v <= 65535 { out.push(0xcd); put_u16(out, v as u16); return; }
    if v <= 4294967295 { out.push(0xce); put_u32(out, v as u32); return; }
    out.push(0xcf);
    put_u64(out, v);
}

fn int(out: u8[>..]&, v: i64) {
    if v >= 0 { uint(out, v as u64); return; }
    if v >= -32 { out.push(v as! u8); return; }
    if v >= -128 { out.push(0xd0); out.push(v as! u8); return; }
    if v >= -32768 { out.push(0xd1); put_u16(out, v as! u16); return; }
    if v >= -2147483648 { out.push(0xd2); put_u32(out, v as! u32); return; }
    out.push(0xd3);
    put_u64(out, v as! u64);
}

fn float32(out: u8[>..]&, v: f32) {
    out.push(0xca);
    put_u32(out, f32_bits(v));
}

fn float64(out: u8[>..]&, v: f64) {
    out.push(0xcb);
    put_u64(out, f64_bits(v));
}

fn str(out: u8[>..]&, s: u8[:]) {
    let n = s.len;
    if !fits(n) { abort("msgpack: a length must fit in 32 bits"); }
    if n <= 31 { out.push(0xa0 + (n as u8)); }
    else if n <= 255 { out.push(0xd9); out.push(n as u8); }
    else if n <= 65535 { out.push(0xda); put_u16(out, n as u16); }
    else { out.push(0xdb); put_u32(out, n as u32); }
    out.append(s);
}

fn bin(out: u8[>..]&, b: u8[:]) {
    let n = b.len;
    if !fits(n) { abort("msgpack: a length must fit in 32 bits"); }
    if n <= 255 { out.push(0xc4); out.push(n as u8); }
    else if n <= 65535 { out.push(0xc5); put_u16(out, n as u16); }
    else { out.push(0xc6); put_u32(out, n as u32); }
    out.append(b);
}

fn array(out: u8[>..]&, n: i64) {
    if !fits(n) { abort("msgpack: a length must fit in 32 bits"); }
    if n <= 15 { out.push(0x90 + (n as u8)); return; }
    if n <= 65535 { out.push(0xdc); put_u16(out, n as u16); return; }
    out.push(0xdd);
    put_u32(out, n as u32);
}

fn map(out: u8[>..]&, n: i64) {
    if !fits(n) { abort("msgpack: a length must fit in 32 bits"); }
    if n <= 15 { out.push(0x80 + (n as u8)); return; }
    if n <= 65535 { out.push(0xde); put_u16(out, n as u16); return; }
    out.push(0xdf);
    put_u32(out, n as u32);
}

fn ext(out: u8[>..]&, typ: i8, data: u8[:]) {
    let n = data.len;
    if !fits(n) { abort("msgpack: a length must fit in 32 bits"); }
    if n == 1 { out.push(0xd4); }
    else if n == 2 { out.push(0xd5); }
    else if n == 4 { out.push(0xd6); }
    else if n == 8 { out.push(0xd7); }
    else if n == 16 { out.push(0xd8); }
    else if n <= 255 { out.push(0xc7); out.push(n as u8); }
    else if n <= 65535 { out.push(0xc8); put_u16(out, n as u16); }
    else { out.push(0xc9); put_u32(out, n as u32); }
    out.push(typ as! u8);
    out.append(data);
}
