# Python stdlib equivalents for common bash patterns

Loaded on demand from `platform-quirks-escape`. Each entry is the bash pattern, the platform-quirk it carries, and the Python stdlib equivalent that sidesteps it.

## File and directory operations

| Bash | Quirk | Python |
|---|---|---|
| `for f in *.txt; do ...; done` | Empty-glob behaviour (nullglob option needed) | `for f in Path('.').glob('*.txt'):` |
| `find . -name '*.md' -type f` | `find` flag differences (BSD vs GNU) | `for f in Path('.').rglob('*.md'):` |
| `cp src dst` | BSD `cp -R` vs GNU `cp -r` | `shutil.copy(src, dst)` / `shutil.copytree(src, dst)` |
| `mv src dst` | Cross-device rename quirks | `shutil.move(src, dst)` |
| `rm -rf dir` | BSD `rm` does not have `--no-preserve-root` | `shutil.rmtree(dir)` |
| `mkdir -p path` | `-p` portable but spelling varies | `Path(path).mkdir(parents=True, exist_ok=True)` |
| `stat -c %s file` (GNU) / `stat -f %z file` (BSD) | Different flag syntax | `Path(file).stat().st_size` |

## Path manipulation

| Bash | Quirk | Python |
|---|---|---|
| `"$dir/$file"` | Trailing-slash and Windows backslash issues | `Path(dir) / file` |
| `basename "$path"` | Edge-case with trailing slash | `Path(path).name` |
| `dirname "$path"` | Edge-case with trailing slash | `Path(path).parent` |
| `${file%.*}` (strip extension) | Bash 4+ on some forms | `Path(file).stem` |
| `${file##*.}` (just extension) | Bash 4+ on some forms | `Path(file).suffix` |
| `realpath "$path"` (GNU only) | Missing on BSD without coreutils | `Path(path).resolve()` |

## Process invocation

| Bash | Quirk | Python |
|---|---|---|
| `cmd arg1 "$arg with space"` | Quoting hell across shells | `subprocess.run(['cmd', 'arg1', arg_with_space])` |
| `output=$(cmd)` | Trailing-newline strip behaviour | `output = subprocess.check_output(['cmd']).decode().rstrip('\n')` |
| `cmd1 \| cmd2` | Exit-status of pipeline; `pipefail` needed | `p = subprocess.run(['cmd1'], capture_output=True); subprocess.run(['cmd2'], input=p.stdout)` |
| `cmd > file 2>&1` | Redirection works but cross-shell quirks | `subprocess.run(['cmd'], stdout=open('file', 'w'), stderr=subprocess.STDOUT)` |
| `command -v tool` | Some shells use `which` (deprecated POSIX) | `shutil.which('tool')` |
| `cmd && other_cmd` | Exit-status semantics | `subprocess.run(['cmd'], check=True); subprocess.run(['other_cmd'], check=True)` |

## Environment variables

| Bash | Quirk | Python |
|---|---|---|
| `${VAR:-default}` | Portable, but cluttered when many | `os.environ.get('VAR', 'default')` |
| `${VAR:?required}` | Portable | `os.environ['VAR']` (raises KeyError if missing) |
| `export VAR=val; cmd` | Subshell scoping | `subprocess.run(['cmd'], env={**os.environ, 'VAR': 'val'})` |
| `${VAR^^}` (uppercase) | Bash 4+ only | `os.environ['VAR'].upper()` |
| `unset VAR` | Portable | `os.environ.pop('VAR', None)` |

## String manipulation

| Bash | Quirk | Python |
|---|---|---|
| `${str/foo/bar}` | Bash 4+ for global form (`${str//foo/bar}` always) | `str.replace('foo', 'bar')` |
| `${str:0:5}` | Bash 4+ on some forms | `str[:5]` |
| `${#str}` | Counts bytes, not chars (UTF-8 issues) | `len(str)` (counts chars) |
| `[[ "$str" =~ regex ]]` | BRE vs ERE vs PCRE differences | `re.search(regex, str)` |
| `echo "$str" \| tr 'a-z' 'A-Z'` | Locale-dependent | `str.upper()` |

## JSON

| Bash | Quirk | Python |
|---|---|---|
| `jq '.foo' file` | jq must be installed | `json.load(open('file'))['foo']` |
| `jq -r '.list[]' \| while read item; do ...; done` | Whitespace-in-values bugs | `for item in json.load(open('file'))['list']: ...` |
| `jq -n --arg k v '{key: $v}'` | Quoting nightmare | `json.dumps({'key': v})` |

## HTTP

| Bash | Quirk | Python |
|---|---|---|
| `curl -fsSL url \| sh` | Insecure pattern; curl flags vary | `urllib.request.urlopen(url).read()` |
| `curl -X POST -d @file url` | Curl flag-set varies; quoting | `urllib.request.urlopen(url, data=open('file', 'rb').read())` |
| `curl -H "Auth: ..." -u user:pass url` | Header quoting; secrets in args | `req = urllib.request.Request(url, headers={'Auth': '...'}); urllib.request.urlopen(req)` |

For richer HTTP (retries, sessions, JSON helpers), `requests` if available; otherwise stdlib `urllib`.

## Collections

| Bash | Quirk | Python |
|---|---|---|
| `arr=(a b c); echo "${arr[1]}"` | One-dim only; quoting issues | `arr = ['a', 'b', 'c']; arr[1]` |
| `declare -A m; m[k]=v` | Bash 4+; fails on macOS 3.2 | `m = {'k': 'v'}` |
| `for k in "${!m[@]}"; do ...; done` | Bash 4+ | `for k, v in m.items(): ...` |
| `arr+=("$x")` (append) | Portable, but ugly | `arr.append(x)` |
| `${#arr[@]}` | Counts elements | `len(arr)` |
| Sort, unique, count | Pipe through `sort -u`, `sort \| uniq -c` | `sorted(set(arr))`, `collections.Counter(arr)` |

## Date and time

| Bash | Quirk | Python |
|---|---|---|
| `date +%Y-%m-%d` | BSD vs GNU `date` differ | `datetime.date.today().isoformat()` |
| `date -u +%FT%TZ` | BSD vs GNU; cross-link to `utc-timestamps` | `datetime.datetime.now(datetime.UTC).strftime('%FT%TZ')` |
| `date -d '+1 day'` (GNU) / `date -v+1d` (BSD) | Hard divergence | `datetime.date.today() + datetime.timedelta(days=1)` |

## Temporary files

| Bash | Quirk | Python |
|---|---|---|
| `mktemp` | BSD vs GNU template syntax | `tempfile.NamedTemporaryFile(delete=False)` |
| `trap 'rm -f $tmp' EXIT` | Easy to forget; quirks across shells | `with tempfile.NamedTemporaryFile() as tmp: ...` (auto-cleans) |

## Bottom line

If you find yourself in this cheatsheet looking up more than 2-3 patterns to translate a single script, the script wanted to be Python from the start. Rewrite, do not patch.
