# Lecture 3: Create simple shell scripts

A shell script is nothing more than the commands you would type, saved in a file, plus a little logic:
decisions, loops and inputs. The RHCSA asks for short, practical scripts, the kind an administrator writes
to create a batch of users, check a set of hosts, or find large files. You are graded by running your script
with inputs you have not seen, so it has to behave correctly in the edge cases too: missing arguments, file
names with spaces, users that do not exist.

This lecture builds the language up from how bash runs a script, through variables and quoting, to the four
objective areas: conditions, loops, inputs and command output. Everything here also makes you better at the
interactive shell, because it is the same language.

---

## Background: how a script runs

### The shebang line

Create a file and make it executable:

```bash
cat > /usr/local/bin/hello.sh <<'EOF'
#!/bin/bash
echo "Hello from $(hostname)"
EOF
chmod +x /usr/local/bin/hello.sh
hello.sh
```

When you run a file, the kernel looks at its first bytes. If they are `#!`, the rest of that line is an
**interpreter path**, and the kernel runs `/bin/bash /usr/local/bin/hello.sh` for you. That first line is the
**shebang**. Without it, bash would usually still run the file as a script when you start it from bash, but
cron, systemd or another shell may not, so always include `#!/bin/bash` as the very first line (no leading
blank line or spaces).

Three ways to run a script, with different requirements and effects:

| Command | Needs `x`? | Runs in |
|---|---|---|
| `./script.sh` or `/path/script.sh` or `script.sh` (if in `PATH`) | yes (and `r`) | a new bash process |
| `bash script.sh` | no, only `r` | a new bash process |
| `source script.sh` or `. script.sh` | no | **your current shell** |

A script run normally is a **child process**: it gets a copy of your exported environment, and nothing it does
(changing directory, setting variables) affects your shell after it exits. `source` is the exception: it
executes the lines in your current shell, which is how `~/.bashrc` is loaded and how you would apply a file of
variable assignments.

Where to put scripts: `/usr/local/bin` is in everyone's `PATH` and is meant for locally added programs; root's
own tools can go in `/root/bin` or `/usr/local/sbin`. On the exam, put the script exactly where the task says.

### Debugging tools you should always use

```bash
bash -n script.sh     # parse only: catches syntax errors without running anything
bash -x script.sh     # trace: prints each command, after expansion, prefixed with +
```

`set -x` / `set +x` inside a script turns tracing on and off around a suspicious section. The trace shows the
command **after** variable expansion and word splitting, which instantly exposes quoting bugs.

### Comments and readability

`#` starts a comment to the end of the line (except in the shebang and inside quotes). Indent the bodies of
`if` and loops. Use meaningful variable names. Graders do not care, but you will, when you debug at speed.

---

## Variables, quoting and the environment

### Assigning and using variables

```bash
name=harry            # NO spaces around =
count=3
greeting="Hello, $name"
echo "$greeting, you have $count messages"
echo "${name}_backup"  # braces separate the name from following text
```

`name = harry` is a classic error: bash parses it as the command `name` with arguments `=` and `harry`.

All bash variables are strings. Arithmetic is done explicitly with `$(( ))`:

```bash
total=$((count * 2 + 1))
((count++))
```

Useful expansions:

| Syntax | Result |
|---|---|
| `${var:-default}` | `default` if `var` is unset or empty |
| `${var:=default}` | same, and assign it |
| `${#var}` | length of the string |
| `${var%.txt}` | remove the shortest `.txt` suffix: `report.txt` → `report` |
| `${var##*/}` | remove the longest prefix ending in `/`: the file name part of a path (like `basename`) |
| `${var%/*}` | the directory part (like `dirname`) |
| `${var/old/new}` | replace first `old` with `new` (`//` for all) |

### Why quoting matters so much in scripts

Recall from Lecture 1 that the shell splits the **result** of an unquoted `$var` into words and then expands
wildcards in them. In a script, variables hold data you did not choose (file names, user input), so unquoted
variables break in ways that tests don't catch:

```bash
file="my report.txt"
rm $file       # tries to remove "my" and "report.txt"
rm "$file"     # removes "my report.txt"

dir=""
[ -d $dir ]    # becomes [ -d ], which is TRUE (a single non-empty string), a silent bug
[ -d "$dir" ]  # becomes [ -d "" ], correctly false
```

