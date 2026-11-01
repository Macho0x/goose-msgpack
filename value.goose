// One MessagePack value, as a tree in a caller-owned pool.
// Spec: https://github.com/msgpack/msgpack/blob/master/spec.md
// Push children before their parent, then link siblings in order. The root
// is the last node. A map chain is key, value, key, value, and the count
// is the pair count. Links are 4-byte self-relative offsets, so the tree
// stays inside the pool. decode clears the pool and reads one value.
// Bytes after that value stay unread. Failure clears the pool and returns
// false. encode appends the root. An empty pool returns false. An unsigned
// value above i64 max is Uint. Every smaller integer is Int. Ext type -1
// stays raw bytes. This is not constant-time.
//
// Link siblings with prev.next .= nxt in the function that received both
// nodes from this pool, then push the parent there too. A helper cannot
// see that a parameter shares the pool's root. array and map with no
// children are the empty containers.
//
// Value, Node, root, nil, boolean, int, uint, float32, float64, str, bin,
// ext, array, map, decode, encode.

import std;
import encode;
import decode;

namespace value;

enum Value {
    Nil,
    Bool { v: bool },
    Int { n: i64 },
    Uint { n: u64 },
    F32 { v: f32 },
    F64 { v: f64 },
    Str { s: u8[varint] },
    Bin { b: u8[varint] },
    Arr { first: Node&<u32>?, count: i64 },
    Map { first: Node&<u32>?, count: i64 },
    Ext { typ: i8, data: u8[varint] },
}

struct Node { next: Node&<u32>?, val: Value.. }

fn root(pool: Node[>..]&) -> Node? {
    var last: Node? = null;
    for n in pool { last .= n; }
    return last;
}

fn nil(pool: Node[>..]&) -> Node& {
    pool.push(Node { next: null, val: Value.Nil })
}

fn boolean(pool: Node[>..]&, v: bool) -> Node& {
    pool.push(Node { next: null, val: Value.Bool { v: v } })
}

fn int(pool: Node[>..]&, n: i64) -> Node& {
    pool.push(Node { next: null, val: Value.Int { n: n } })
}

fn uint(pool: Node[>..]&, n: u64) -> Node& {
    pool.push(Node { next: null, val: Value.Uint { n: n } })
}

fn float32(pool: Node[>..]&, v: f32) -> Node& {
    pool.push(Node { next: null, val: Value.F32 { v: v } })
}

fn float64(pool: Node[>..]&, v: f64) -> Node& {
    pool.push(Node { next: null, val: Value.F64 { v: v } })
}

fn str(pool: Node[>..]&, s: u8[:]) -> Node& {
    pool.push(Node { next: null, val: Value.Str { s: s } })
}

fn bin(pool: Node[>..]&, b: u8[:]) -> Node& {
    pool.push(Node { next: null, val: Value.Bin { b: b } })
}

fn ext(pool: Node[>..]&, typ: i8, data: u8[:]) -> Node& {
    pool.push(Node { next: null, val: Value.Ext { typ: typ, data: data } })
}

fn array(pool: Node[>..]&) -> Node& {
    pool.push(Node { next: null, val: Value.Arr { first: null, count: 0 } })
}

fn map(pool: Node[>..]&) -> Node& {
    pool.push(Node { next: null, val: Value.Map { first: null, count: 0 } })
}

recursive fn read_array(src: u8[:], at: i64&, pool: Node[>..]&) -> Node? {
    let n, ok = decode::array(src, at);
    if !ok { return null; }
    var first: Node? = null;
    if n > 0 {
        let head = read_value(src, at, pool);
        if !head { return null; }
        first .= head;
        var last .= head;
        for i in 1..n {
            let child = read_value(src, at, pool);
            if !child { return null; }
            last.next .= child;
            last .= child;
        }
    }
    return pool.push(Node { next: null, val: Value.Arr { first: first, count: n } });
}

recursive fn read_map(src: u8[:], at: i64&, pool: Node[>..]&) -> Node? {
    let n, ok = decode::map(src, at);
    if !ok { return null; }
    var first: Node? = null;
    if n > 0 {
        let key = read_value(src, at, pool);
        if !key { return null; }
        let val = read_value(src, at, pool);
        if !val { return null; }
        key.next .= val;
        first .= key;
        var last .= val;
        for i in 1..n {
            let key2 = read_value(src, at, pool);
            if !key2 { return null; }
            last.next .= key2;
            let val2 = read_value(src, at, pool);
            if !val2 { return null; }
            key2.next .= val2;
            last .= val2;
        }
    }
    return pool.push(Node { next: null, val: Value.Map { first: first, count: n } });
}

