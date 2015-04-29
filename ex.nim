import hix/http
import hix/iovec
import net, os
import strutils

let s = newSocket(buffered = false)
s.setSockOpt(OptReuseAddr, true)
s.bindAddr(7890.Port)
s.listen

proc app(req: var Request): BodyWriter =
  let head = req.startHead
  head.setHeader("Content-Type", "text/html;charset=utf-8")

  let body = head.startBody
  body.add("<!doctype>")
  body.add(repeatChar(4096, ' ')) # add padding to force the browser
  body.add("<body><pre>")
  body.add(req.headers["User-Agent"], "\n")
  body.add("\n")
  for i in 1 .. 10:
    body.add("Hello world: ")
    body.add($i)
    body.add("\n")
    body.flush
  return body

proc loop(s: Socket) {.gcsafe.} =
  s.startServer(app)

#s.loop

let numThreads = 8
var thr: seq[TThread[Socket]]
newSeq(thr, numThreads)
for i in 0 .. <numThreads:
  createThread(thr[i], loop, s)
joinThreads(thr)