**Rule: double-quote every variable expansion and command substitution** (`"$var"`, `"$@"`, `"$(cmd)"`),
unless you specifically want splitting. This one habit prevents most script bugs.

### Shell variables versus environment variables

A variable you set is a **shell variable**, visible only in the current shell. `export` marks it as an
**environment variable**, which is copied into every child process the shell starts:

```bash
LOGDIR=/var/log/app        # only this shell
export LOGDIR              # now children (scripts, programs) inherit it
export PATH="$PATH:/opt/tools/bin"
env | grep LOGDIR          # list the environment
VAR=value command          # set VAR only in command's environment
```

The environment flows one way: parent to child. A script cannot change its caller's variables (unless sourced).

Standard variables worth knowing: `HOME`, `USER`, `PATH`, `PWD`, `SHELL`, `HOSTNAME`, `LANG`, `RANDOM`,
`UID` (read-only), and `$$` (the shell's PID).

> **Cron and systemd gotcha.** Scripts run by cron or a systemd timer get a minimal environment, often with a
> short `PATH` (cron uses `/usr/bin:/bin`). If your script calls `/usr/sbin` tools, use full paths or set
> `PATH` at the top of the script.

---

## 3.1 Conditionally execute code (use of: if, test, [], etc.)

### Exit status is the condition

In most languages, `if` tests a boolean expression. In the shell, **`if` runs a command and tests its exit
status**: 0 means true (success), anything else means false.

```bash
if grep -q '^harry:' /etc/passwd; then
    echo "harry exists"
else
    echo "no harry"
fi
```

`grep -q` produces no output; it only sets its exit status. Any command works: `if id "$user" &>/dev/null`,
`if ping -c1 -W1 "$host" &>/dev/null`, `if systemctl is-active --quiet sshd`. This is the most natural way to
write administrative conditions: ask the tool that knows.

The full form:

```bash
if COMMAND; then
    ...
elif OTHER_COMMAND; then
    ...
else
    ...
fi
```

`then` must be on a new line or after a `;`. `!` inverts a status: `if ! id "$u" &>/dev/null; then`.

### test, [ ] and [[ ]]

For conditions that are not naturally a command, such as comparing strings or checking file types, there is
the `test` command, whose other name is `[`. `[ -f /etc/hosts ]` literally runs the command `[` with the
arguments `-f`, `/etc/hosts` and `]`. That is why **the spaces are mandatory**: `[-f file]` looks for a command
named `[-f`.

File tests:

| Test | True if |
|---|---|
| `-e path` | exists (any type) |
| `-f path` | is a regular file |
| `-d path` | is a directory |
| `-L path` | is a symbolic link |
| `-s path` | exists and is not empty |
| `-r`, `-w`, `-x path` | readable / writable / executable **by you** |
| `a -nt b`, `a -ot b` | `a` is newer / older than `b` |

String tests:

| Test | True if |
|---|---|
| `-z "$s"` | empty string |
| `-n "$s"` | non-empty |
| `"$a" = "$b"` | equal (`==` also works in bash) |
| `"$a" != "$b"` | different |

Integer tests (strings are converted to numbers):

| Test | Meaning |
|---|---|
| `-eq`, `-ne` | equal, not equal |
| `-lt`, `-le` | less than, less or equal |
| `-gt`, `-ge` | greater than, greater or equal |

Do not mix them up: `[ "$a" = "$b" ]` compares text, `[ "$a" -eq "$b" ]` compares numbers, and `[ $a > $b ]`
is **not** a comparison at all: `>` is redirection, so it creates a file named after `$b`.

Combine tests with `&&` and `||` between brackets: `[ -f "$f" ] && [ -r "$f" ]`. (`-a` and `-o` inside a single
`[ ]` exist but are deprecated.)

**`[[ ]]`** is bash's built-in improved test. It does not word-split variables (so quoting mistakes are less
dangerous), allows `&&` and `||` inside, `<` and `>` for string ordering, pattern matching with `==`, and regex
matching with `=~`:

```bash
if [[ $answer == [Yy]* ]]; then echo yes; fi
if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "looks like IPv4"; fi
```

**`(( ))`** evaluates arithmetic and is true if the result is non-zero: `if (( count > 10 )); then`. Inside it,
`>` and `<` are real comparisons and you can omit `$`.

