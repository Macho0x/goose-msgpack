# goose-msgpack

Version 0.1.

MessagePack for [Goose](https://github.com/aardappel/goose). The bytes follow the [MessagePack specification](https://github.com/msgpack/msgpack/blob/master/spec.md). Integers use the shortest form from rmp's `write_sint` and `write_uint`. A map keeps the order you append its pairs in. That is what `rmp_serde::to_vec_named` does for struct fields.

Copyright 2026 Macho0x. Licensed under Apache-2.0, the same license as Goose.

## Check

Install the Goose compiler, then from this directory:

```sh
goose tests/self_check.goose
```

A good run prints `msgpack ok`.

`msgpack.goose` is the package entry. It does not load a codec. From another directory:

```goose
import msgpack from "../msgpack";
import msgpack.encode;

fn main() {
    var out: u8[>..] = [];
    encode::nil(out);
    encode::boolean(out, true);
    print(out);
}
```

## Modules

| Module | What it does |
| --- | --- |
| `encode` | Appends one value to a `u8[>..]` you own |
| `decode` | Reads those bytes. A short or illegal buffer returns false |
| `value` | A tree of nil, bool, int, float, str, bin, array, map, and ext |

Positive integers use the unsigned family, including a positive fixint. Negative integers use a negative fixint or a signed header. `float32` stays 32 bits and `float64` stays 64 bits, both IEEE-754 big-endian. `str` and `bin` are raw bytes, with no UTF-8 check. Ext type -1 stays raw bytes.

`value::decode` clears the pool you pass, then reads one value. Bytes after that value are left in the buffer. The root is the last node. Build a container in the function that pushed its children, and link siblings with `prev.next .= nxt` there. `PORTING.md` lists what this package leaves out of rmp.
