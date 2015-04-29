import phr
import hix/iovec, hix/buffers
import net
import os, posix
import strutils

include ./httputils

proc kB(n: int): int = n * 1024

const HeaderSize = 4.kB
const EntitySize = 100.kB # this should be enough for anyone, right?

type
  StaticSeq[T;N: static[int]] = object
    len: int
    values: array[N, T]

proc `[]`(s: StaticSeq, pos: int): auto =
  return s.values[pos]

proc `[]=`(s: var StaticSeq, pos: int, data: auto) =
  s.values[pos] = data

proc add(s: var StaticSeq, val: auto) =
  s[s.len] = val
  s.len.inc

type
  # 128 headers should be enough for anyone
  Headers = StaticSeq[PhrHeader, 128]

  Connection = object of RootObj
    socket*: Socket

    headers*: Headers
    minor*: int32

    entityLength: int
    entity: IOVec
    isComplete: bool
    # has the entity been read

    closeConnection: bool
    # should we close the connection when we're done?

    writer: Writer
    inbuffer: MemBuffer[HeaderSize + EntitySize]
    outbuffer: MemBuffer[HeaderSize]

  Request* = object of Connection
    host*, meth*, path*: IOVec

  RequestHandler* = proc(req: var Request): BodyWriter

  ConnectionStatus* = enum
    Partial, Close, KeepAlive

  HTTPError* = object of Exception
  ServerError* = object of HTTPError
  ClientError* = object of HTTPError

  Writer = object
    conn: ptr Connection
    vecs: StaticSeq[IOVec, 512]
    buffered: int # number of bytes buffered for sending
    bufferedBody: int # number of bytes of the body buffered
    finished: bool # whether the sent body is done
    preflusher: proc() {.closure, raises:[], gcsafe.}
    postflusher: proc() {.closure, raises:[], gcsafe.}

  BodyWriter* = distinct ptr Writer

proc recv(s: Socket, data: IOVec): int {.inline.} =
  s.recv(data.buf, data.len)

proc didError(conn: var Connection, msg: string) {.raises:[HTTPError].} =
  raise newException(ClientError, msg)

proc clear(conn: var Connection) =
  # Copy everything that was left to the beginning.
  conn.inbuffer.set(conn.inbuffer.currIOVec)
  conn.outbuffer.clear

  conn.writer.finished = false
  conn.writer.buffered = 0
  conn.writer.bufferedBody = 0
  conn.writer.preflusher = nil
  conn.writer.postflusher = nil

proc finish(body: BodyWriter) {.raises:[], gcsafe.}

proc find(headers: Headers, name: string): IOVec =
  for i in 0 .. <headers.len:
    if headers[i].name == name:
      return headers[i].value

template `[]`*(headers: Headers, name: string): IOVec =
  when compiles((const lcname = name.toLower)):
    const lcname = name.toLower
    headers.find(lcname)
  else:
    headers.find(name.toLower)

proc processHeaders(req: var Request) {.raises:[HTTPError], gcsafe.}
proc processEntity(req: var Request) {.raises:[HTTPError], gcsafe.}

proc startServer*(server: Socket, handler: RequestHandler) =
  let req = new(Request)
  req.socket = newSocket(buffered = false)

  while true:
    server.accept(req.socket)

    try:
      while true:
        # for each connection

        req[].clear

        req[].processHeaders
        req[].processEntity

        var body = handler(req[])
        body.finish

        if req.closeConnection:
          req.socket.close
          break
    except HTTPError:
      req.socket.close
      discard

proc readEntity*(req: var Request): IOVec {.raises:[HTTPError].}

include ./httprequest
include ./httpwriter