Any of these is fine on the exam. `[ ]` is the portable classic and what the objective names; use `[[ ]]` when
you want patterns.

### Short-circuit operators as compact ifs

```bash
[ -d /backup ] || mkdir -p /backup
[ $# -eq 0 ] && { echo "Usage: $0 FILE" >&2; exit 2; }
```

Use braces `{ ...; }` (with the spaces and the final `;`) to group several commands.

### case

When one value is compared against several patterns, `case` is cleaner than a chain of `elif`:

```bash
case "$1" in
    start|begin)  systemctl start httpd ;;
    stop)         systemctl stop httpd ;;
    status)       systemctl status httpd ;;
    *.conf)       echo "a config file: $1" ;;
    *)            echo "Usage: $0 {start|stop|status}" >&2; exit 2 ;;
esac
```

Patterns are shell globs, `|` separates alternatives, each branch ends with `;;`, and `*)` is the catch-all.

---

## 3.2 Use Looping constructs (for, etc.) to process file, command line input

### for: iterate over a list of words

```bash
for user in alice bob carol; do
    useradd "$user"
done

for f in /var/log/*.log; do          # a glob: safe with spaces, each match is one item
    echo "$f: $(wc -l < "$f") lines"
done

for i in {1..5}; do echo "$i"; done  # brace expansion
for i in $(seq 1 2 9); do echo "$i"; done   # 1 3 5 7 9
for ((i = 0; i < 5; i++)); do echo "$i"; done   # C-style

for arg in "$@"; do                  # every command-line argument, spaces preserved
    echo "arg: $arg"
done
```

A `for` loop over `$(cat file)` splits on **any whitespace**, not lines, so it breaks lines that contain spaces.
For files, use `while read`.

### while read: process a file line by line

```bash
while read -r line; do
    echo "got: $line"
done < /root/users.txt
```

- `read` reads one line from stdin into the variable and returns non-zero at end of file, which ends the loop.
- `-r` stops backslashes being treated as escapes. Always use it.
- The `< file` after `done` feeds the whole loop from the file.
- `read` strips leading and trailing whitespace (because of `IFS`); `IFS= read -r line` keeps it exactly.

`read` can split a line into fields, using `IFS` (the Internal Field Separator, whitespace by default):

```bash
while IFS=: read -r user _ uid gid _ home shell; do
    [ "$uid" -ge 1000 ] && echo "$user uses $shell"
done < /etc/passwd
```

Variables named `_` are a convention for "ignore this field". The last variable gets the rest of the line.

**Skipping lines** is a common requirement:

```bash
while read -r name; do
    [ -z "$name" ] && continue               # blank line
    [[ $name == \#* ]] && continue           # comment
    echo "processing $name"
done < "$1"
```

`continue` jumps to the next iteration; `break` leaves the loop.

**The pipe-into-while trap.** `cmd | while read ...; do count=$((count+1)); done` runs the loop in a subshell
(every part of a pipeline is a separate process), so `count` is unchanged after the loop. If you need the
variables afterwards, feed the loop with process substitution instead: `done < <(cmd)`.

### while and until with conditions

```bash
count=0
while [ "$count" -lt 5 ]; do
    count=$((count + 1))
done

until systemctl is-active --quiet httpd; do   # loop until the command succeeds
    sleep 1
done
```

---

## 3.3 Process script inputs ($1, $2, etc.)

### Positional parameters

When a script runs as `./myscript.sh alice "bob smith" 42`, bash sets:

| Parameter | Value |
|---|---|
| `$0` | the script name as invoked (`./myscript.sh`) |
| `$1`, `$2`, `$3` | `alice`, `bob smith`, `42` |
| `${10}` | the tenth argument (braces required beyond 9) |
| `$#` | number of arguments: `3` |
| `"$@"` | all arguments, each as a separate word: `"alice" "bob smith" "42"` |
| `"$*"` | all arguments joined into one word: `"alice bob smith 42"` |

**Use `"$@"`**, quoted, to pass on or loop over arguments. It is the only form that keeps "bob smith" as one
argument. Unquoted `$@` and `$*` both re-split it into two.

`shift` discards `$1` and moves the rest down (`$2` becomes `$1`, `$#` decreases). It is handy when the first
argument is special:

