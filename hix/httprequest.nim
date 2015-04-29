proc sendError(req: var Request, status: int, msg: string = nil) {.raises:[HTTPError].} =
  let statusText = StatusCodes[status]

  var msg = msg
  if msg.isNil:
    msg = statusText

  let res = "HTTP/1.1 " & statusText & "\r\n" &
    "Connection: close\r\n" &
    "Content-Length: " & $(msg.len+1) & "\r\n\r\n" &
    msg & "\n"

  discard req.socket.trySend(res)
  raise newException(HTTPError, msg)

proc processHeaders(req: var Request) =
  # we should not ask for more data if there was
  # something there already (pipelining).
  var shouldPull = (req.inbuffer.len == 0)

  while true:
    if shouldPull:
      let next = req.inbuffer.nextIOVec(HeaderSize)
      let nread = req.socket.recv(next)
      if nread <= 0:
        req.didError("failed to read request")
      req.inbuffer.didWrite(nread)

    shouldPull = true

    var num_headers = req.headers.N

    # Let's parse it
    let nparsed = phr_parse_request(
      req.inbuffer.currIOVec,
      req.meth.toWriter,
      req.path.toWriter,
      req.minor,
      addr(req.headers.values[0]), num_headers,
      0
    )

    case nparsed
    of -1:
      # parse error
      req.sendError(400)
    of -2:
      # incomplete header
      continue
    else:
      req.headers.len = num_headers
      req.inbuffer.didConsume(nparsed)
      break

  # Done fetching the headers. Now process them.

  # Default to closing the connection on HTTP/1.0
  req.closeConnection = (req.minor == 0)

  for i in 0 .. <req.headers.len:
    var header = req.headers[i]
    let htype = header.name.normalizeHeader

    case htype
    of HeaderName.Other:
      discard

    of HeaderName.Host:
      req.host = header.value

    of HeaderName.ContentLength:
      let cl = header.value.toInt
      if cl < 0:
        req.sendError(400, "invalid content-length")
      req.entityLength = cl
      req.isComplete = false

    of HeaderName.TransferEncoding:
      toLower(header.value)
      if header.value != "chunked":
        req.sendError(400, "unknown transfer-encoding")
      req.entityLength = -1
      req.isComplete = false

    of HeaderName.Expect:
      toLower(header.value)
      if header.value == "100-continue":
        let sent = req.socket.trySend("HTTP/1.1 100 Continue\r\n\r\n")
        if not sent:
          req.didError("could not send 100 Continue")

    of HeaderName.Connection:
      toLower(header.value)
      if header.value != "keep-alive":
        req.closeConnection = true

    of HeaderName.Upgrade:
      discard

proc processEntity(req: var Request) =
  if req.entityLength < 0:
    # chunked encoding. don't fetch anything.
    return

  if req.entityLength > EntitySize:
    # huge body. don't attempt to fetch it all.
    return

  # check how much we've already read
  var vec = req.inbuffer.currIOVec
  if vec.len > req.entityLength:
    # we got more data on the wire than needed.
    # this probably means that a request has been
    # pipelined. clamp it.
    vec.len = req.entityLength

  # now we store this IOVec
  req.entity = vec

  while req.entity.len < req.entityLength:
    # read directly into the inbuffer. only as much as we need.
    let nread = req.socket.recv(req.inbuffer.nextIOVec(req.inbuffer.N))
    if nread <= 0:
      req.didError("failed to read entity")
    req.inbuffer.didWrite(nread)
    req.entity.len += nread

  # mark it complete
  req.isComplete = true

  # consume it from the inbuffer
  req.inbuffer.didConsume(req.entity.len)

proc readEntity*(req: var Request): IOVec =
  if req.entityLength < 0:
    # this only handles requests with Content-Length
    req.sendError(411)

  if req.entityLength > EntitySize:
    # doesn't handle huge requests either
    req.sendError(413)

  return req.entity

# TODO: read chunks

