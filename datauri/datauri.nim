import os, base64, strutils, parseopt2

var
  file = ""
  version = "0.1"
  usage = "  DataUri v" & version & " - Image-to-data-uri converter" & """

  (c) 2013-2014 Fabio Cevasco

  Usage:
    datauri image_file

  Arguments:
    image_file         the file to convert.
"""

proc encode_image(file, format): string =
  let contents = file.readFile
  let enc_contents = contents.encode(contents.len*3) 
  return "data:image/$format;base64,$enc_contents" % ["format", format, "enc_contents", enc_contents]

for kind, key, value in getopt():
  if kind == cmdArgument:
    file = key

let fileparts = file.splitFile
let format = fileparts.ext.replace(".", "")
let data = encode_image(file, format)

let output_file = fileparts.dir/fileparts.name & ".txt"

output_file.writefile(data)