```bash
dest="$1"; shift              # first argument is a directory
for user in "$@"; do          # the rest are users
    tar -czf "$dest/$user.tar.gz" -C /home "$user"
done
```

### Validate inputs first

Graders deliberately call your script with no arguments, too many, or bad values. Check at the top and fail
clearly:

```bash
#!/bin/bash
if [ $# -ne 2 ]; then
    echo "Usage: $(basename "$0") DIR SIZE_KB" >&2
    exit 2
fi
dir="$1"; size="$2"
if [ ! -d "$dir" ]; then
    echo "$dir: not a directory" >&2
    exit 1
fi
```

Error messages go to **stderr** (`>&2`), so they do not pollute output that someone may be capturing, and the
script exits with a **non-zero status** so callers can detect failure. Conventionally `1` is a general error and
`2` is a usage error, but follow whatever the task specifies exactly.

`$(basename "$0")` prints the script's name without its path, which makes usage messages look the same however
the script was called.

### Interactive input

```bash
read -p "Username: " user
read -s -p "Password: " pw; echo     # -s: don't echo what is typed
read -t 10 -p "Continue? " ans       # timeout after 10 s
```

Interactive prompts make a script hard to grade or automate, so prefer arguments unless asked.

### Options with getopts (bonus)

For scripts with flags like `-v -o file`, bash's `getopts` parses them. It is beyond what the exam usually
asks, but good to recognise:

```bash
while getopts "vo:" opt; do
    case $opt in
        v) verbose=1 ;;
        o) outfile=$OPTARG ;;
        *) echo "Usage: $0 [-v] [-o file]" >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))   # remaining arguments are now $1, $2...
```

---

## 3.4 Processing output of shell commands within a script

### Command substitution

`$(command)` runs a command and substitutes its **stdout**, with trailing newlines removed:

```bash
today=$(date +%F)                       # 2026-11-07
kernel=$(uname -r)
count=$(grep -c '^processor' /proc/cpuinfo)
uid=$(id -u "$user")
shell=$(getent passwd "$user" | cut -d: -f7)
echo "Backup of $(hostname) on $today"
```

The older backtick form `` `command` `` does the same but nests badly; use `$( )`. Quote the result when you
use it, `"$(cmd)"`, if it might contain spaces or be empty.

`getent passwd NAME` is the right way to look up a user: it consults every configured source (local files, and
LDAP or SSSD if configured), and its exit status is 0 if the user exists, 2 if not. Using it in an `if` is
cleaner than grepping `/etc/passwd`.

### Exit status: $?

`$?` holds the exit status of the most recently executed command. Read it **immediately**, because the next
command overwrites it:

```bash
cp "$src" "$dst"
rc=$?
if [ $rc -ne 0 ]; then
    echo "copy failed with status $rc" >&2
    exit $rc
fi
```

Usually you can write that more directly as `if ! cp "$src" "$dst"; then ...`. In a pipeline, `$?` is the
status of the last command; `set -o pipefail` makes it the status of the last command that failed.

`exit N` ends the script with status N. A script without `exit` returns the status of its last command, which
might accidentally be non-zero (for example a final `[ ... ] && echo` whose test was false). End scripts that
must report success with an explicit `exit 0`.

### Turning output into decisions and loops

```bash
# act on each line of a command's output
while read -r pid cmd; do
    echo "Killing $cmd ($pid)"
    kill "$pid"
done < <(pgrep -a -u baduser)

# counting and comparing
used=$(df --output=pcent / | tail -1 | tr -d ' %')
if [ "$used" -gt 90 ]; then
    logger -p user.warning -t diskcheck "root file system at ${used}%"
fi

# collecting results, then a summary line
n=0
while read -r f; do
    echo "$f"
    n=$((n + 1))
done < <(find "$dir" -type f -size +"${size}"k | sort)
echo "TOTAL $n"
```

Notice the pattern in the last example: produce a list with a tool (`find`), shape it with filters (`sort`),
process it line by line, and summarise. Most administrative scripts are variations on that.

### Functions (bonus)

