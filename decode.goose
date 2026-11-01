// MessagePack readers. The inverse of encode.
// Spec: https://github.com/msgpack/msgpack/blob/master/spec.md
// A short buffer, marker 0xc1, or a marker of the wrong family returns
// false. The other results are then meaningless. The cursor stays on that
// marker when the value is rejected. int and uint accept every integer
// marker whose value fits, so they read the shortest form encode writes.
// uint rejects a negative. int rejects an unsigned value above i64 max.
// str and bin are raw bytes. UTF-8 is not checked. This is not constant-time.
//
// nil, boolean, int, uint, float32, float64, str, bin, array, map, ext.
// number is the integer decode that int and uint share. array and map
// return a count. The caller reads the elements that follow. ext returns
// the signed type and the data bytes.

import std;

namespace decode;

fn have(src: u8[:], at: i64, n: i64) -> bool { at >= 0 && n >= 0 && at + n <= src.len }

// High bits of a negative two's-complement field, so the low `width` bits
// become the same i64 write_sint would have read.
fn sign_bits(raw: u64, width: i64) -> u64 {
    if width == 8 {
        if (raw & 0x80) == 0 { return raw; }
        return raw | 0xffffffffffffff00;
    }
    if width == 16 {
        if (raw & 0x8000) == 0 { return raw; }
        return raw | 0xffffffffffff0000;
    }
    if width == 32 {
        if (raw & 0x80000000) == 0 { return raw; }
        return raw | 0xffffffff00000000;
    }
    return raw;
}

fn be(src: u8[:], at: i64, n: i64) -> u64 {
    var raw: u64 = 0;
    for i in 0..n { raw = (raw << 8) | src[at + i]; }
    return raw;
}

fn number(src: u8[:], at: i64&) -> u64, bool, bool {
    if at >= src.len { return 0, false, false; }
    let m = src[at];
    if m <= 0x7f {
        at += 1;
        let bits: u64 = m;
        return bits, false, true;
    }
    if m >= 0xe0 {
        at += 1;
        let bits = sign_bits(m, 8);
        return bits, true, true;
    }
    if m == 0xcc || m == 0xd0 {
        if !have(src, at, 2) { return 0, false, false; }
        let raw: u64 = src[at + 1];
        at += 2;
        if m == 0xcc { return raw, false, true; }
        let bits = sign_bits(raw, 8);
        return bits, (bits >> 63) != 0, true;
    }
    if m == 0xcd || m == 0xd1 {
        if !have(src, at, 3) { return 0, false, false; }
        let raw = be(src, at + 1, 2);
        at += 3;
        if m == 0xcd { return raw, false, true; }
        let bits = sign_bits(raw, 16);
        return bits, (bits >> 63) != 0, true;
    }
    if m == 0xce || m == 0xd2 {
        if !have(src, at, 5) { return 0, false, false; }
        let raw = be(src, at + 1, 4);
        at += 5;
        if m == 0xce { return raw, false, true; }
        let bits = sign_bits(raw, 32);
        return bits, (bits >> 63) != 0, true;
    }
    if m == 0xcf || m == 0xd3 {
        if !have(src, at, 9) { return 0, false, false; }
        let raw = be(src, at + 1, 8);
        at += 9;
        if m == 0xcf { return raw, false, true; }
        return raw, (raw >> 63) != 0, true;
    }
    return 0, false, false;
}

fn int(src: u8[:], at: i64&) -> i64, bool {
    let start = at;
    let bits, neg, ok = number(src, at);
    if !ok { return 0, false; }
    if neg { return bits as! i64, true; }
    if (bits >> 63) != 0 { at = start; return 0, false; }
    return bits as i64, true;
}

fn uint(src: u8[:], at: i64&) -> u64, bool {
    let start = at;
    let bits, neg, ok = number(src, at);
    if !ok || neg { at = start; return 0, false; }
    return bits, true;
}

fn nil(src: u8[:], at: i64&) -> bool {
    if at >= src.len || src[at] != 0xc0 { return false; }
    at += 1;
    return true;
}

fn boolean(src: u8[:], at: i64&) -> bool, bool {
    if at >= src.len { return false, false; }
    let m = src[at];
    if m == 0xc3 { at += 1; return true, true; }
    if m == 0xc2 { at += 1; return false, true; }
    return false, false;
}

fn bits_f32(u: u32) -> f32 {
    var image: u8[>..] = [];
    image.push(4);
    image.push((u & 0xff) as! u8);
    image.push(((u >> 8) & 0xff) as! u8);
    image.push(((u >> 16) & 0xff) as! u8);
    image.push((u >> 24) as! u8);
    var a, ok = from_bytes<f32[>..]>(image);
    if !ok || a.len != 1 { abort("msgpack: float bits"); }
    return a[0];
}

