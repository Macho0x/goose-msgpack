import msgpack from "..";
import msgpack.encode;
import msgpack.decode;
import msgpack.value;
import os;

fn eq(a: u8[:], b: u8[:]) -> bool {
    if a.len != b.len { return false; }
    for i in 0..a.len {
        if a[i] != b[i] { return false; }
    }
    return true;
}

fn enc_i(v: i64, exp: u8[:]) -> bool {
    var out: u8[>..] = [];
    encode::int(out, v);
    return eq(out, exp);
}

fn enc_u(v: u64, exp: u8[:]) -> bool {
    var out: u8[>..] = [];
    encode::uint(out, v);
    return eq(out, exp);
}

fn dec_i(src: u8[:], expect: i64) -> bool {
    var at = 0;
    let n, ok = decode::int(src, at);
    return ok && n == expect && at == src.len;
}

fn dec_u(src: u8[:], expect: u64) -> bool {
    var at = 0;
    let n, ok = decode::uint(src, at);
    return ok && n == expect && at == src.len;
}

fn dec_i_bad(src: u8[:]) -> bool {
    var at = 0;
    let n, ok = decode::int(src, at);
    return !ok && n == 0;
}

fn check_encode() -> bool {
    var out: u8[>..] = [];
    encode::nil(out);
    if !eq(out, [0xc0]) { return false; }
    out.clear();
    encode::boolean(out, false);
    if !eq(out, [0xc2]) { return false; }
    out.clear();
    encode::boolean(out, true);
    if !eq(out, [0xc3]) { return false; }

    if !enc_i(0, [0x00]) { return false; }
    if !enc_i(1, [0x01]) { return false; }
    if !enc_i(127, [0x7f]) { return false; }
    if !enc_i(-1, [0xff]) { return false; }
    if !enc_i(-32, [0xe0]) { return false; }
    if !enc_i(-33, [0xd0, 0xdf]) { return false; }
    if !enc_i(-128, [0xd0, 0x80]) { return false; }
    if !enc_i(-129, [0xd1, 0xff, 0x7f]) { return false; }
    if !enc_i(-32768, [0xd1, 0x80, 0x00]) { return false; }
    if !enc_i(-32769, [0xd2, 0xff, 0xff, 0x7f, 0xff]) { return false; }
    if !enc_i(-2147483648, [0xd2, 0x80, 0x00, 0x00, 0x00]) { return false; }
    if !enc_i(-2147483649, [0xd3, 0xff, 0xff, 0xff, 0xff, 0x7f, 0xff, 0xff, 0xff]) { return false; }
    let lo = -9223372036854775807 - 1;
    if !enc_i(lo, [0xd3, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) { return false; }

    if !enc_u(128, [0xcc, 0x80]) { return false; }
    if !enc_u(255, [0xcc, 0xff]) { return false; }
    if !enc_u(256, [0xcd, 0x01, 0x00]) { return false; }
    if !enc_u(65535, [0xcd, 0xff, 0xff]) { return false; }
    if !enc_u(65536, [0xce, 0x00, 0x01, 0x00, 0x00]) { return false; }
    if !enc_u(4294967295, [0xce, 0xff, 0xff, 0xff, 0xff]) { return false; }
    let big32: u64 = 4294967296;
    if !enc_u(big32, [0xcf, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]) { return false; }
    let big: u64 = 18446744073709551615;
    if !enc_u(big, [0xcf, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]) { return false; }
    if !enc_i(128, [0xcc, 0x80]) { return false; }

    out.clear();
    encode::float32(out, 1.0);
    if !eq(out, [0xca, 0x3f, 0x80, 0x00, 0x00]) { return false; }
    out.clear();
    encode::float32(out, 0.5);
    if !eq(out, [0xca, 0x3f, 0x00, 0x00, 0x00]) { return false; }
    out.clear();
    encode::float64(out, 1.0);
    if !eq(out, [0xcb, 0x3f, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) { return false; }
    out.clear();
    encode::float64(out, -2.5);
    if !eq(out, [0xcb, 0xc0, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) { return false; }

    out.clear();
    encode::str(out, "");
    if !eq(out, [0xa0]) { return false; }
    out.clear();
    encode::str(out, "hi");
    if !eq(out, [0xa2, 0x68, 0x69]) { return false; }
    var letters: u8[>..] = [];
    for i in 31 { letters.push('a'); }
    out.clear();
    encode::str(out, letters);
    if out.len != 32 || out[0] != 0xbf { return false; }
    for i in 31 { if out[1 + i] != 'a' { return false; } }
    letters.push('a');
    out.clear();
    encode::str(out, letters);
    if out.len != 34 || out[0] != 0xd9 || out[1] != 32 { return false; }
    for i in 32 { if out[2 + i] != 'a' { return false; } }

    out.clear();
    encode::bin(out, "");
    if !eq(out, [0xc4, 0x00]) { return false; }
    out.clear();
    encode::bin(out, [0xab]);
    if !eq(out, [0xc4, 0x01, 0xab]) { return false; }
    var blob: u8[>..] = [];
    for i in 256 { blob.push(1); }
    out.clear();
    encode::bin(out, blob);
    if out.len != 259 || out[0] != 0xc5 || out[1] != 0x01 || out[2] != 0x00 { return false; }
    for i in 256 { if out[3 + i] != 1 { return false; } }

    out.clear();
    encode::array(out, 0);
    if !eq(out, [0x90]) { return false; }
    out.clear();
    encode::array(out, 2);
    encode::int(out, 1);
    encode::int(out, 2);
    if !eq(out, [0x92, 0x01, 0x02]) { return false; }
    out.clear();
    encode::array(out, 16);
    for i in 16 { encode::int(out, 0); }
    if out.len != 19 || out[0] != 0xdc || out[1] != 0x00 || out[2] != 16 { return false; }
    for i in 16 { if out[3 + i] != 0 { return false; } }

    out.clear();
    encode::map(out, 0);
    if !eq(out, [0x80]) { return false; }
    out.clear();
    encode::map(out, 1);
    encode::str(out, "a");
    encode::int(out, 1);
    if !eq(out, [0x81, 0xa1, 0x61, 0x01]) { return false; }

    // Keys "z" then "a". Byte 0x7a is the first key and 0x61 is the second.
    out.clear();
    encode::map(out, 2);
    encode::str(out, "z");
    encode::int(out, 1);
    encode::str(out, "a");
    encode::int(out, 2);
    if out.len < 6 || out[2] != 0x7a || out[5] != 0x61 { return false; }
    if !eq(out, [0x82, 0xa1, 0x7a, 0x01, 0xa1, 0x61, 0x02]) { return false; }

    out.clear();
    encode::ext(out, 1, [0x02]);
    if !eq(out, [0xd4, 0x01, 0x02]) { return false; }
    out.clear();
    encode::ext(out, -1, [0x02]);
    if !eq(out, [0xd4, 0xff, 0x02]) { return false; }
    out.clear();
    encode::ext(out, 0, "");
    if !eq(out, [0xc7, 0x00, 0x00]) { return false; }
    out.clear();
    encode::ext(out, 3, "abc");
    if !eq(out, [0xc7, 0x03, 0x03, 0x61, 0x62, 0x63]) { return false; }
    out.clear();
    encode::ext(out, 4, [0x05, 0x06, 0x07, 0x08]);
    if !eq(out, [0xd6, 0x04, 0x05, 0x06, 0x07, 0x08]) { return false; }
    return true;
}

fn check_decode() -> bool {
    var at = 0;
    if !decode::nil([0xc0], at) || at != 1 { return false; }
    at = 0;
    if decode::nil([0xc2], at) || at != 0 { return false; }
    at = 0;
    if decode::nil([0xc1], at) { return false; }
    at = 0;
    let f, fok = decode::boolean([0xc2], at);
    if !fok || f || at != 1 { return false; }
    at = 0;
    let t, tok = decode::boolean([0xc3], at);
    if !tok || !t || at != 1 { return false; }
    at = 0;
    let badb, bok = decode::boolean([0xc1], at);
    if bok || badb || at != 0 { return false; }

    if !dec_i([0x00], 0) { return false; }
    if !dec_i([0x01], 1) { return false; }
    if !dec_i([0x7f], 127) { return false; }
    if !dec_i([0xff], -1) { return false; }
    if !dec_i([0xe0], -32) { return false; }
    if !dec_i([0xd0, 0xdf], -33) { return false; }
    if !dec_i([0xd0, 0x80], -128) { return false; }
    if !dec_i([0xd1, 0xff, 0x7f], -129) { return false; }
    if !dec_i([0xd1, 0x80, 0x00], -32768) { return false; }
    if !dec_i([0xd2, 0xff, 0xff, 0x7f, 0xff], -32769) { return false; }
    if !dec_i([0xd2, 0x80, 0x00, 0x00, 0x00], -2147483648) { return false; }
    if !dec_i([0xd3, 0xff, 0xff, 0xff, 0xff, 0x7f, 0xff, 0xff, 0xff], -2147483649) { return false; }
    let lo = -9223372036854775807 - 1;
    if !dec_i([0xd3, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00], lo) { return false; }
    if !dec_i([0xcc, 0x80], 128) { return false; }
    if !dec_i([0xd0, 0x01], 1) { return false; }
    if !dec_i_bad([0xcf, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]) { return false; }
    if !dec_i_bad([]) { return false; }
    if !dec_i_bad([0xcd]) { return false; }
    if !dec_i_bad([0xcd, 0x01]) { return false; }
    if !dec_i_bad([0xc1]) { return false; }

    at = 0;
    let u, uok = decode::uint([0xff], at);
    if uok || u != 0 || at != 0 { return false; }
    if !dec_u([0xcc, 0x80], 128) { return false; }
    if !dec_u([0xcd, 0x01, 0x00], 256) { return false; }
    if !dec_u([0xce, 0xff, 0xff, 0xff, 0xff], 4294967295) { return false; }
    let big: u64 = 18446744073709551615;
    if !dec_u([0xcf, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff], big) { return false; }
    at = 0;
    let neg, nok = decode::uint([0xd0, 0x80], at);
    if nok || at != 0 { return false; }

    at = 0;
    let f32v, f32ok = decode::float32([0xca, 0x3f, 0x80, 0x00, 0x00], at);
    if !f32ok || f32v != 1.0 || at != 5 { return false; }
    at = 0;
    let f64v, f64ok = decode::float64([0xcb, 0x3f, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00], at);
    if !f64ok || f64v != 1.0 || at != 9 { return false; }
    at = 0;
    let short, short_ok = decode::float64([0xcb, 0x3f], at);
    if short_ok || short != 0.0 { return false; }

    var hi: u8[] = [0xa2, 0x68, 0x69];
    at = 0;
    let s, sok = decode::str(hi, at);
    if !sok || s != "hi" || at != 3 { return false; }
    var empty_src: u8[] = [0xa0];
    at = 0;
    let empty, eok = decode::str(empty_src, at);
    if !eok || empty.len != 0 || at != 1 { return false; }
    var cut_src: u8[] = [0xa5, 0x68, 0x69];
    at = 0;
    let cut, cok = decode::str(cut_src, at);
    if cok || cut.len != 0 { return false; }

    var bin_src: u8[] = [0xc4, 0x01, 0xab];
    at = 0;
    let b, bok2 = decode::bin(bin_src, at);
    if !bok2 || b.len != 1 || b[0] != 0xab || at != 3 { return false; }
    at = 0;
    let n, aok = decode::array([0x92, 0x01, 0x02], at);
    if !aok || n != 2 || at != 1 { return false; }
    var arr16: u8[] = [0xdc, 0x00, 0x10];
    at = 0;
    let n16, a16ok = decode::array(arr16, at);
    if !a16ok || n16 != 16 || at != 3 { return false; }
    var arr32: u8[] = [0xdd, 0x00, 0x00, 0x00, 0x02];
    at = 0;
    let n32, a32ok = decode::array(arr32, at);
    if !a32ok || n32 != 2 || at != 5 { return false; }
    at = 0;
    let nbad, a16 = decode::array([0xdc], at);
    if a16 || nbad != 0 { return false; }
    var str16: u8[] = [0xda, 0x00, 0x02, 0x68, 0x69];
    at = 0;
    let wide, wok = decode::str(str16, at);
    if !wok || wide != "hi" || at != 5 { return false; }
    at = 0;
    let pairs, mok = decode::map([0x82, 0xa1, 0x7a, 0x01, 0xa1, 0x61, 0x02], at);
    if !mok || pairs != 2 || at != 1 { return false; }

    var ext_src: u8[] = [0xd4, 0xff, 0x02];
    at = 0;
    let typ, data, xok = decode::ext(ext_src, at);
    if !xok || typ != -1 || data.len != 1 || data[0] != 0x02 || at != 3 { return false; }
    var ext3: u8[] = [0xc7, 0x03, 0x03, 0x61, 0x62, 0x63];
    at = 0;
    let typ3, data3, x3 = decode::ext(ext3, at);
    if !x3 || typ3 != 3 || data3 != "abc" { return false; }
    return true;
}

fn is_nil(n: value::Node&) -> bool {
    match n.val {
        Nil => true,
        _ => false,
    }
}

fn is_true(n: value::Node&) -> bool {
    match n.val {
        Bool b => b.v,
        _ => false,
    }
}

fn int_is(n: value::Node&, expect: i64) -> bool {
    match n.val {
        Int x => x.n == expect,
        _ => false,
    }
}

fn uint_is(n: value::Node&, expect: u64) -> bool {
    match n.val {
        Uint x => x.n == expect,
        _ => false,
    }
}

fn str_is(n: value::Node&, expect: u8[:]) -> bool {
    match n.val {
        Str &s => s.s == expect,
        _ => false,
    }
}

fn array_true_nil(n: value::Node&) -> bool {
    match n.val {
        Arr &a => a.count == 2 && arr_elems(a.first),
        _ => false,
    }
}

fn arr_elems(first: value::Node?) -> bool {
    if !first || !is_true(first) { return false; }
    let e1 = first.next;
    if !e1 || !is_nil(e1) { return false; }
    return true;
}

fn map_pairs(first: value::Node?) -> bool {
    if !first || !str_is(first, "b") { return false; }
    let v1 = first.next;
    if !v1 || !array_true_nil(v1) { return false; }
    let k2 = v1.next;
    if !k2 || !str_is(k2, "a") { return false; }
    let v2 = k2.next;
    if !v2 || !str_is(v2, "x") { return false; }
    return true;
}

fn nested_shape(n: value::Node&) -> bool {
    match n.val {
        Map &m => m.count == 2 && map_pairs(m.first),
        _ => false,
    }
}

fn reload(src: u8[:]) -> bool {
    var pool: value::Node[>..] = [];
    if !value::decode(src, pool) { return false; }
    var out: u8[>..] = [];
    if !value::encode(pool, out) { return false; }
    return eq(out, src);
}

fn check_value() -> bool {
    var pool: value::Node[>..] = [];
    var out: u8[>..] = [];
    if value::encode(pool, out) { return false; }

    if !value::decode([0xc0, 0xff], pool) { return false; }
    let nil_node = value::root(pool);
    if !nil_node || !is_nil(nil_node) { return false; }
    out.clear();
    if !value::encode(pool, out) || !eq(out, [0xc0]) { return false; }

    if value::decode([], pool) { return false; }
    if value::root(pool) { return false; }
    if value::decode([0xc1], pool) { return false; }
    if value::decode([0x91], pool) { return false; }
    if value::decode([0xa5, 0x68, 0x69], pool) { return false; }

    if !value::decode([0xd0, 0x01], pool) { return false; }
    let one = value::root(pool);
    if !one || !int_is(one, 1) { return false; }
    out.clear();
    if !value::encode(pool, out) || !eq(out, [0x01]) { return false; }

    let lo = -9223372036854775807 - 1;
    if !reload([0xd3, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) { return false; }
    if !value::decode([0xd3, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00], pool) { return false; }
    let lo_node = value::root(pool);
    if !lo_node || !int_is(lo_node, lo) { return false; }
    let big: u64 = 18446744073709551615;
    if !reload([0xcf, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]) { return false; }
    if !value::decode([0xcf, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff], pool) { return false; }
    let big_node = value::root(pool);
    if !big_node || !uint_is(big_node, big) { return false; }

    if !reload([0xca, 0x3f, 0x80, 0x00, 0x00]) { return false; }
    if !reload([0xca, 0x3f, 0x00, 0x00, 0x00]) { return false; }
    if !reload([0xcb, 0x3f, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) { return false; }
    if !reload([0xcb, 0xc0, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) { return false; }
    if !reload([0xcb, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) { return false; }
    if !reload([0xc4, 0x01, 0xab]) { return false; }
    if !reload([0xa2, 0x68, 0x69]) { return false; }
    if !reload([0x92, 0x01, 0x02]) { return false; }
    if !reload([0xd4, 0x01, 0x02]) { return false; }
    if !reload([0xd4, 0xff, 0x02]) { return false; }
    if !reload([0xc7, 0x03, 0x03, 0x61, 0x62, 0x63]) { return false; }

    var nested: u8[] = [0x82, 0xa1, 0x62, 0x92, 0xc3, 0xc0, 0xa1, 0x61, 0xa1, 0x78];
    if !reload(nested) { return false; }
    if !value::decode(nested, pool) { return false; }
    let top = value::root(pool);
    if !top || !nested_shape(top) { return false; }

    // Built in push order "z" then "a", same bytes as the encoder test.
    var built: value::Node[>..] = [];
    let z .= value::str(built, "z");
    let n1 .= value::int(built, 1);
    z.next .= n1;
    let a .= value::str(built, "a");
    n1.next .= a;
    let n2 .= value::int(built, 2);
    a.next .= n2;
    built.push(value::Node { next: null, val: value::Value.Map { first: z, count: 2 } });
    out.clear();
    if !value::encode(built, out) { return false; }
    if out.len < 6 || out[2] != 0x7a || out[5] != 0x61 { return false; }
    if !eq(out, [0x82, 0xa1, 0x7a, 0x01, 0xa1, 0x61, 0x02]) { return false; }
    return true;
}

fn fail(name: u8[:]) {
    write_stdout(name);
    write_stdout(" FAIL\n");
    exit(1);
}

fn ::main() {
    if !check_encode() { fail("encode"); }
    if !check_decode() { fail("decode"); }
    if !check_value() { fail("value"); }
    write_stdout("msgpack ok\n");
}
