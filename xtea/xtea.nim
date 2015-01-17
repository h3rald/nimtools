import parseopt2, os, streams, base64, strutils

type
  TOperation = enum encryptOp, decryptOp


const 
  version* = "1.0"
  rounds* = 32   
  delta* = 0x9E3779B9
  d_sum* = delta * rounds
  usage* = "  XTEA v" & version & " - XTEA Encryption/Decryption Utility" & """

  (c) 2014-2015 Fabio Cevasco

  Usage:
    xtea -p:<password> [ -e | -d] <stdin>

  Options:
    -e, --encrypt (default)     Encrypt text.
    -d, --decrypt               Decrypt text.
    -h, --help                  Display this help text (default if no password and 
                                no text are specified)
    -p, --password              The password to use to encrypt/decrypt text.
    -v, --version               Display the program version.
"""

proc bytes2string(input: seq[int8]): string =
  var output = ""
  for i in input:
    output = output & i.uint8.chr
  return output

proc string2bytes(input: string): seq[int8] =
  var output:seq[int8]
  output.newSeq(0)
  for i in input:
    output.add cast[int8](i.ord)
  return output

# Packs a sequence of 8 bytes
proc pack(input: seq[int8]): array[0..1, int32] =
  var v: array[0..1, int32]
  v[0] =  (input[0].int32 shl 24               ) or
          (input[1].int32 shl 16 and 0x00ff0000) or
          (input[2].int32 shl  8 and 0x0000ff00) or
          (input[3].int32        and 0x000000ff) 
  v[1] =  (input[4].int32 shl 24               ) or
          (input[5].int32 shl 16 and 0x00ff0000) or
          (input[6].int32 shl  8 and 0x0000ff00) or
          (input[7].int32        and 0x000000ff)
  return v

proc unpack(v: array[0..1, int32]): seq[int8] =
  var offset = 0
  var output: seq[int8]
  output.newSeq(8)
  output[offset  ] = ((v[0]               ) shr 24).toU8
  output[offset+1] = ((v[0] and 0x00ff0000) shr 16).toU8
  output[offset+2] = ((v[0] and 0x0000ff00) shr  8).toU8
  output[offset+3] = ((v[0] and 0x000000ff)       ).toU8
  output[offset+4] = ((v[1]               ) shr 24).toU8
  output[offset+5] = ((v[1] and 0x00ff0000) shr 16).toU8
  output[offset+6] = ((v[1] and 0x0000ff00) shr  8).toU8
  output[offset+7] = ((v[1] and 0x000000ff)       ).toU8
  #echo output.repr
  return output

# Generate four int subkeys from the first 16 bytes of the password
proc generate_subkeys(password: string): seq[int32] =
  var key = string2bytes password
  var subkeys: seq[int32]
  subkeys.newSeq(4)
  if key.len < 16:
    for k in countup(key.len, 15):
      key.add 0
  for i in countup(0, 3):
    subkeys[i] =  ((key[0+i*4].int32               ) shl 24) or
                  ((key[1+i*4].int32 and 0x00ff0000) shl 16) or
                  ((key[2+i*4].int32 and 0x0000ff00) shl  8) or
                  ((key[3+i*4].int32 and 0x000000ff)       )
  return subkeys

# Decipher a sequence of 8 bytes using a sequence of 4 ints
proc decipher(input: seq[int8], subkeys: seq[int32]): seq[int8] =
  var 
    v = pack(input)
    n = rounds
    sum = d_sum
  for i in countup(1, n):
    v[1] = v[1] -% (((v[0] shl 4 xor v[0] shr 5) +% v[0]) xor (sum +% subkeys[sum shr 11 and 3])).toU32
    sum = sum -% delta
    v[0] = v[0] -% (((v[1] shl 4 xor v[1] shr 5) +% v[1]) xor (sum +% subkeys[sum and 3])).toU32
  return unpack(v)

# Encipher a sequence of 8 bytes using a sequence of 4 ints
proc encipher(input: seq[int8], subkeys: seq[int32]): seq[int8] =
  var
    v = pack(input)
    n = rounds
    sum = 0
  for i in countup(1, n):
    v[0] = v[0] +% (((v[1] shl 4 xor v[1] shr 5) +% v[1]) xor (sum +% subkeys[sum and 3])).toU32
    sum = sum +% delta
    v[1] = v[1] +% (((v[0] shl 4 xor v[0] shr 5) +% v[0]) xor (sum +% subkeys[sum shr 11 and 3])).toU32
  var res = unpack(v)
  return res

proc process(stream: Stream, password: string, operation: TOperation): string =
  var opProc: proc(input: seq[int8], subkeys: seq[int32]) :seq[int8]
  if operation == decryptOp:
    opProc = decipher
  else:
    opProc = encipher
  #zeropad text
  let subkeys = generate_subkeys password
  var
    input, output: seq[int8]
    k = 1
  input.newSeq(0)
  output.newSeq(0)
  while not stream.atEnd:
    input.add stream.readInt8
    # Read eight bytes at a time and process
    if k mod 8 == 0:
      output = output & opProc(input[k-8..k-1], subkeys)
    inc(k)
  # zeropad
  if input.len mod 8 != 0:
    for i in 1..(8-(input.len mod 8)):
      input.add(0)
      inc(k)
    output = output & opProc(input[k-9..k-2], subkeys)
  return bytes2string(output)

proc encrypt*(stream: Stream, password: string): string =
  return process(stream, password, encryptOp)

proc decrypt*(stream: Stream, password: string): string =
  return process(stream, password, decryptOp)


################

var 
  password, file: string = ""
  stream: FileStream = newFileStream(stdin)
  operation: TOperation = encryptOp

for kind, key, val in getopt():
  case kind
  of cmdLongOption, cmdShortOption:
    case key
    of "help", "h":
      echo usage
      quit(0)
    of "version", "v":
      echo version
      quit(0)
    of "password", "p":
      password = val
    of "encrypt", "e":
      operation = encryptOp
    of "decript", "d":
      operation = decryptOp
    else:
      discard
  of cmdArgument:
    file = key
  of cmdEnd: 
    quit(1)
  else:
    discard

if password == "" and file == "":
  echo usage
  quit(0)

if password == "":
  quit("Error: Password not set")

if file != "" and file.existsFile:
  try:
    stream = newFileStream(file, fmRead)
  except:
    stderr.writeln("Error: " & getCurrentExceptionMsg())
  
if operation == encryptOp:
  var entext = encrypt(stream, password)
  echo encode(entext, entext.len*2)
else:
  var s = ""
  while not stream.atEnd:
    s = s & stream.readChar
  echo decrypt(s.decode.newStringStream, password)