fn bits_f64(u: u64) -> f64 {
    var image: u8[>..] = [];
    image.push(8);
    var x = u;
    for i in 0..8 {
        image.push((x & 0xff) as! u8);
        x = x >> 8;
    }
    var a, ok = from_bytes<f64[>..]>(image);
    if !ok || a.len != 1 { abort("msgpack: float bits"); }
    return a[0];
}

fn float32(src: u8[:], at: i64&) -> f32, bool {
    if at >= src.len || src[at] != 0xca { return 0.0, false; }
    if !have(src, at, 5) { return 0.0, false; }
    let bits = be(src, at + 1, 4) as u32;
    at += 5;
    return bits_f32(bits), true;
}

fn float64(src: u8[:], at: i64&) -> f64, bool {
    if at >= src.len || src[at] != 0xcb { return 0.0, false; }
    if !have(src, at, 9) { return 0.0, false; }
    let bits = be(src, at + 1, 8);
    at += 9;
    return bits_f64(bits), true;
}

enum Family { Str, Bin, Arr, Map }

fn sized(src: u8[:], at: i64&, family: Family) -> i64, i64, bool {
    if at >= src.len { return 0, 0, false; }
    let m = src[at];
    var n: i64 = -1;
    var head: i64 = 1;
    match family {
        Str => {
            if m >= 0xa0 && m <= 0xbf { n = m - 0xa0; }
            else if m == 0xd9 { head = 2; }
            else if m == 0xda { head = 3; }
            else if m == 0xdb { head = 5; }
            else { return 0, 0, false; }
        },
        Bin => {
            if m == 0xc4 { head = 2; }
            else if m == 0xc5 { head = 3; }
            else if m == 0xc6 { head = 5; }
            else { return 0, 0, false; }
        },
        Arr => {
            if m >= 0x90 && m <= 0x9f { n = m - 0x90; }
            else if m == 0xdc { head = 3; }
            else if m == 0xdd { head = 5; }
            else { return 0, 0, false; }
        },
        Map => {
            if m >= 0x80 && m <= 0x8f { n = m - 0x80; }
            else if m == 0xde { head = 3; }
            else if m == 0xdf { head = 5; }
            else { return 0, 0, false; }
        },
    }
    if !have(src, at, head) { return 0, 0, false; }
    if n < 0 && head == 2 { n = src[at + 1]; }
    if n < 0 && head == 3 { n = (src[at + 1] as i64) << 8 | src[at + 2]; }
    if n < 0 && head == 5 { n = be(src, at + 1, 4) as i64; }
    return n, head, true;
}

fn payload(src: u8[:], at: i64&, n: i64, head: i64) -> u8[:], bool {
    if n < 0 || !have(src, at, head + n) { return "", false; }
    let s = src[at + head..at + head + n];
    at += head + n;
    return s, true;
}

fn str(src: u8[:], at: i64&) -> u8[:], bool {
    let n, head, ok = sized(src, at, Family.Str);
    if !ok { return "", false; }
    return payload(src, at, n, head);
}

fn bin(src: u8[:], at: i64&) -> u8[:], bool {
    let n, head, ok = sized(src, at, Family.Bin);
    if !ok { return "", false; }
    return payload(src, at, n, head);
}

fn array(src: u8[:], at: i64&) -> i64, bool {
    let n, head, ok = sized(src, at, Family.Arr);
    if !ok || n < 0 || !have(src, at, head) { return 0, false; }
    at += head;
    return n, true;
}

fn map(src: u8[:], at: i64&) -> i64, bool {
    let n, head, ok = sized(src, at, Family.Map);
    if !ok || n < 0 || !have(src, at, head) { return 0, false; }
    at += head;
    return n, true;
}

fn ext(src: u8[:], at: i64&) -> i8, u8[:], bool {
    if at >= src.len { return 0, "", false; }
    let m = src[at];
    var n: i64 = -1;
    var head: i64 = 2;
    if m == 0xd4 { n = 1; }
    else if m == 0xd5 { n = 2; }
    else if m == 0xd6 { n = 4; }
    else if m == 0xd7 { n = 8; }
    else if m == 0xd8 { n = 16; }
    else if m == 0xc7 { head = 3; }
    else if m == 0xc8 { head = 4; }
    else if m == 0xc9 { head = 6; }
    else { return 0, "", false; }
    if !have(src, at, head) { return 0, "", false; }
    if m == 0xc7 { n = src[at + 1]; }
    else if m == 0xc8 { n = (src[at + 1] as i64) << 8 | src[at + 2]; }
    else if m == 0xc9 { n = be(src, at + 1, 4) as i64; }
    if n < 0 || !have(src, at, head + n) { return 0, "", false; }
    let typ = src[at + head - 1] as! i8;
    let data = src[at + head..at + head + n];
    at += head + n;
    return typ, data, true;
}
