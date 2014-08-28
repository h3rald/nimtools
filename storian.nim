import
  parseopt2, os, times, re, strutils


type
  TErrorCode = enum
    ecGeneric = 1,
    ecNoSrc = 2,
    ecNoDest = 3,
    ecSrcIsFile = 4,
    ecDestIsFile = 5,
    ecInvalidTimeRange = 6,
    ecInvalidSizeRange = 7
  TAction = enum
    aArchive,
    aBackup,
    aList,
    aHelp,
    aVersion,
    aTotalsize,
    aDelete,
    aCount
  TFileInfo = tuple
    path: string
    name: string
    ext: string
    fullname: string
    mtime: TTime
    size: int64

const
  v = "0.1"
  usage = "  Storian v" & v & " - Nimrod File Filtering & Archiving Utility" & """

  (c) 2013-2014 Fabio Cevasco
  
  Usage:
    storian [options] source_directory [destination_directory]

  Arguments:
    source_directory          the directory to be scanned.
    destination_directory     the directory where the archive/backup files 
                              will be placed.
  General Options:
    --info                    prints additional information and stats.

  Operation Options:
    --help, -h                shows this help.
    --version, -v             shows the version.
    --list, -l                (default) lists the filtered files.
    --count, -c               counts the filtered files.
    --archive, -a             moves the filtered files to destination_directory. 
    --backup, -b              copiesthe filtered files to destination_directory.
    --delete, -d              deletes the filtered files.
    --totalsize, -s           display the total size of the filtered files.

  Filtering Options:
    --minsize:size, 
    --bigger-than:size        include only files bigger than the specified size.
                              Example: --minsize:100KB

    --maxsize:size, 
    --smaller-than:size       include only files smaller than the specified size.
                              -> Example: --smaller-than:5MB
    --since:date,
    --from:date               include only files modified after the specified date.
                              -> Example: --since:2013-01-15
    --till:date,
    --to:date                 include only files modified before the specified date.
                              -> Example: --to:2012-12-31
    --name:string             include only files containing the specified string.
    --ext:ext1,ext2           include only file of the specified extensions.

  Archiving/Backup Options:
    --fsys:s1/s2/s3           defines the "filing system" for archive/backup folders.
                              s1, s2, ... are parametric strings separated by '/'
                              used to identify folder names. 
                              The following parameters are available:
                               %y: year (four digits)
                               %m: month (two digits)
                               %n: month name
                               %d: day (two digits)
                               %e: extension
                              

  Examples:
    
    storian --minsize:50MB .
    -> List all the files bigger than 50MB within the current directory.

    storian --till:2012-12-31 -a --ext:avi,mpg --org:%Y/%M / "My Archive\test"
    -> Move all the .avi and .mpg files that were last modified before 2013 to a 
       "My Archive\test" folder, organized by year and month.
  """

  nilseq = @[""]
  niltime = TTime(0)
  nilstring = ""
  nilint = 0
  scan_actions = {aList, aArchive, aBackup, aTotalsize, aCount, aDelete}

var
  execstart = cpuTime()
  execstop: float
  n_args = 0
  n_files = 0
  f_files = 0
  files: seq[TFileInfo] = @[]
  size: int64 = 0

  src = nilstring
  dest = nilstring
  stime = niltime
  etime = getTime()
  maxsize = high(int64)
  minsize = nilint
  name = nilstring
  exts = nilseq
  action = aList
  info = false
  fsys = nilstring
  confirmop = false

proc toDate(s: string, dayend = false): TTime =
  if not s.match(re"^\d\d\d\d-\d\d-\d\d$"):
    quit("Error: Invalid date format - must be YYYY-MM-DD.")
  var date: array[0..2, int]
  var i = 0
  for num in split(s, '-'):
    date[i] = num.parseInt
    inc(i)
  var tinfo: TTimeInfo
  try:
    tinfo = TTimeInfo(year: date[0], month: TMonth(date[1]-1), monthday: date[2])
  except:
    quit("Error: Invalid date.")
  if dayend:
    tinfo.hour = 23
    tinfo.minute = 59
    tinfo.second = 59
  return tinfo.TimeInfoToTime

