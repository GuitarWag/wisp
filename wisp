#!/bin/bash
# wisp - read a file in a native macOS window, then leave nothing behind.
#
# Renders the file to HTML, shows it in QuickLook, and deletes the rendered
# copy when you close the window. The original file is never touched.
#
#   wisp NOTES.md
#   wisp main.go
#
# Close with Escape, Space or the window button. QuickLook blocks until then,
# which is what triggers the cleanup, so there is no timer and no stray file.
#
# Supports: md, markdown, ts, tsx, py, sh, bash, go.
set -eu

src=${1:-}
if [ -z "$src" ] || [ ! -f "$src" ]; then
  echo "usage: wisp <file>   (md, ts, py, sh, go)" >&2
  exit 2
fi

command -v qlmanage >/dev/null || { echo "wisp needs qlmanage (macOS only)" >&2; exit 1; }

# A file name goes into the page, so escape it. A name like
# "<img src=x onerror=...>.md" is a legal file name and would otherwise become
# live markup in the window.
esc() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'; }

ext=${src##*.}
base=$(basename "$src")

# Refuse binary input. Pygments reports "text" for a PNG as readily as for a
# .txt file, so ask the file itself instead of trusting the extension.
case "$(file --mime-encoding -b -- "$src" 2>/dev/null)" in
  binary) echo "wisp: $base is a binary file." >&2; exit 2 ;;
esac

dir=$(mktemp -d -t wisp)
tmp="$dir/${base%.*}.html"
# Delete the render on every exit path: normal close, Ctrl-C, or kill.
trap 'rm -rf "$dir"' EXIT INT TERM

# Two themes, chosen by the system setting. Pygments emits one flat stylesheet
# per style, so each one goes inside its own media query.
pygcss() {
  command -v pygmentize >/dev/null 2>&1 || return 0
  printf '@media (prefers-color-scheme: light) { %s }\n' "$(pygmentize -f html -S default -a .highlight 2>/dev/null)"
  printf '@media (prefers-color-scheme: dark) { %s }\n'  "$(pygmentize -f html -S github-dark -a .highlight 2>/dev/null)"
}

css=""
WIDTH=72em   # source reads better wide
case "$ext" in
  md|markdown)
    command -v python3 >/dev/null || { echo "wisp needs python3 for markdown" >&2; exit 1; }
    # -I runs python isolated. Without it the current directory is on sys.path,
    # so a markdown.py sitting in the directory you happen to be in is imported
    # and run instead of the real module.
    # codehilite runs fenced code through pygments, so a doc full of snippets
    # reads the same as a source file does.
    body=$(python3 -I -m markdown -x fenced_code -x codehilite -x tables -x toc -- "$src" 2>/dev/null) \
      || body=$(python3 -I -m markdown -- "$src")
    WIDTH=46em  # prose reads better narrow
    css=$(pygcss)
    ;;
  *)
    command -v pygmentize >/dev/null || { echo "wisp needs pygmentize for source files" >&2; exit 1; }
    # Let pygments pick the lexer from the name. It knows js, json, yaml, toml,
    # rust, sql, lua, proto, terraform, css, html, swift, ruby, java, c, and
    # extensionless names such as Dockerfile and Makefile.
    lexer=$(pygmentize -N "$src" 2>/dev/null || echo text)
    if [ "$lexer" = "text" ]; then
      # Not a language pygments knows. Show it as plain text rather than refuse:
      # a .txt, a .log or a .env still reads better in a window than in a pager.
      body="<pre class=\"plain\">$(esc "$(cat -- "$src")")</pre>"
    else
      # Line numbers make a window of code navigable. The table form keeps them
      # out of a copied selection.
      body=$(pygmentize -f html -O "linenos=table,lineanchors=L" -l "$lexer" -- "$src")
      css=$(pygcss)
    fi
    ;;
esac

