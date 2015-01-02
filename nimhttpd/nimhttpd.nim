import asynchttpserver, asyncdispatch, asyncnet, os, strutils, mimetypes, times, parseopt2
from strtabs import StringTableRef, newStringTable
from htmlgen as hg import nil

const style = "style.css".slurp

let appname = "NimHTTPd Web Server"
let appversion = "1.0"
let usage = appname & " v" & appversion & " - Tiny Web Server for Static Sites" & """

  (c) 2014-2015 Fabio Cevasco

  Usage:
    nimhttpd [-p:port] [directory]

  Arguments:
    directory      The directory to serve (default: current directory).
    port           Listen to port (default: 1337).
"""


type 
  NimHttpResponse* = tuple[
    code: HttpCode,
    content: string,
    headers: StringTableRef]
  NimHttpSettings* = object
    directory*: string
    mimes*: MimeDb
    port*: Port
    address*: string
    appname: string
    appversion*: string

proc h_page(settings:NimHttpSettings, content: string, title=""): string =
  var res = "<!DOCTYPE html>\n"
  var footer = "<div id=\"footer\">" & settings.appname & " v" & settings.appversion & "</div>"
  res = res & "<html>\n" & 
    hg.head(hg.title(title), "<style type=\"text/css\">"&style&"</style>", "<meta charset=\"UTF-8\">") & 
    hg.body(hg.h1(title), content, footer) & 
    "</html>"
  return res

proc relativePath(path, cwd): string =
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

proc relativeParent(path, cwd): string =
  var relparent = path.parentDir.relativePath(cwd)
  if relparent == "":
    return "/"
  else: 
    return relparent

proc sendNotFound(settings, path): NimHttpResponse = 
  var content = hg.p("The page you requested cannot be found.");
  return (code: Http404, content: h_page(settings, content, $Http404), headers: newStringTable())

proc sendNotImplemented(settings, path): NimHttpResponse =
  var content = hg.p("This server does not support the functionality required to fulfill the request.");
  return (code: Http500, content: h_page(settings, content, $Http500), headers: newStringTable())

proc sendStaticFile(settings, path): NimHttpResponse =
  let mimes = settings.mimes
  let mimetype = mimes.getMimetype(path.splitFile.ext[1 .. -1])
  var file = path.readFile
  return (code: Http200, content: file, headers: {"Content-type": mimetype}.newStringTable)

proc sendDirContents(settings, path): NimHttpResponse = 
  let cwd = settings.directory
  var res: NimHttpResponse
  var files = newSeq[string](0)
  if path != cwd and path != cwd&"/" and path != cwd&"\\":
    files.add hg.li(class="i-back entypo", hg.a(href=path.relativeParent(cwd), "..")) 
  var title = "Index of " & path.relativePath(cwd)
  for i in walkDir(path):
    let name = i.path.extractFilename
    let relpath = i.path.relativePath(cwd)
    if name == "index.html" or name == "index.htm":
      return sendStaticFile(settings, i.path)
    if i.path.existsDir:
      files.add hg.li(class="i-folder entypo", hg.a(href=relpath, name)) 
    else:
      files.add hg.li(class="i-file entypo", hg.a(href=relpath, name)) 
  res = (code: Http200, content: h_page(settings, hg.ul(files.join("\n")), title), headers: newStringTable())
  return res

proc printReqInfo(req) =
  echo getLocalTime(getTime()), " - ", req.hostname, " ", req.reqMethod, " ", req.url.path

proc handleCtrlC() {.noconv.} =
  echo "\nExiting..."
  quit()

setControlCHook(handleCtrlC)

proc serve*(settings: NimHttpSettings) =
  var server = newAsyncHttpServer()
  proc handleHttpRequest(req: Request): Future[void] {.async.} =
    printReqInfo(req)
    let path = settings.directory/req.url.path.replace("%20", " ")
    var res: NimHttpResponse 
    if req.reqMethod != "GET":
      res = sendNotImplemented(settings, path)
    elif path.existsDir:
      res = sendDirContents(settings, path)
    elif path.existsFile:
      res = sendStaticFile(settings, path)
    else:
      res = sendNotFound(settings, path)
    await req.respond(res.code, res.content, res.headers)
  echo settings.appname, " v", settings.appversion, " started on port ", int(settings.port), "." 
  echo "Serving directory ", settings.directory
  asyncCheck server.serve(settings.port, handleHttpRequest, settings.address)

when isMainModule:

  var port = Port(1337)
  var address = ""
  var www = getCurrentDir()
  
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
          port = Port(val.parseInt)
        except:
          if val == "":
            echo "Port not set."
            quit(2)
          else:
            echo "Error: Invalid port: '", val, "'"
            echo "Running on default port instead."
      else:
        discard
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
  
  var settings: NimHttpSettings
  settings.directory = www
  settings.mimes = newMimeTypes()
  settings.address = address
  settings.appname = appname
  settings.appversion = appversion
  settings.port = port

  serve(settings)
  runForever()
