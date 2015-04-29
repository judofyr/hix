{.compile:"deps/picohttpparser/picohttpparser.c"}

import hix/iovec

type
  PhrHeader* = object
    name*, value*: IOVec

proc phr_parse_request*(
  data: IOVec,
  meth, path: IOVecWriter,
  minor: var cint,
  headers: ptr PhrHeader, num_headers: var int,
  last_len: int): cint {.importc.}

proc phr_parse_response*(
  data: IOVec,
  minor: var cint,
  status: var cint, msg: IOVecWriter,
  headers: ptr PhrHeader, num_headers: var int,
  last_len: int): cint {.importc.}

proc phr_parse_headers*(
  data: IOVec,
  headers: ptr PhrHeader, num_headers: var int,
  last_len: int): cint {.importc.}

