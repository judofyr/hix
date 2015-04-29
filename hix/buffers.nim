import hix/iovec

type
  MemBuffer*[N: static[int]] = object
    data: array[0 .. N-1, char]
    a*, b*: int

{.push inline.}
proc clear*(buf: var MemBuffer) =
  buf.a = 0
  buf.b = 0

proc didWrite*(buf: var MemBuffer, bytes: int) =
  buf.b += bytes

proc didConsume*(buf: var MemBuffer, bytes: int) =
  buf.a += bytes

proc left*[N: static[int]](buf: var MemBuffer[N]): int =
  N - buf.b

proc set*(buf: var MemBuffer, other: IOVec) =
  buf.a = 0
  buf.b = other.len
  copyMem(addr(buf.data[0]), other.buf, other.len)

proc add*(buf: var MemBuffer, other: IOVec): IOVec =
  if other.len > buf.left:
    # not enough space
    result.len = -1
    return

  result.buf = cstring(addr(buf.data[buf.b]))
  result.len = other.len

  copyMem(result.buf, other.buf, other.len)
  buf.b += result.len

proc len*(buf: var MemBuffer): int =
  buf.b - buf.a

proc currIOVec*(buf: var MemBuffer): IOVec =
  result.buf = cstring(addr(buf.data[buf.a]))
  result.len = buf.len

proc nextIOVec*[N](buf: var MemBuffer[N], total: int): IOVec =
  result.buf = cstring(addr(buf.data[buf.b]))
  result.len = (total - buf.a) - buf.b

{.pop.}
