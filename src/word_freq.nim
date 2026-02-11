import std/[os, tables, syncio, strutils, algorithm]

proc usage() =
  echo "Usage: word_freq <file_path> <count>"
  echo "  <file_path>  : Path to the input text file."
  echo "  <count>      : Number of most frequent words to display."

proc main() =
  if paramCount() != 2:
    usage()
    quit(1)

  let filePath = paramStr(1)
  let countStr = paramStr(2)

  var count: int
  try:
    count = parseInt(countStr)
  except:
    echo "Error: <count> must be a valid integer."
    usage()
    quit(1)

  if count <= 0:
    echo "Error: <count> must be a positive integer."
    usage()
    quit(1)

  if not fileExists(filePath):
    echo "Error: File not found: ", filePath
    usage()
    quit(1)

  var wordCounts: CountTable[string]
  
  block read_file:
    let f = open(filePath)
    defer: f.close()

    var all_seps = PunctuationChars + Whitespace

    for line in f.lines:
      for word in line.split(all_seps):
        if word.len > 3:
          var cleanedWord = word.toLowerAscii()          
          if cleanedWord.len > 0:
            wordCounts.inc(cleanedWord)

  wordCounts.sort()
  var n = min(count, wordCounts.len)
  var idx = 0

  echo "\nTop ", count, " most frequent words:"
  echo "---------------------------------"
  for k,v in pairs(wordCounts):
    inc idx
    echo idx, ".\t", v, " ", k
    
    if idx >= n:
      break

when isMainModule:
  main()