proc toFileSize(s: string): int =
  let r = r"^(\d+)(KB|MB|GB)?$".re({reIgnoreCase})
  var matches: array[0..1, string]
  let valid_size = s.match(r, matches)
  if valid_size == false:
    quit("Error: invalid size value.")
  let size = matches[0].parseInt
  if matches[1].isNil:
    return size
  else:
    return
      case matches[1]
      of "KB", "kb", "Kb":
        size*1024
      of "MB", "mb", "Mb":
        size*1024*1024
      of "GB", "gb", "Gb":
        size*10024*1024*1024
      else: size 

proc parseFilingSystem(f: TFileInfo, s: string): seq[string] = 
  let tinfo = f.mtime.getLocalTime
  let y = tinfo.format("yyyy")
  let m = tinfo.format("MM")
  let n = tinfo.format("MMM")
  let d = tinfo.format("dd")
  let e = f.ext
  var folders = nilseq
  for fld in s.split('/'):
    let folder = fld.replace("%y", y).replace("%m", m).replace("%n", n).replace("%d", d).replace("%e", e)
    folders.add(folder)
  return folders

proc checkopts =
  let has_src = action notin scan_actions or src != nilstring
  let has_dest = action notin {aArchive, aBackup} or dest != nilstring
  let valid_timerange = action notin scan_actions or (etime <= getTime() and stime <= getTime() and stime < etime)
  let valid_sizerange = action notin scan_actions or minsize == nilint or maxsize == nilint or minsize < maxsize
  if not has_src:
    quit("Error: Source argument is required by the list, archive, backup, totalsize, count and delete operations.", ecNoSrc.ord)
  if not has_dest:
    quit("Error: Destination argument is required by the archive and backup operations.", ecNoDest.ord)
  if not valid_timerange:
    quit("Error: Invalid time range", ecInvalidTimeRange.ord)
  if not valid_sizerange:
    quit("Error: Invalid size range", ecInvalidSizeRange.ord)

proc manageFile(f: TFileInfo) =
  var dir = dest
  if action in {aArchive, aBackup}:
    for i in parseFilingSystem(f, fsys):
      dir = dir/i
  try:
    echo(f.path)
    case action
    of aBackup:
      echo("    -> ", dir/f.fullname)
      if not dir.existsDir: 
        dir.createDir
      f.path.copyFile(dir/f.fullname)
    of aArchive:
      echo("    -> ", dir/f.fullname)
      if not dir.existsDir: dir.createDir
      f.path.moveFile(dir/f.fullname)
    of aDelete:
      echo("    -> *")
      f.path.removeFile
    else: nil
  except:
    stderr.writeln("  Warning: " & getCurrentExceptionMsg())

proc agree(msg): bool =
  while true:
    echo(msg)
    let s = stdin.readLine
    if s.match(r"^y(es)?$".re({reIgnoreCase})):
      return true
    elif s.match(r"^no?$".re({reIgnoreCase})):
      return false
    else:
      echo("Please answer 'yes' or 'no'.")

proc help =
  echo(usage)

proc scan =
  for path in walkDirRec(src, filter = {pcFile, pcDir}):
    inc(n_files)
    let fileelements = path.splitFile
    let fileext = fileelements.ext
    let filename = fileelements.name
    let fullname = filename & fileext
    # Ignore unless file matches specified extension
    if exts != nilseq and not(exts.contains(fileext)): 
      continue
    # Ignore unless filename matches specified pattern
    if name != nilstring and not(filename.contains(name)): 
      continue
    var filetime: TTime
    var filesize: int64
    try:
      filetime = path.getLastModificationTime
      # Ignore if file is newer than etime
      if filetime > etime:
        continue
      # Ignore if file is older than stime
      if stime != niltime and filetime < stime:
        continue
      filesize = path.getFileSize
      # Ignore if file is smaller than minsize
      if minsize != nilint and filesize < minsize:
        continue
      # Ignore if file is bigger than maxsize
      if maxsize != nilint and filesize > maxsize:
        continue
    except:
      stderr.writeln(path)
      stderr.writeln("  Warning: " & getCurrentExceptionMsg())
      continue
    inc(f_files)
    case action
    of aTotalsize:
      size += filesize
    of aList, aArchive, aBackup, aDelete:
      echo(path)
      # Save filtered file for later
      if action != aList:
        files.add((path: path, name: filename, ext: fileext, fullname: fullname, mtime: filetime, size: filesize))
      if info:
        echo("   Last Modified: ", filetime) 
        echo("            Size: ", filesize.formatSize)
    else: nil