render() {
cat <<HTML
<!doctype html><meta charset="utf-8">
<!-- QuickLook renders this with WebKit, and python-markdown copies raw HTML
     from the source file into the output. A markdown file can therefore carry
     a script tag or an inline event handler. This policy blocks both, and
     blocks any request off the machine. Keep it: wisp exists to read files
     that somebody else wrote. -->
<meta http-equiv="Content-Security-Policy"
      content="default-src 'none'; style-src 'unsafe-inline'; img-src data:;">
<title>$(esc "$(basename "$src")")</title>
<style>
  :root { color-scheme: light dark; --fg:#1d1d1f; --bg:#fff; --mut:#6e6e73; --line:#e5e5ea; --code:#f5f5f7; }
  @media (prefers-color-scheme: dark) {
    :root { --fg:#f5f5f7; --bg:#1c1c1e; --mut:#98989d; --line:#38383a; --code:#2c2c2e; }
  }
  body { margin:0; padding:48px 56px 72px; background:var(--bg); color:var(--fg);
         font:16px/1.65 -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
         max-width:$WIDTH; -webkit-font-smoothing:antialiased; }
  h1,h2,h3,h4 { line-height:1.25; margin:1.8em 0 .6em; font-weight:600; }
  h1 { font-size:1.9em; margin-top:0; } h2 { font-size:1.45em; } h3 { font-size:1.2em; }
  p,li { margin:.6em 0; } a { color:#0071e3; }
  code { font:13.5px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace;
         background:var(--code); padding:.15em .4em; border-radius:4px; }
  pre { background:var(--code); padding:16px 18px; border-radius:8px; overflow-x:auto; }
  pre code, .highlight pre { background:none; padding:0; }
  .highlight { background:var(--code); border-radius:8px; padding:16px 18px; overflow-x:auto; }
  .highlight pre { margin:0; font:13.5px/1.55 ui-monospace, SFMono-Regular, Menlo, monospace; }
  blockquote { margin:1em 0; padding-left:1em; border-left:3px solid var(--line); color:var(--mut); }
  table { border-collapse:collapse; margin:1.2em 0; font-size:.95em; }
  th,td { border:1px solid var(--line); padding:.45em .8em; text-align:left; }
  th { background:var(--code); font-weight:600; }
  hr { border:0; border-top:1px solid var(--line); margin:2em 0; }
  .wisp-name { color:var(--mut); font-size:12px; letter-spacing:.04em;
               text-transform:uppercase; margin-bottom:28px; }
  /* Line numbers come as a two-cell table so that a copied selection holds the
     code alone. The number cell does not wrap and does not select. */
  .highlighttable { border:0; width:100%; margin:0; }
  .highlighttable td { border:0; padding:0; vertical-align:top; }
  .highlighttable td.linenos { width:1%; padding-right:14px; text-align:right;
                               color:var(--mut); user-select:none; -webkit-user-select:none; }
  .highlighttable td.code { width:99%; }
  .linenos pre, .code pre { margin:0; }
  pre.plain { white-space:pre-wrap; word-break:break-word; }
  /* A long line scrolls inside the block rather than widening the window. */
  .highlight, .highlighttable { max-width:100%; overflow-x:auto; }
  $css
  /* After the pygments sheet, which hardcodes a background on the line-number
     cell and sets a bare pre rule. Both fight the page, so restate them.
     Do not write a backtick in here: the heredoc is unquoted, so bash reads it
     as a command. */
  .highlighttable td.linenos, .highlighttable td.linenos .normal,
  .highlighttable td.linenos .special { background:none; border:0; padding-left:0; }
  .highlight pre, .highlighttable pre { line-height:1.55; }
</style>
<div class="wisp-name">$(esc "$(basename "$src")")</div>
$body
HTML
}

# wispview is the preferred viewer. It takes the page on stdin, so nothing
# reaches the disk, and it turns JavaScript off in the web view itself rather
# than relying on the page's own policy. QuickLook is the fallback for a
# machine with no Swift toolchain.
viewer="$(dirname "$(readlink "$0" 2>/dev/null || echo "$0")")/wispview"

if [ -z "${body:-}" ]; then
  echo "wisp: $src produced no output. The converter may have failed." >&2
  exit 1
fi

if [ -x "$viewer" ]; then
  render | "$viewer" "$base" || { echo "wisp: the viewer failed to open." >&2; exit 1; }
else
  # QuickLook needs a file, so this path writes one and deletes it on exit.
  render > "$tmp"
  if ! qlmanage -p "$tmp" >/dev/null 2>"$dir/err"; then
    echo "wisp: quicklook could not open the render." >&2
    [ -s "$dir/err" ] && sed 's/^/  /' "$dir/err" >&2
    exit 1
  fi
fi
