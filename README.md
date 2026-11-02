<p align="center">
  <img src="logo.png" alt="A goose holding a tied parcel" width="220">
</p>

<h1 align="center">goose-msgpack</h1>

<p align="center">
  📦 MessagePack for <a href="https://github.com/aardappel/goose">Goose</a><br>
  <strong>0.2.2</strong> · <a href="LICENSE">Apache-2.0</a>
</p>

Reads and writes [MessagePack](https://github.com/msgpack/msgpack/blob/master/spec.md) bytes. Integers use the shortest form, the same choice as rmp's `write_sint` and `write_uint`. A map keeps the order you append its pairs in. That is the order `rmp_serde::to_vec_named` uses for struct fields.

## Example

```goose
import msgpack from "../msgpack";
import msgpack.encode;

fn main() {
    var out: u8[>..] = [];
    encode::map(out, 2);
    encode::str(out, "z");
    encode::uint(out, 1);
    encode::str(out, "a");
    encode::uint(out, 2);
    print(out);
}
```

That map is the bytes `82 a1 7a 01 a1 61 02`. `msgpack.goose` is the package entry. It does not load a codec. `import msgpack.encode` does.

## Check

Install the Goose compiler, then from this directory:

```sh
goose tests/self_check.goose
```

A good run prints `msgpack ok`.

## Modules

| Module | What it does |
| --- | --- |
| `encode` | Appends one value to a `u8[>..]` you own |
| `decode` | Reads those bytes. A short or illegal buffer returns false |
| `value` | A tree of nil, bool, int, float, str, bin, array, map, and ext |

## Good to know

Positive integers use the unsigned family, including a positive fixint. Negative integers use a negative fixint or a signed header. `float32` stays 32 bits and `float64` stays 64 bits, both IEEE-754 big-endian. `str` and `bin` are raw bytes, with no UTF-8 check. Ext type -1 stays raw bytes.

`value::decode` clears the pool you pass, then reads one value. Bytes after that value are left in the buffer. The root is the last node. `PORTING.md` lists what this package leaves out of rmp, including serde and timestamps.

## Benchmarks

`bench.goose` times this package. The row names stay fixed, so a clang run before a change and a clang run after it compare.

```sh
goose build -o msgpack-bench bench.goose --cc clang
./msgpack-bench
```

`goose bench.goose` runs in TinyCC. That is not a timing result. Numbers depend on the machine, so this page does not publish them.

## License

Apache-2.0. Free and open to everyone. The terms are in [LICENSE](LICENSE).