recursive fn read_value(src: u8[:], at: i64&, pool: Node[>..]&) -> Node? {
    if at >= src.len { return null; }
    let m = src[at];
    if m <= 0x7f || m >= 0xe0 || (m >= 0xcc && m <= 0xd3) {
        let bits, neg, ok = decode::number(src, at);
        if !ok { return null; }
        if neg { return pool.push(Node { next: null, val: Value.Int { n: bits as! i64 } }); }
        if (bits >> 63) != 0 { return pool.push(Node { next: null, val: Value.Uint { n: bits } }); }
        return pool.push(Node { next: null, val: Value.Int { n: bits as i64 } });
    }
    if m == 0xc0 {
        if !decode::nil(src, at) { return null; }
        return pool.push(Node { next: null, val: Value.Nil });
    }
    if m == 0xc2 || m == 0xc3 {
        let v, ok = decode::boolean(src, at);
        if !ok { return null; }
        return pool.push(Node { next: null, val: Value.Bool { v: v } });
    }
    if m == 0xca {
        let v, ok = decode::float32(src, at);
        if !ok { return null; }
        return pool.push(Node { next: null, val: Value.F32 { v: v } });
    }
    if m == 0xcb {
        let v, ok = decode::float64(src, at);
        if !ok { return null; }
        return pool.push(Node { next: null, val: Value.F64 { v: v } });
    }
    if (m >= 0xa0 && m <= 0xbf) || m == 0xd9 || m == 0xda || m == 0xdb {
        let s, ok = decode::str(src, at);
        if !ok { return null; }
        return pool.push(Node { next: null, val: Value.Str { s: s } });
    }
    if m == 0xc4 || m == 0xc5 || m == 0xc6 {
        let b, ok = decode::bin(src, at);
        if !ok { return null; }
        return pool.push(Node { next: null, val: Value.Bin { b: b } });
    }
    if m == 0xc7 || m == 0xc8 || m == 0xc9 || (m >= 0xd4 && m <= 0xd8) {
        let typ, data, ok = decode::ext(src, at);
        if !ok { return null; }
        return pool.push(Node { next: null, val: Value.Ext { typ: typ, data: data } });
    }
    if (m >= 0x90 && m <= 0x9f) || m == 0xdc || m == 0xdd { return read_array(src, at, pool); }
    if (m >= 0x80 && m <= 0x8f) || m == 0xde || m == 0xdf { return read_map(src, at, pool); }
    return null;
}

fn decode(src: u8[:], pool: Node[>..]&) -> bool {
    pool.clear();
    var at = 0;
    var ok = false;
    {
        let node = read_value(src, at, pool);
        if node { ok = true; }
    }
    if ok { return true; }
    pool.clear();
    return false;
}

recursive fn write_node(n: Node&, out: u8[>..]&) -> bool {
    match n.val {
        Nil => { encode::nil(out); },
        Bool b => { encode::boolean(out, b.v); },
        Int x => { encode::int(out, x.n); },
        Uint x => { encode::uint(out, x.n); },
        F32 x => { encode::float32(out, x.v); },
        F64 x => { encode::float64(out, x.v); },
        Str &s => { encode::str(out, s.s); },
        Bin &b => { encode::bin(out, b.b); },
        Ext &e => { encode::ext(out, e.typ, e.data); },
        Arr &a => {
            encode::array(out, a.count);
            var c = a.first;
            for i in a.count {
                if !c { return false; }
                if !write_node(c, out) { return false; }
                c .= c.next;
            }
        },
        Map &m => {
            encode::map(out, m.count);
            var c = m.first;
            for i in m.count {
                if !c { return false; }
                if !write_node(c, out) { return false; }
                let v = c.next;
                if !v { return false; }
                if !write_node(v, out) { return false; }
                c .= v.next;
            }
        },
    }
    return true;
}

fn encode(pool: Node[>..]&, out: u8[>..]&) -> bool {
    let r = root(pool);
    if !r { return false; }
    return write_node(r, out);
}
