import std/[os, tables, heapqueue, strutils, strformat]
import threading/[channels, rwlock]
import malebolgia
import malebolgia / lockers

type
  Flag = tuple[done: bool, rw: RwLock]
  Word = tuple[freq: int, value: string]

proc done(f: var Flag): bool = 
  readWith f.rw:
    result = f.done

proc signal(f: var Flag) = 
  writeWith f.rw:
    f.done = true

proc `<`(a, b: Word): bool = a.freq < b.freq
proc `$`(w: Word): string = fmt"{w.freq}|{w.value}"


proc usage() =
  echo "Usage: word_freq <file_path> <count> <core_count>"
  echo "  <file_path>  : Path to the input text file."
  echo "  <count>      : Number of most frequent words to display."


proc wordsInBuckets(fname: string, ch: openArray[Chan[string]], flag: Locker[Flag]) =
  let all_seps = PunctuationChars + Whitespace
  
  for line in lines(fname):
    for word in line.split(all_seps):
      case word.len:
        of 0..3:
          continue # skip pronouns, articles, etc
        of 4:
          ch[0].send word.toLowerAscii
        of 5:
          ch[1].send word.toLowerAscii
        of 6:
          ch[2].send word.toLowerAscii
        else:
          ch[3].send word.toLowerAscii
  
  # use the inner RwLock, malebolgia Locker is just for the type system
  unprotected flag as f:
    f.signal()


proc wordsInBucket(fname: string, ch: Chan[string], flag: Locker[Flag]) =
  let all_seps = PunctuationChars + Whitespace
  
  for line in lines(fname):
    for word in line.split(all_seps):
      case word.len:
        of 0..3:
          continue
        else:
          ch.send word.toLowerAscii
  
  # use the inner RwLock, malebolgia Locker is just for the type system
  unprotected flag as f:
    f.signal()


proc countWords(tag: string, ch: Chan[string], results: Locker[CountTable[string]], flag: Locker[Flag]) =
  var n = 0

  while true:
    # chan probe
    var word = ""    
    if ch.tryRecv(word):
      # in this run results are thread disjoint; lock for accumulators
      lock results as r: 
        r.inc word
        n.inc
      continue

    # done probe
    unprotected flag as f:
      if f.done():
        echo tag, " work done; msg count: ", n
        break

    # busy wait
    sleep(5)


proc consume(pot: var HeapQueue[Word], t: CountTable[string], records: int) =
  for word, freq in pairs(t):
    let item = (freq, word)
    # saturate feed the pot
    if len(pot) < records:      
      pot.push(item)
    elif freq > pot[0].freq:
      # then preserve the strongest candidates
      discard pot.replace(item)
    

proc countWordsFile(fname: string, count: int) =
  var m = createMaster()
  var res1 = initLocker initCountTable[string](4 * 1024)
  var res2 = initLocker initCountTable[string](8 * 1024)
  var res3 = initLocker initCountTable[string](8 * 1024)
  var res4 = initLocker initCountTable[string](40 * 1024)
  var wr1 = newChan[string](8*1024) # 10% of the total count should do
  var wr2 = newChan[string](8*1024)
  var wr3 = newChan[string](8*1024)
  var wr4 = newChan[string](8*1024)
  var chStatus = initLocker (false, createRwLock())

  m.awaitAll:
    # producer
    m.spawn wordsInBuckets(fname, [wr1, wr2, wr3, wr4], chStatus)
    # consumers
    # 1. all separate pots
    # 0.70s user 0.14s system 188% cpu 0.444 total
    m.spawn countWords("4_letters", wr1, res1, chStatus)
    m.spawn countWords("5_letters", wr2, res2, chStatus)
    m.spawn countWords("6_letters", wr3, res3, chStatus)
    m.spawn countWords("7_letters", wr4, res4, chStatus)
    
    # in a heap mode finalizer, we cannot place same word, with partial frequencies,    
    # in different buckets. 
    # m.spawn countWords(wr4, res1, chStatus) - not correct in heap consuming

    # Instead, we could try spawning more target clones
    # 2. enabling this (only for 1.)
    # m.spawn countWords("4_letters_extra", wr1, res1, chStatus)
    # m.spawn countWords("5_letters_extra", wr2, res2, chStatus)
    # m.spawn countWords("6_letters_extra", wr3, res3, chStatus)
    # m.spawn countWords("7_letters_extra", wr4, res4, chStatus)

    # 3a. alternative to 1. (either/or)
    # high contention over the same bucket lock
    # 23.45s user 1.34s system 389% cpu 6.362 total
    # m.spawn countWords("4_same_bucket", wr1, res4, chStatus)
    # m.spawn countWords("5_same_bucket", wr2, res4, chStatus)
    # m.spawn countWords("6_same_bucket", wr3, res4, chStatus)
    # m.spawn countWords("7_same_bucket", wr4, res4, chStatus)

    # 3b. alternative to 1. (either/or)
    # split contention over two buckets
    # 1.88s user 0.19s system 304% cpu 0.680 total
    # m.spawn countWords("4_split_bucket", wr1, res1, chStatus)
    # m.spawn countWords("5_split_bucket", wr2, res1, chStatus)
    # m.spawn countWords("6_split_bucket", wr3, res4, chStatus)
    # m.spawn countWords("7_split_bucket", wr4, res4, chStatus)

    # 4. single buclet/channel, single producer/consumer case as alternative to 1. (either/or)
    # (comment the other producer)
    # 0.73s user 0.30s system 105% cpu 0.973 total
    # m.spawn wordsInBucket(fname, wr1, chStatus)
    # m.spawn countWords("same_channel", wr1, res4, chStatus)


  # global counting outcome
  echo "------------------- dictionary length"
  var heap: HeapQueue[Word]
  # fill a fixed size heap instead of joining r1 <- (r2, r3, r4) + sorting
  unprotected res1 as r1:
    echo "4_letters: ", r1.len
    heap.consume(r1, count)
  unprotected res2 as r2:
    echo "5_letters: ", r2.len
    heap.consume(r2, count)
  unprotected res3 as r3:
    echo "6_letters: ", r3.len
    heap.consume(r3, count)
  unprotected res4 as r4:
    echo "7_letters: ", r4.len
    heap.consume(r4, count)
          
  echo "\nTop ", count, " most frequent words:"
  echo "---------------------------------"
  for n in countdown(heap.len, 1):
    var it = heap.pop()
    echo fmt"{n}: ", $it
    

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

  # let f = open(filePath)
  # let lines = toSeq(f.lines)
  # let lines = f.readAll()
  # f.close()
  countWordsFile(filePath, count)

  
when isMainModule:
  main()