#!/bin/bash
# Tests for wisp. Run from the repository root:
#
#   ./test.sh
#
# Each case covers a fault a review found. A test that fails means a fix came
# out. No framework: the checks are greps over the rendered page, and the
# viewer is replaced by a stub so nothing opens a window.
set -u

cd "$(dirname "$0")"
here=$(pwd)
pass=0; fail=0
tmp=$(mktemp -d -t wisp-test)
trap 'rm -rf "$tmp"; [ -e "$here/wispview.real" ] && mv "$here/wispview.real" "$here/wispview"' EXIT INT TERM

ok()  { printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
no()  { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }

# The stub writes the page where a test can read it, instead of opening a window.
[ -e wispview ] && mv wispview wispview.real
printf '#!/bin/sh\ncat > %s/out.html\n' "$tmp" > wispview
chmod +x wispview
render() { ./wisp "$1" >"$tmp/stdout" 2>"$tmp/stderr"; }
page()   { cat "$tmp/out.html" 2>/dev/null; }

echo "rendering"

printf '# Title\n\nSome `code` and a list:\n\n- a\n- b\n' > "$tmp/doc.md"
render "$tmp/doc.md"
page | grep -q '<h1[^>]*>Title</h1>' && ok "markdown renders a heading" || no "markdown renders a heading"
page | grep -q '<code>code</code>'   && ok "markdown renders inline code" || no "markdown renders inline code"

printf 'package main\n\nfunc main() { println("hi") }\n' > "$tmp/a.go"
render "$tmp/a.go"
page | grep -q 'class="linenos"' && ok "source gets line numbers" || no "source gets line numbers"
page | grep -q 'prefers-color-scheme: dark' && ok "a dark theme is included" || no "a dark theme is included"

printf 'a: 1\nb:\n  - x\n' > "$tmp/a.yaml"
render "$tmp/a.yaml"
page | grep -q 'class="nt"' && ok "yaml is highlighted" || no "yaml is highlighted"

printf 'just words\n' > "$tmp/a.log"
render "$tmp/a.log"
page | grep -q 'class="plain"' && ok "an unknown type falls back to plain text" || no "an unknown type falls back to plain text"

echo "refusing"

printf '\x89PNG\x0d\x0a\x1a\x0a\x00\x01' > "$tmp/a.png"
render "$tmp/a.png"
grep -q 'binary file' "$tmp/stderr" && ok "a binary file is refused" || no "a binary file is refused"

echo "injection"

# A file name is legal markup. It must reach the page as text.
printf '# hi\n' > "$tmp/<img src=x onerror=alert(1)>.md"
render "$tmp/<img src=x onerror=alert(1)>.md"
page | grep -q '<img src=x onerror' && no "a file name is escaped" || ok "a file name is escaped"
page | grep -q '&lt;img src=x onerror' && ok "the escaped name still shows as text" || no "the escaped name still shows as text"

# python puts the current directory on sys.path. A markdown.py beside the file
# must not be imported in place of the real module.
mkdir -p "$tmp/hijack"
printf 'import sys; sys.stderr.write("HIJACKED\\n")\n' > "$tmp/hijack/markdown.py"
printf '# t\n' > "$tmp/hijack/a.md"
rm -f "$tmp/out.html"
( cd "$tmp/hijack" && "$here/wisp" a.md >/dev/null 2>"$tmp/hj" )
# Assert the real module ran, not that the fake one stayed quiet. wisp sends the
# converter's stderr to /dev/null, so a hijacked run is silent and simply
# renders nothing. The proof is a real heading in the page.
page | grep -q '<h1[^>]*>t</h1>' && ok "python runs isolated" || no "python runs isolated"

# The page must carry the policy that protects the QuickLook path.
render "$tmp/doc.md"
page | grep -q "default-src 'none'" && ok "the page sets a content security policy" || no "the page sets a content security policy"

# A dash-leading name must not become an option to pygmentize.
printf 'x = 1\n' > "$tmp/-O,full,x.py"
render "$tmp/-O,full,x.py"
page | grep -q 'class="linenos"' && ok "a dash-leading name is not an option" || no "a dash-leading name is not an option"

# The heredoc is unquoted, so a backtick in the template is a command.
grep -n '`' wisp | awk -F: '$1 > 80 && $1 < 145' | grep -q . \
  && no "no backtick inside the HTML template" || ok "no backtick inside the HTML template"

echo "viewer"

if [ -x wispview.real ]; then
  grep -q 'allowsContentJavaScript = false' wispview.swift && ok "javascript is off in the viewer" || no "javascript is off in the viewer"
  grep -q 'WKNavigationDelegate' wispview.swift && ok "the viewer restricts navigation" || no "the viewer restricts navigation"
  printf '<meta http-equiv="refresh" content="0;url=https://example.com/x"><h1>p</h1>' \
    | ./wispview.real "test" --selftest 2>"$tmp/nav" >/dev/null
  grep -q 'blocked navigation' "$tmp/nav" && ok "a meta refresh is blocked" || no "a meta refresh is blocked"
else
  printf '  --    viewer tests skipped, wispview is not built\n'
fi

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
