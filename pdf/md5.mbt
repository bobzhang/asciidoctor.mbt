///|
// MD5 (RFC 1321), for the index's term anchors: asciidoctor-pdf names the
// destination of an index entry `__indextermdef-` and the MD5 hex digest of
// the term.

///|
let md5_shifts : Array[Int] = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9,
  14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
]

///|
/// `floor(abs(sin(i + 1)) * 2^32)`
let md5_constants : Array[UInt] = Array::makei(64, i => {
  let v = (@math.sin((i + 1).to_double()).abs() * 4294967296.0).floor()
  v.to_uint64().to_uint()
})

///|
fn md5_rotl(x : UInt, n : Int) -> UInt {
  (x << n) | (x >> (32 - n))
}

///|
/// The MD5 digest of `data` as 32 lowercase hex digits.
fn md5_hex(data : Bytes) -> String {
  let len = data.length()
  // message, 0x80, zero padding to 56 mod 64, then the bit length (LE)
  let padded_len = (len + 8) / 64 * 64 + 64
  let msg = FixedArray::make(padded_len, b'\x00')
  for i in 0..<len {
    msg[i] = data[i]
  }
  msg[len] = b'\x80'
  let bits = len.to_uint64() * 8UL
  for i in 0..<8 {
    msg[padded_len - 8 + i] = (bits >> (8 * i)).to_byte()
  }
  let mut a0 : UInt = 0x67452301U
  let mut b0 : UInt = 0xefcdab89U
  let mut c0 : UInt = 0x98badcfeU
  let mut d0 : UInt = 0x10325476U
  let m = FixedArray::make(16, 0U)
  for chunk = 0; chunk < padded_len; chunk = chunk + 64 {
    for j in 0..<16 {
      let p = chunk + j * 4
      m[j] = msg[p].to_uint() |
        (msg[p + 1].to_uint() << 8) |
        (msg[p + 2].to_uint() << 16) |
        (msg[p + 3].to_uint() << 24)
    }
    let mut a = a0
    let mut b = b0
    let mut c = c0
    let mut d = d0
    for i in 0..<64 {
      let (f, g) = if i < 16 {
        ((b & c) | (b.lnot() & d), i)
      } else if i < 32 {
        ((d & b) | (d.lnot() & c), (5 * i + 1) % 16)
      } else if i < 48 {
        (b ^ c ^ d, (3 * i + 5) % 16)
      } else {
        (c ^ (b | d.lnot()), 7 * i % 16)
      }
      let f2 = f + a + md5_constants[i] + m[g]
      a = d
      d = c
      c = b
      b = b + md5_rotl(f2, md5_shifts[i])
    }
    a0 = a0 + a
    b0 = b0 + b
    c0 = c0 + c
    d0 = d0 + d
  }
  let sb = StringBuilder()
  for word in [a0, b0, c0, d0] {
    for k in 0..<4 {
      let byte = ((word >> (8 * k)) & 0xFFU).reinterpret_as_int()
      sb.write_char("0123456789abcdef"[byte >> 4].unsafe_to_char())
      sb.write_char("0123456789abcdef"[byte & 15].unsafe_to_char())
    }
  }
  sb.to_string()
}

///|
test "md5 digests" {
  inspect(md5_hex(b""), content="d41d8cd98f00b204e9800998ecf8427e")
  inspect(
    md5_hex(b"The quick brown fox jumps over the lazy dog"),
    content="9e107d9d372bb6826bd81d3542a419d6",
  )
  inspect(
    md5_hex(
      @utf8.encode(
        "a string of exactly sixty-four bytes, to pad a whole block....",
      ),
    ),
    content="ddc5f921ce15fea94fa53489b6fca8ef",
  )
}