proc startinfo = 
  let str_action = case action
                   of aBackup: "backup"
                   of aArchive: "archive"
                   of aList: "list"
                   of aTotalsize: "totalsize"
                   of aCount: "count"
                   of aDelete: "delete"
                   of aHelp: "help"
                   of aVersion: "version"
  echo("\n")
  echo("         Source: ", src)
  echo("    Destination: ", dest)
  echo("         Action: ", str_action)
  echo("     Start Time: ", stime)
  echo("       End Time: ", etime)
  echo("      File Name: ", name)
  echo("     Extensions: ", exts.join(", "))
  echo("      Min. Size: ", minsize.formatSize)
  echo("      Max. Size: ", maxsize.formatSize)
  echo("    Filing Sys.: ", fsys)
  echo("\n")

proc stopinfo = 
  execstop = cpuTime()
  echo("\n")
  echo("   Elapsed time: ", (execstop-execstart).formatFloat, " seconds")
  echo("          Files: ", f_files, "/", n_files)

# Parse arguments and options
for kind, key, val in getopt():
  if kind == cmdArgument:
    case n_args
    of 0:
      src = key
      if src.existsFile:
        quit("Error: Specified source is a file.", ecSrcIsFile.ord)
    of 1:
      dest = key
      if dest.existsFile:
        quit("Error: Specified destination is a file.", ecDestIsFile.ord)
    else: nil
    n_args.inc
  else: nil
  case key
  of "since", "from":
    stime = val.toDate
  of "till", "to":
    etime = val.toDate(true)
  of "minsize", "bigger-than":
    minsize = val.toFileSize
  of "maxsize", "smaller-than":
    maxsize = val.toFileSize
  of "name":
    name = val
  of "ext", "extension":
    var fixext = proc(x:string): string = 
      if x.startsWith("."): x 
      else: "."&x
    exts = val.split(re"[;,+]").map(fixext)
  of "a", "archive":
    action = aArchive
  of "b", "backup":
    action = aBackup
  of "c", "count":
    action = aCount
  of "h", "help":
    action = aHelp
  of "l", "list":
    action = aList
  of "s", "totalsize":
    action = aTotalsize
  of "v", "version":
    action = aVersion
  of "d", "delete":
    action = aDelete
  of "info":
    info = true
  of "fsys":
    fsys = val
  else: nil



# Main Execution

if src == nilstring and action == aList: 
  action = aHelp

checkopts()

if info and action in scan_actions: startinfo()

case action
of aHelp: help()
of aVersion: echo(v)
of aList:
  scan()
of aCount:
  scan()
  echo(f_files)
of aTotalsize:
  scan()
  echo(size.formatSize)
of aArchive: 
  scan()
  if f_files > 0 and agree("Do you want to archive " & $f_files & " files to '" & dest & "'? [y/n]"):
    confirmop = true
of aBackup: 
  scan()
  if f_files > 0 and agree("Do you want to backup " & $f_files & " files to '" & dest & "'? [y/n]"):
    confirmop = true
of aDelete:
  scan()
  if f_files > 0 and agree("Do you want to delete " & $f_files & " files? [y/n]"):
    confirmop = true
else: help()

if confirmop:
  for f in files: 
    f.manageFile

if info and action in scan_actions: stopinfo()