Functions name a block of code, take arguments as `$1`, `$2` (their own, not the script's) and return a status
with `return N`:

```bash
user_exists() {
    getent passwd "$1" > /dev/null
}
if user_exists "$name"; then echo "yes"; fi
```

Use `local var=value` inside functions to avoid overwriting global variables.

### Safer scripts: set options

```bash
set -e            # exit on the first command that fails (with caveats in ifs, pipelines, &&)
set -u            # treat unset variables as an error (catches typos like $usre)
set -o pipefail   # a pipeline fails if any part fails
```

`set -euo pipefail` at the top is common in production scripts. It can surprise you (for example `grep`
returning 1 for "no match" kills the script), so for short exam scripts it is optional; explicit checks are
easier to reason about.

---

## Putting it together: a worked example

Task: *"Write `/usr/local/bin/mkusers.sh FILE`. For each non-blank, non-comment line of FILE, create the user
named on that line if they don't exist and print `created NAME`; otherwise print `exists NAME`. With no
argument, print a usage message to stderr and exit 2. If FILE isn't readable, exit 1."*

```bash
#!/bin/bash
# mkusers.sh: create users listed in a file
if [ $# -ne 1 ]; then
    echo "Usage: $(basename "$0") FILE" >&2
    exit 2
fi
file="$1"
if [ ! -r "$file" ]; then
    echo "$file: cannot read" >&2
    exit 1
fi

while read -r name; do
    [ -z "$name" ] && continue          # skip blank lines
    [[ $name == \#* ]] && continue      # skip comments
    if getent passwd "$name" > /dev/null; then
        echo "exists $name"
    else
        useradd "$name" && echo "created $name"
    fi
done < "$file"
exit 0
```

Then: `chmod +x /usr/local/bin/mkusers.sh`, `bash -n` it, and test the edge cases yourself before the grader
does: no argument (`echo $?` should be 2), a missing file, a file with a blank line, a comment and an existing
user. Running it twice should report `exists` for everyone the second time.

**Now practise:** [Lab 03](#/lab/03) has four scripts graded with hidden inputs, including a broken script with
syntax, quoting and path bugs to fix.

## Review questions

1. What does the kernel do with `#!/bin/bash`, and why should it be the very first line?
2. What is the difference between running `./script.sh` and `source script.sh`?
3. Why is `name = harry` an error, and what does bash try to do?
4. `dir=""; [ -d $dir ] && echo yes` prints `yes`. Explain, and fix it.
5. In `if grep -q x file; then`, what exactly is `if` testing?
6. What is wrong with `[ $count > 10 ]`? Give two correct versions.
7. Why does `for line in $(cat file)` misbehave, and what should you use instead?
8. Explain the difference between `"$@"`, `$@` and `"$*"` when an argument contains a space.
9. A script's error messages are mixed into the output file someone captures with `> out.txt`. What did the
   author forget?
10. A counter incremented inside `cat file | while read ...` is 0 after the loop. Why, and how do you fix it?
11. How do you make a script exit with status 2 and why might a grader care?
12. Which bash option shows each command after expansion as it runs?

<details><summary>Answers</summary>

1. It runs the named interpreter with the script path as its argument. The kernel only checks the first two
   bytes of the file, so anything before `#!` (even a blank line) defeats it.
2. `./script.sh` runs in a new child process; `source` runs the lines in the current shell, so variable and
   directory changes persist.
3. Spaces around `=` make it a command named `name` with arguments `=` and `harry`.
4. Unquoted, `$dir` vanishes, leaving `[ -d ]`, a one-argument test that is true because `-d` is a non-empty
   string. Use `[ -d "$dir" ]`.
5. The exit status of `grep -q`: 0 (true) if a line matched.
6. `>` is a redirection, creating a file named `10`. Use `[ "$count" -gt 10 ]` or `(( count > 10 ))`.
7. Command substitution output is split on all whitespace, not newlines, and globbed. Use
   `while read -r line; do ...; done < file`.
8. `"$@"` keeps each argument as one word; unquoted `$@` re-splits on spaces; `"$*"` joins all arguments into a
   single word.
9. To send errors to stderr with `>&2`.
10. Each part of a pipeline runs in a subshell, so the loop's variables vanish when it ends. Use
    `while ...; done < file` or `done < <(cmd)`.
11. `exit 2`. Graders check exit statuses as well as output, and callers (cron, other scripts) rely on them.
12. `bash -x script` or `set -x`.

</details>
