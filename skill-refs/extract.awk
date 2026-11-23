# Extracts code references from Markdown files for skill-refs/refs.sh.
#
#   awk -f extract.awk FILE...
#
# Prints one tab-separated record per reference:
#   P <file> <line> <span>    inline code span in prose (a path candidate)
#   C <file> <line> <words>   a command, from an inline code span or a line in
#                             a shell or untagged fence; words are separated
#                             by \037
#   D <file> <line> <words>   a command after a cd or pushd earlier in the same
#                             span or fence, which runs in another directory
#   W <file> <line> <path>    a .github/workflows/*.yml path in a shell fence
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
  pending = ""
  after_cd = 0
}

# Splits text into words and operators, then prints one C record per command,
# or a D record once a cd or pushd has changed the directory.
function emit_commands(text, line,    i, c, n, word, in_word, quote, words, nwords, cmd, first) {
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
  first = ""
  for (i = 1; i <= nwords + 1; i++) {
    if (i > nwords || words[i] == SUBSEP) {
      if (cmd != "") {
        print (after_cd ? "D" : "C") "\t" fname "\t" line "\t" cmd
        if (first == "cd" || first == "pushd") after_cd = 1
      }
      cmd = ""
      first = ""
      continue
    }
    if (cmd == "") first = words[i]
    cmd = (cmd == "" ? words[i] : cmd "\037" words[i])
  }
}

# Workflow files referred to by a path that starts a word, as in
# "cat .github/workflows/release.yml" or "--file=./.github/workflows/ci.yaml".
# Words with a URL or an @ref point at another repository.
function emit_workflow_paths(text, line,    n, i, words, word, rest) {
  n = split(text, words, /[ \t]+/)
  for (i = 1; i <= n; i++) {
    word = words[i]
    if (word ~ /:\/\// || word ~ /@/) continue
    gsub(/["'`]/, "", word)
    sub(/^[^=]*=/, "", word)
    sub(/^\.\//, "", word)
    if (!match(word, /^\.github\/workflows\/[A-Za-z0-9_.-]+\.ya?ml/)) continue
    rest = substr(word, RLENGTH + 1, 1)
    if (rest ~ /[A-Za-z0-9_.\/-]/) continue
    print "W\t" fname "\t" line "\t" substr(word, 1, RLENGTH)
  }
}

# Line of position i in text, which starts at line first and may span lines.
function line_at(text, i, first,    prefix) {
  prefix = substr(text, 1, i - 1)
  return first + gsub(/\n/, "", prefix)
}

# Finds inline code spans: a run of N backticks closed by the next run of
# exactly N backticks. A span can wrap onto the next lines of its block, so
# an unclosed run waits in pending, with the rest of its line, unless final
# is set; then the run is literal text. In a table row, \| is a pipe.
function scan_spans(text, first, final, table,    i, n, run, j, closing, span, k, line) {
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
    if (!closing) {
      if (!final) {
        pending = substr(text, i)
        pending_line = line_at(text, i, first)
        return
      }
      i += run
      continue
    }
    line = line_at(text, i, first)
    span = substr(text, i + run, closing - i - run)
    gsub(/\n/, " ", span)
    if (table) gsub(/\\\|/, "|", span)
    if (span ~ /^ .* $/ && span !~ /^ +$/) span = substr(span, 2, length(span) - 2)
    if (span != "") {
      print "P\t" fname "\t" line "\t" span
      after_cd = 0
      emit_commands(span, line)
    }
    i = closing + run
  }
}

# The block ended: a run still waiting for its closing run was literal.
function flush_pending(    text) {
  if (pending == "") return
  text = pending
  pending = ""
  scan_spans(text, pending_line, 1, 0)
}

END { flush_pending() }

# Markdown with CRLF line endings: drop the carriage return first, or fences
# and their languages are not recognized.
{ sub(/\r$/, "") }

FNR == 1 {
  # Still under the previous file's name.
  flush_pending()
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
    # Console sessions mix commands and output; only $ lines are commands,
    # with the lines that continue one, which may start with a > prompt.
    if (continued != "") {
      sub(/^[ \t]*>[ \t]?/, "", text)
    } else if (text !~ /^[ \t]*\$ /) {
      next
    }
  }
  if (continued != "") {
    text = continued " " text
    line = continued_line
  } else {
    sub(/^[ \t]*\$ /, "", text)
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

# Any indentation, and after a list marker: fences inside list items are
# indented to the item's content, often by four spaces or more, or open on
# the item's own line.
match($0, /^[ \t]*(([-*+]|[0-9]+[.)])[ \t]+)*(```+|~~~+)/) {
  marker = substr($0, RSTART, RLENGTH)
  sub(/^[ \t]*(([-*+]|[0-9]+[.)])[ \t]+)*/, "", marker)
  info = substr($0, RSTART + RLENGTH)
  # A backtick fence's info string cannot contain backticks.
  if (!(substr(marker, 1, 1) == "`" && info ~ /`/)) {
    flush_pending()
    fence_char = substr(marker, 1, 1)
    fence_len = length(marker)
    sub(/^[ \t]+/, "", info)
    split(info, parts, /[ \t{]/)
    lang = tolower(parts[1])
    fence_shell = (lang == "" || lang == "bash" || lang == "sh" || lang == "shell" || lang == "zsh" || lang == "console")
    fence_console = (lang == "console")
    continued = ""
    after_cd = 0
    next
  }
}

# Prose. A code span cannot cross a blank line or the start of another block:
# a list item, a block quote, a heading or a table row. Headings and table
# rows are single lines.
{
  if ($0 ~ /^[ \t]*$/) { flush_pending(); next }
  single = ($0 ~ /^[ \t]*#+([ \t]|$)/ || $0 ~ /^[ \t]*\|/)
  if (single || $0 ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/ || $0 ~ /^[ \t]*>/) flush_pending()
  if (pending != "") {
    text = pending "\n" $0
    first = pending_line
    pending = ""
  } else {
    text = $0
    first = FNR
  }
  scan_spans(text, first, single, ($0 ~ /^[ \t]*\|/))
}
