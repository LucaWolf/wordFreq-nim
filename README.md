# Word Frequency Counter (wordFreq-nim)

This is a command-line utility written in Nim that analyzes text files to report the most frequently occurring words. It is designed to be memory-efficient by processing files line-by-line.

## Features
- **Concurrent Processing:** Leverages producer/consumer pattern over channels, 
orchestrated by [malebolgia](https://github.com/Araq/malebolgia) for parallel word extraction and counting.
- **Memory Efficient:** Reads input files line-by-line using `std/syncio`.
- **Case Insensitive:** Converts all words to lowercase for accurate counting.
- **Contraction Handling:** Attempts to properly split lines, discarding common suffixes after single quotes (e.g., "don't" is handled to count the root word).
- **Frequency Tracking:** Utilizes `std/tables` for efficient counting.
- **Note:** Discards words of three or fewer letters.

## Prerequisites
- Nim 2.2.6+ compiler must be installed on your system.

## Build Instructions
The main source file is located at [`src/word_freq.nim`](src/word_freq.nim).

To compile the application, navigate to the project root and run:

```bash
nimble build -d:release -d:ThreadPoolSize=8
```
This command compiles the source and creates an executable file named `word_freq` in the project root directory.

## Usage
The application requires two arguments: the path to the input file and the number of top frequent words to display.

```bash
./word_freq <input_file_path> <count>
```

**Arguments:**
- `<input_file_path>`: The path to the text file you wish to analyze.
- `<count>`: A positive integer specifying the number of most frequent words to display (e.g., 10 for the top 10 words).

**Example:**
To find the top 5 most frequent words in `my_document.txt`:
```bash
./word_freq my_document.txt 5
```