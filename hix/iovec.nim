type
  IOVec* = object
    buf*: cstring
    len*: int

  IOVecWriter* = object
    buf: ptr cstring
    len: ptr int

proc `$`*(vec: IOVec): string {.inline.} =
  result = newString(vec.len)
  for i in 0 .. <vec.len:
    result[i] = vec.buf[i]

proc `==`*(vec: IOVec, other: string): bool {.inline.} =
  if vec.len != other.len:
    return false
  for i in 0 .. <vec.len:
    if vec.buf[i] != other[i]:
      return false
  return true

proc `[]`*(vec: IOVec, slice: Slice[int]): IOVec =
  result.buf = cast[cstring](cast[int](vec.buf) + slice.a)
  result.len = slice.b - slice.a + 1

proc toInt*(vec: IOVec): int =
  var pos = vec.len

  if pos == 0:
    return -1

  var multiplier = 1

  while pos > 0:
    pos.dec
    let ch = vec.buf[pos]

    if not (ch in '0' .. '9'):
      return -1

    result += (ch.int8 - '0'.int8) * multiplier
    multiplier *= 10
    # TODO: handle overflow

proc toHex*(vec: IOVec, n: int) =
  const Chars = "0123456789abcdef"
  var shift: int
  var buf = cast[ptr array[32, char]](vec.buf)
  for j in countdown(vec.len-1, 0):
    buf[j] = Chars[(n shr shift) and 0xF]
    shift += 4

proc toDec*(vec: IOVec, n: int) =
  const Chars = "0123456789abcdef"
  var buf = cast[ptr array[32, char]](vec.buf)
  var n = n
  for j in countdown(vec.len-1, 0):
    buf[j] = Chars[n mod 10]
    n = n div 10

proc toIOVec*(str: string): IOVec {.inline.} =
  result.buf = cstring(str)
  result.len = len(str)

proc toWriter*(vec: var IOVec): IOVecWriter {.inline.} =
  result.buf = addr(vec.buf)
  result.len = addr(vec.len)

