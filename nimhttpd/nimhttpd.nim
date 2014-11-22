import asynchttpserver, asyncdispatch, asyncnet, os, strutils, mimetypes, times, parseopt2
from strtabs import PStringTable, newStringTable
from htmlgen as hg import nil

const style = "style.css".slurp
const appname = "NimHTTPd"
const appversion = "1.0"

let usage = appname & " v" & appversion & " - Tiny Web Server for Static Sites" & """

  (c) 2014 Fabio Cevasco

  Usage:
    nimhttpd [-p:port] [directory]

  Arguments:
    directory      The directory to serve (default: current directory).
    port           Listen to port (default: 1337).
"""

var port = TPort(1337)
var address = ""
var www = getCurrentDir()
let server = newAsyncHttpServer()
let mimes = newMimeTypes()

type TNimHttpResponse* = tuple[
  code: THttpCode,
  content: string,
  headers: PStringTable]

for kind, key, val in getopt():
  case kind
  of cmdLongOption, cmdShortOption:
    case key
    of "help", "h":
      echo usage
      quit(0)
    of "version", "v":
      echo appversion
      quit(0)
    of "port", "p":
      try:
        port = TPort(val.parseInt)
      except:
        if val == "":
          echo "Port not set."
          quit(2)
        else:
          echo "Error: Invalid port: '", val, "'"
          echo "Running on default port instead."
  of cmdArgument:
    var dir: string
    if key.isAbsolute:
      dir = key
    else:
      dir = www/key
    if dir.existsDir:
      www = expandFilename dir
    else:
      echo "Error: Directory '"&dir&"' does not exist."
      quit(1)
  else: 
    discard

let cwd = www

proc h_page(content: string, title=""): string =
  var res = "<!DOCTYPE html>\n"
  var footer = "<div id=\"footer\">" & appname & " Web Server v" & appversion & "</div>"
  res = res & "<html>\n" & 
    hg.head(hg.title(title), "<style type=\"text/css\">"&style&"</style>", "<meta charset=\"UTF-8\">") & 
    hg.body(hg.h1(title), content, footer) & 
    "</html>"
  return res

proc relativePath(path): string =
  var path2 = path
  if cwd == "/":
    return path
  else:
    path2.delete(0, cwd.len)
  var relpath = path2.replace("\\", "/")
  if (not relpath.endsWith("/")) and (not path.existsFile):
    relpath = relpath&"/"
  if not relpath.startsWith("/"):
    relpath = "/"&relpath
  return relpath

proc relativeParent(path): string =
  var relparent = path.parentDir.relativePath
  if relparent == "":
    return "/"
  else: 
    return relparent

proc sendNotFound(path): TNimHttpResponse = 
  var content = hg.p("The page you requested cannot be found.");
  return (code: Http404, content: h_page(content, $Http404), headers: newStringTable())

proc sendNotImplemented(path): TNimHttpResponse =
  var content = hg.p("This server does not support the functionality required to fulfill the request.");
  return (code: Http500, content: h_page(content, $Http500), headers: newStringTable())

proc sendStaticFile(path): TNimHttpResponse =
  let mimetype = mimes.getMimetype(path.splitFile.ext[1 .. -1])
  var file = path.readFile
  return (code: Http200, content: file, headers: {"Content-type": mimetype}.newStringTable)

proc sendDirContents(path): TNimHttpResponse = 
  var res: TNimHttpResponse
  var files = newSeq[string](0)
  if path != cwd and path != cwd&"/" and path != cwd&"\\":
    files.add hg.li(class="i-back entypo", hg.a(href=path.relativeParent(), "..")) 
  var title = "Index of " & path.relativePath()
  for i in walkDir(path):
    let name = i.path.extractFilename
    let relpath = i.path.relativePath()
    if name == "index.html" or name == "index.htm":
      return sendStaticFile(i.path)
    if i.path.existsDir:
      files.add hg.li(class="i-folder entypo", hg.a(href=relpath, name)) 
    else:
      files.add hg.li(class="i-file entypo", hg.a(href=relpath, name)) 
  res = (code: Http200, content: h_page(hg.ul(files.join("\n")), title), headers: newStringTable())
  return res

echo appname , " Web Server v", appversion, " started on port ", int(port), "." 
echo "Serving directory ", cwd

proc printReqInfo(req) =
  echo getLocalTime(getTime()), " - ", req.hostname, " ", req.reqMethod, " ", req.url.path

proc handleHttpRequest(req: TRequest): PFuture[void] {.closure, gcsafe.}=
  printReqInfo(req)
  let path = cwd/req.url.path.replace("%20", " ")
  var res: TNimHttpResponse 
  if req.reqMethod != "GET":
    res = sendNotImplemented(path)
  elif path.existsDir:
    res = sendDirContents(path)
  elif path.existsFile:
    res = sendStaticFile(path)
  else:
    res = sendNotFound(path)
  return respond(req, res.code, res.content, res.headers)

proc handleCtrlC() {.noconv.} =
  echo "\nExiting..."
  server.close()
  quit()

setControlCHook(handleCtrlC)

######

while true:
  discard server.serve(port, handleHttpRequest, address)
  runForever()
