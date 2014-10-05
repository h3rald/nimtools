import asynchttpserver2, asyncdispatch, asyncnet, os, strutils, mimetypes, times
from strtabs import PStringTable, newStringTable
from htmlgen as hg import nil

const style = "style.css".slurp
const appname = "NimHttpd"
const appversion = "1.0"


var port = TPort(8888)
var address = ""
var cwd = getCurrentDir()
var server = newAsyncHttpServer()
var mimes = newMimeTypes()

type TNimHttpResponse* = tuple[
  code: THttpCode,
  content: string,
  headers: PStringTable]

proc h_page(content: string, title=""): string =
  var res = "<!DOCTYPE html>\n"
  var footer = "<div id=\"footer\">" & appname & " Web Server v" & appversion & "</div>"
  res = res & "<html>\n" & 
    hg.head(hg.title(title), "<style type=\"text/css\">"&style&"</style>", "<meta charset=\"UTF-8\">") & 
    hg.body(hg.h1(title), content, footer) & 
    "</html>"
  return res

proc sendDirContents(path): TNimHttpResponse = 
  var res: TNimHttpResponse
  var files = newSeq[string](0)
  files.add hg.li(hg.a(href=".", "."))  
  files.add hg.li(hg.a(href="..", "..")) 
  var title = "Index of " & path.replace(cwd, "")
  for i in walkDir(path):
    let name = i.path.extractFilename
    let relpath = i.path.replace(cwd, "")
    files.add hg.li(hg.a(href=relpath, name)) 
  res = (code: Http200, content: h_page(hg.ul(files.join("\n")), title), headers: newStringTable())
  return res

proc sendNotFound(path): TNimHttpResponse = 
  var content = hg.p("The page you requested cannot be found.");
  return (code: Http404, content: h_page(content, $Http404), headers: newStringTable())

proc sendNotImplemented(path): TNimHttpResponse =
  var content = hg.p("This server does not support the functionality required to fulfill the request.");
  return (code: Http501, content: h_page(content, $Http501), headers: newStringTable())

proc sendStaticFile(path): TNimHttpResponse =
  let mimetype = mimes.getMimetype(path.splitFile.ext[1 .. -1])
  var file = path.readFile
  return (code: Http200, content: file, headers: {"Content-type": mimetype}.newStringTable)

proc printReqInfo(req) =
  echo getLocalTime(getTime()), " - ", req.hostname, " ", req.reqMethod, "\t", "/", req.url.path

proc handleHttpRequest(req: TRequest): PFuture[void]=
  printReqInfo(req)
  let path = cwd/req.url.path
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

server.serve(port, handleHttpRequest, address)
runForever()
