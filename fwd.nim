import os, times, parseopt2

var
  src = ""
  dest = "" 
  n = 0
  version = "0.1"
  usage = "  FWD v" & version & " - Directory Monitoring and File Forwarding Utility" & """

  (c) 2013-2014 Fabio Cevasco

  Usage:
    fwd source_directory destination_directory

  Arguments:
    source_directory          the directory to be monitored.
    destination_directory     the directory where files will be moved to.
"""

proc scan(callback: proc(f: string, name: string)) =
  for path in walkDirRec(src, filter = {pcFile, pcDir}):
    let fileparts = path.splitFile
    let filename = fileparts.name & fileparts.ext
    if (filename != "Thumbs.db"):
      stdout.write(getTime(), ": ", filename, " ")
      callback(path, filename)

proc move(f: string, name: string) =
  try:
    let dest_f = dest/name
    stdout.write(".")
    if dest_f.existsFile:
      dest_f.setFilePermissions({fpUserWrite})
      dest_f.removeFile
    stdout.write(".")
    f.copyFile(dest_f)
    stdout.write(".")
    f.setFilePermissions({fpUserWrite})
    f.removeFile
    stdout.write(" -> OK!\n")
  except:
    stderr.writeln("\n    Warning: " & getCurrentExceptionMsg())

for kind, key, value in getopt():
  if kind == cmdArgument:
    case n
    of 0:
      src = key
      if src.existsDir == false:
        quit("Source directory '" & src & "' does not exist.")
    of 1:
      dest = key
      if dest.existsDir == false:
        quit("Destination directory '" & dest & "' does not exist.")
    else: nil
    n.inc

if src == "" and dest == "":
  quit(usage)
if dest == "":
  quit("Destination directory not specified.")


echo(getTime(), ": FWD monitor started.")
echo("")
echo("        Source: ", src)
echo("   Destination: ", dest)
echo("")
echo("")
while(true):
  sleep(2000)
  scan(move)
