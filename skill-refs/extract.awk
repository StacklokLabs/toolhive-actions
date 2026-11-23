# Extracts code references from Markdown files for skill-refs/refs.sh.
#
#   awk -f extract.awk FILE...
#
# Prints one tab-separated record per reference:
#   P <file> <line> <span>    inline code span in prose (a path candidate)
#   C <file> <line> <words>   a command, from an inline code span or a line in
#                             a shell or untagged fence; words are separated
#                             by \037
#   W <file> <line> <path>    a .github/workflows/ path in a shell fence
#
# Only code is read: prose outside code spans, YAML frontmatter and fences in
# other languages are skipped. Commands are split at &&, ||, ;, |, ( and $(,
# quotes are removed, and an unquoted # starts a comment.

# awk reads an operand such as x=1/SKILL.md as a variable assignment, not a
# file. Read those through ./ and report them under the name they were given.
BEGIN {
  for (i = 1; i < ARGC; i++) {
    if (ARGV[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
      given["./" ARGV[i]] = ARGV[i]
      ARGV[i] = "./" ARGV[i]
    }
  }
}

function reset_file() {
  in_frontmatter = 0
  fence_char = ""
  fence_len = 0
  fence_shell = 0
  fence_console = 0
  continued = ""
}

# Splits text into words and operators, then prints one C record per command.
function emit_commands(text, line,    i, c, n, word, in_word, quote, words, nwords, cmd) {
  nwords = 0
  word = ""
  in_word = 0
  quote = ""
  n = length(text)
  for (i = 1; i <= n; i++) {
    c = substr(text, i, 1)
    if (quote != "") {
      if (c == quote) {
        quote = ""
      } else {
        word = word c
      }
      continue
    }
    if (c == "\"" || c == "'") {
      quote = c
      in_word = 1
      continue
    }
    if (c == "#" && !in_word) {
      break
    }
    if (c == " " || c == "\t") {
      if (in_word) { words[++nwords] = word; word = ""; in_word = 0 }
      continue
    }
    if (c == "$" && substr(text, i + 1, 1) == "(") {
      if (in_word) { words[++nwords] = word; word = ""; in_word = 0 }
      words[++nwords] = SUBSEP
      i++
      continue
    }
    if (c == ";" || c == "|" || c == "&" || c == "(" || c == ")" || c == "`") {
      if (in_word) { words[++nwords] = word; word = ""; in_word = 0 }
      words[++nwords] = SUBSEP
      continue
    }
    word = word c
    in_word = 1
  }
  if (in_word) words[++nwords] = word

  cmd = ""
  for (i = 1; i <= nwords + 1; i++) {
    if (i > nwords || words[i] == SUBSEP) {
      if (cmd != "") print "C\t" fname "\t" line "\t" cmd
      cmd = ""
      continue
    }
    cmd = (cmd == "" ? words[i] : cmd "\037" words[i])
  }
}

function emit_workflow_paths(text, line,    rest, path) {
  rest = text
  while (match(rest, /\.github\/workflows\/[A-Za-z0-9_.-]+/)) {
    path = substr(rest, RSTART, RLENGTH)
    print "W\t" fname "\t" line "\t" path
    rest = substr(rest, RSTART + RLENGTH)
  }
}

# Finds inline code spans: a run of N backticks closed by the next run of
# exactly N backticks on the same line.
function scan_spans(text, line,    i, n, run, j, closing, span, k) {
  n = length(text)
  i = 1
  while (i <= n) {
    if (substr(text, i, 1) != "`") { i++; continue }
    run = 0
    while (i + run <= n && substr(text, i + run, 1) == "`") run++
    closing = 0
    j = i + run
    while (j <= n) {
      if (substr(text, j, 1) != "`") { j++; continue }
      k = 0
      while (j + k <= n && substr(text, j + k, 1) == "`") k++
      if (k == run) { closing = j; break }
      j += k
    }
    if (!closing) { i += run; continue }
    span = substr(text, i + run, closing - i - run)
    if (span ~ /^ .* $/ && span !~ /^ +$/) span = substr(span, 2, length(span) - 2)
    if (span != "") {
      print "P\t" fname "\t" line "\t" span
      emit_commands(span, line)
    }
    i = closing + run
  }
}

# Markdown with CRLF line endings: drop the carriage return first, or fences
# and their languages are not recognized.
{ sub(/\r$/, "") }

FNR == 1 {
  fname = (FILENAME in given) ? given[FILENAME] : FILENAME
  reset_file()
  if ($0 ~ /^---[ \t]*$/) { in_frontmatter = 1; next }
}

in_frontmatter {
  if ($0 ~ /^(---|\.\.\.)[ \t]*$/) in_frontmatter = 0
  next
}

fence_char != "" {
  # A closing fence uses the same character, at least as many times, and
  # has no info string.
  if (match($0, /^[ \t]*(`+|~+)[ \t]*$/)) {
    marker = $0
    gsub(/[ \t]/, "", marker)
    if (substr(marker, 1, 1) == fence_char && length(marker) >= fence_len) {
      fence_char = ""
      next
    }
  }
  if (!fence_shell) next

  text = $0
  if (fence_console) {
    # Console sessions mix commands and output; only $ lines are commands.
    if (text !~ /^[ \t]*\$ /) next
  }
  sub(/^[ \t]*\$ /, "", text)
  if (continued != "") {
    text = continued " " text
    line = continued_line
  } else {
    line = FNR
  }
  if (text ~ /\\$/) {
    continued = substr(text, 1, length(text) - 1)
    continued_line = line
    next
  }
  continued = ""
  emit_commands(text, line)
  emit_workflow_paths(text, line)
  next
}

# Any indentation: fences inside list items are indented to the item's
# content, often by four spaces or more.
match($0, /^[ \t]*(```+|~~~+)/) {
  marker = substr($0, RSTART, RLENGTH)
  sub(/^[ \t]+/, "", marker)
  info = substr($0, RSTART + RLENGTH)
  # A backtick fence's info string cannot contain backticks.
  if (!(substr(marker, 1, 1) == "`" && info ~ /`/)) {
    fence_char = substr(marker, 1, 1)
    fence_len = length(marker)
    sub(/^[ \t]+/, "", info)
    split(info, parts, /[ \t{]/)
    lang = tolower(parts[1])
    fence_shell = (lang == "" || lang == "bash" || lang == "sh" || lang == "shell" || lang == "zsh" || lang == "console")
    fence_console = (lang == "console")
    continued = ""
    next
  }
}

{
  scan_spans($0, FNR)
}
