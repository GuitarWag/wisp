# wisp

Read a file in a native macOS window. Close it and nothing remains.

```sh
wisp NOTES.md
wisp cmd/server/main.go
wisp deploy.yaml
```

Escape or Cmd-W closes it.

## Why

An agent writes a document and you want to read it, not edit it. An editor tab
means a buffer to open, a split to size and a buffer to close. A pager keeps the
text in the terminal, where it competes with the scrollback you still need.

`wisp` puts the document in its own window, renders it properly, and leaves
nothing behind.

## Install

Needs macOS. Needs `pygmentize` and the Python `markdown` module. Builds a small
Swift viewer when `swiftc` is present, and falls back to QuickLook when it is
not.

```sh
git clone git@github.com:GuitarWag/wisp.git
cd wisp
./install.sh        # build the viewer, link into ~/.local/bin, verify
./install.sh check  # verify only
```

```sh
pipx install pygments
pip install markdown
```

## Formats

Markdown renders through `python3 -m markdown`, with fenced code, tables and
anchors.

Everything else goes to Pygments, which picks the lexer from the file name:

```
js jsx ts tsx json yaml toml rust go python ruby java c cpp swift kotlin
sql lua proto terraform css html xml sh bash zsh make diff
```

It also reads names with no extension, such as `Dockerfile` and `Makefile`.

A file Pygments does not recognise, such as `.txt` or `.log`, still opens as
plain wrapped text. A binary file is refused. The check asks `file` for the
encoding, because Pygments reports a PNG and a text file the same way.

Source files carry line numbers in a separate table cell, so a copied selection
holds the code alone. Prose sits at 46em and source at 72em. Colours follow the
system setting: the Pygments `default` theme in light mode, `github-dark` in
dark.

## How it works

The file renders to HTML, and a window shows it.

**wispview**, the Swift program in this repository, is preferred. It reads the
page on standard input, so nothing reaches the disk at any point, and it turns
JavaScript off in the web view itself.

**QuickLook** is the fallback when there is no Swift compiler. That path writes
the page to a temporary directory, because `qlmanage` needs a file, and deletes
it when the window closes. `qlmanage -p` holds the shell until then, so the
cleanup runs at the right moment, and the trap covers Ctrl-C and `TERM` too.

The source file is read only in both cases.

## Safety

`wisp` opens files that somebody else wrote, so it treats the content as
hostile. python-markdown copies raw HTML from the source into its output, which
means a markdown file can carry a script tag or an inline event handler.

Five things stop that, and all five should stay:

- wispview allows the first in-memory load and refuses every navigation after
  it. A markdown file can hold a `<meta http-equiv="refresh">`, which needs no
  JavaScript and which no Content Security Policy covers. Without this the
  window would quietly load a remote page. A click on a real link opens the
  browser instead, where you can see where you are going.
- wispview sets `allowsContentJavaScript = false`, so the engine will not run a
  script at all. It passes `baseURL: nil`, so the page reaches neither the file
  system nor the network.
- The page sets a Content Security Policy of `default-src 'none'`. That is what
  protects the QuickLook path, which has no engine switch.
- `wisp` escapes the file name before writing it into the page. A name such as
  `<img src=x onerror=...>.md` is legal on disk.
- Markdown runs through `python3 -I`. Without `-I` the current directory sits on
  `sys.path`, so a `markdown.py` in whatever directory you happen to be in is
  imported and run in place of the real module.

Both file arguments pass after `--`, so a name that starts with a dash cannot
become a command option.

Do not write a backtick into the HTML template in `wisp`. The heredoc is
unquoted, so bash reads a backtick as a command.

## Limits

- It takes a path. It does not read standard input.
- macOS only. It depends on QuickLook or on AppKit.

## Licence

MIT. See [LICENSE](LICENSE).
