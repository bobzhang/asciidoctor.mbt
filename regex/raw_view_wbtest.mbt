///|
test "unit search retains offsets inside surrogate pairs" {
  assert_eq(find_unit("😀z", 1, 'z'.to_int()), 2)
  let text = "😀z"
  let half = raw_view(text, 1, 2)
  assert_eq(half.length(), 1)
  assert_eq(half.unsafe_get(0), text.unsafe_get(1))
}
