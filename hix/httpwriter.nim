proc flush(w: ptr Writer) =
  if not w.preflusher.isNil:
    w.preflusher()

  let fd = w.conn.socket.getFd.cint
  let vecs = cast[ptr TIOVec](addr(w.vecs.values[0]))

  if w.vecs.len > 0:
    discard writev(fd, vecs, w.vecs.len.cint)

  w.vecs.len = 0
  w.buffered = 0
  w.bufferedBody = 0
  w.conn.outbuffer.clear

  if not w.postflusher.isNil:
    w.postflusher()

proc addWeak(w: ptr Writer, data: IOVec) =
  w.buffered += data.len
  w.vecs.add(data)
  if w.vecs.len == w.vecs.N-2:
    w.flush

proc addHeap(w: ptr Writer, data: IOVec) =
  # first check if the content in data is substantial enough to flush directly.
  let tosend = w.buffered + data.len
  if tosend > 1.kB:
    # 1kB is fair enough to send without buffering
    w.addWeak(data)
    w.flush
    # NOTE: this is safe because the string is still alive after we flush.
    return

  # copy it to the outbuffer so it's alive when we want to flush.
  let vec = w.conn.outbuffer.add(data)
  w.addWeak(vec)

template add(w: ptr Writer, data: string) =
  when compiles((const foo = data)):
    addWeak(w, toIOVec(data))
  else:
    addHeap(w, toIOVec(data))

proc startHead*(req: var Request, status: int = 200): ptr Writer =
  doAssert(req.isComplete)

  result = addr(req.writer)
  result.conn = addr(req)

  result.add("HTTP/1.1 ")
  result.addWeak(StatusCodes[status].toIOVec)
  if req.closeConnection:
    result.add("\r\nConnection: close")

proc setStatus*(w: ptr Writer, code: int) =
  # TODO: verify that we haven't flushed the headers yet
  w.vecs[1] = StatusCodes[code].toIOVec

proc setHeader*(
  w: ptr Writer,
  name: static[string]|string, value: static[string]|string
) =
  w.add("\r\n" & name & ": " & value)

proc chunkStartVec(w: ptr Writer, n: int): IOVec =
  result = nextIOVec(w.conn.outbuffer, w.conn.outbuffer.N)
  assert(result.len >= 8)

  result.len = 6
  result.toHex(n)
  result.len = 8
  result.buf[6] = "\r\n"[0]
  result.buf[7] = "\r\n"[1]
  didWrite(w.conn.outbuffer, result.len)

proc contentLengthVec(w: ptr Writer, n: int): IOVec =
  # support up to 1TB of sent data.
  result = w.conn.outbuffer.add("\r\nContent-Length: TGGGMMMKKKBBB\r\n\r\n".toIOVec)
  result[18..30].toDec(n)

proc startBody*(w: ptr Writer): BodyWriter =
  result = w.BodyWriter

  # Add `chunked`-header
  w.add("\r\nTransfer-Encoding: chunked\r\n\r\n")
  # Add potential chunk start
  w.add("")

  var pos = w.vecs.len-1

  proc preparebody() =
    if w.bufferedBody == 0 and w.finished:
      w.vecs[pos] = "0\r\n\r\n".toIOVec

    if w.bufferedBody > 0:
      # fill in the empty vec with a chunk-start
      w.vecs[pos] = w.chunkStartVec(w.bufferedBody)
      if w.finished:
        # complete the chunk, then finish the response.
        w.vecs.add("\r\n0\r\n\r\n".toIOVec)
      else:
        # complete the chunk.
        w.vecs.add("\r\n".toIOVec)

  proc firstpreflusher() =
    if w.finished:
      # The body is complete before we flushed anything. replace the TE:chunked
      # with a Content-Length.
      w.vecs[pos-1] = w.contentLengthVec(w.bufferedBody)
    else:
      preparebody()
      w.preflusher = preparebody

  w.preflusher = firstpreflusher

  w.postflusher = proc() =
    if not w.finished:
      # Prepare another empty vec where we can fill in the chunk-start.
      w.vecs.add("".toIOVec)
      pos = w.vecs.len-1

proc startExact*(w: ptr Writer, len: int): BodyWriter =
  result = w.BodyWriter
  w.addWeak(w.contentLengthVec(len))

template add*(body: BodyWriter, data: string) =
  let w = cast[ptr Writer](body)
  w.bufferedBody += data.len
  w.add(data)

proc add*(body: BodyWriter, data: IOVec) =
  let w = cast[ptr Writer](body)
  w.bufferedBody += data.len
  w.addHeap(data)

# unwrap body.add(foo, bar) to body.add(foo); body.add(bar)
import macros
macro add*(body: BodyWriter, data: varargs[expr]): stmt =
  result = newNimNode(nnkStmtList)
  for i in 0 .. <data.len:
    result.add(newCall("add", body, data[i]))

proc flush*(body: BodyWriter) =
  let w = cast[ptr Writer](body)
  w.flush

proc finish(body: BodyWriter) =
  let w = cast[ptr Writer](body)
  w.finished = true
  w.flush

