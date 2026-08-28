# clipshield.nvim

Keeps secrets out of your clipboard. ([По-русски](README.ru.md))

You keep a list of values you never want to paste anywhere — API keys, tokens, passwords. They stay
fully visible while you edit, and your files are never modified. The moment you copy text to the
**system clipboard**, any of those values in it are substituted for a placeholder.

When you add a value you say what it should read as. Give a hostname a fake hostname and your logs
still make sense to you; say nothing and it becomes `REDACTED1`, `REDACTED2`, numbered so that two
different secrets never look like the same one.

```
# in your editor                          # in your clipboard
OPENAI_KEY=sk-proj-Ab3xK9zzQq             OPENAI_KEY=REDACTED1
GH_TOKEN=ghp_7fQ2mLwPd                    GH_TOKEN=REDACTED2
error.log  mysite.example                 error.log  site1.internal
```

Paste that into a chat window, an issue, a message to a colleague — the keys are not in it.

## What it does not protect against

**Selecting text with the mouse in your terminal does not go through Neovim, and is not masked.**
Your terminal copies straight from its own screen buffer; the plugin never sees it. If you copy by
dragging with the mouse, this plugin does nothing for you at all. Copy with `y` from Neovim, or
don't rely on it.

It also does not hide anything on screen, does not touch your files, and does not scan for things
that merely *look* like secrets — a value is masked because you added it, never because it was
guessed. See [docs/adr/0001-mask-clipboard-only.md](docs/adr/0001-mask-clipboard-only.md) for why.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "desire469/Clipshield" }
```

No `setup()` call is needed — it works as soon as it is installed.

## Use

| Mapping        | Mode   | Does                                                    |
| -------------- | ------ | ------------------------------------------------------- |
| `<leader>sa`   | visual | Add the selection, asking what it should read as        |
| `<leader>sA`   | visual | Add the selection with the default placeholder, no questions |
| `<leader>sy`   | visual | Copy the selection **unmasked**, when the key is the point |
| `<leader>sl`   | normal | Open the watchlist as an ordinary buffer                |
| `<leader>sd`   | normal | Pick an entry to remove                                 |

Same things as commands: `:ClipshieldAdd` and `:ClipshieldAddDefault` (with a range), `:YankRaw`
(with a range), `:ClipshieldList`, `:ClipshieldDelete`.

Editing the list *is* opening the file. It is a normal buffer: change a line, delete one with `dd`,
add one by hand, `:w`. Changes take effect on the next copy.

## The watchlist

One JSON object per line, at `stdpath("data")/clipshield/watchlist.jsonl`. Blank lines and lines
starting with `#` are ignored, so you can leave yourself notes.

```
# work
{"value":"mysite.example","replacement":"site1.internal"}
{"value":"sk-proj-Ab3xK9zzQq"}
```

`replacement` is what the value reads as when copied; leave it out for the numbered default.

**This file holds your real keys, in the clear.** That is unavoidable — matching them in copied text
means knowing what they are. Treat it like any other file full of secrets.

Matching is exact and case-sensitive, anywhere in a line — including inside a URL such as
`https://user:PASSWORD@host`. Entries may span several lines, so a whole PEM key works. Where two
entries overlap, the longer one wins, so a short entry can never chop a longer key in half and leak
the remainder. Entries shorter than 8 characters are refused: they would match half your code.

If a line in the file is not valid, that line is skipped, the rest keep working, and you get a loud
error every time you copy until it is fixed. Silently masking nothing is the one failure this plugin
must never do quietly.

## Configuration

Defaults, all optional:

```lua
require("clipshield").setup({
  watchlist = vim.fs.joinpath(vim.fn.stdpath("data"), "clipshield", "watchlist.jsonl"),
  placeholder = "REDACTED",  -- entries without their own replacement use this plus a number
  min_length = 8,         -- refuse to add anything shorter
  keymaps = true,         -- false to bind everything yourself
  prefix = "<leader>s",
})
```

Only the system clipboard (`+`, `*`) is ever rewritten. The unnamed register keeps the true value,
so `yy` and `p` inside Neovim behave exactly as they always have.
