# What this package does not port

This package reads and writes MessagePack bytes. The integer widths match rmp's `write_sint` and `write_uint`. A map keeps the order of the pairs you append, which is the order `rmp_serde::to_vec_named` uses for struct fields.

It does not port serde. There is no `Serialize` or `Deserialize`, no `to_vec`, and no `from_slice` for an arbitrary Goose struct. You write a named map by calling `encode::map` with the pair count, then writing each string key and each value yourself.

It does not port timestamps. The MessagePack timestamp extension is ext type -1 with a 4, 8, or 12 byte payload. Those bytes stay an `Ext` value. Nothing here turns them into a time.

It does not port derive macros. rmp-serde generates implementations with `Serialize` and `Deserialize` derives. Goose has no proc macros, and this package does not add a substitute.

rmp's fixed-width writers, such as `write_u8` and `write_i16`, always emit one marker. Those are absent. `encode::int` and `encode::uint` always pick the shortest form.
