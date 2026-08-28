# clipshield.nvim

Standalone Neovim plugin. Secrets stay fully visible while editing; they are substituted for
neutral placeholders only at the moment text is copied out of the editor into the system clipboard.

## Language

**Secret**:
A concrete string value that must not leave the editor — an API key, token, password or similar.
_Avoid_: cred, credential, password (too narrow)

**Watchlist**:
The set of Secrets the plugin knows about. Single and machine-global; there is no per-project one.
Membership is explicit — a value is a Secret because the user added it, never because it looked
like one.
_Avoid_: blacklist, blocklist, list, dictionary

**Match**:
A region of copied text that equals an entry in the Watchlist.
_Avoid_: hit, occurrence, finding

**Placeholder**:
The text substituted for a Match. A Secret may carry its own, chosen when it was added, so that
copied text stays readable — a hostname can read as another hostname. A Secret without one falls
back to the numbered default, `REDACTED1`, `REDACTED2`, numbered within a single copy so that
distinct Secrets stay distinguishable.
_Avoid_: replacement, stub, redaction, label, mask (the noun)

**Mask**:
To substitute a Match for its Placeholder in text on its way to the system clipboard.
Never alters the buffer, the file, or what is shown on screen.
_Avoid_: hide, redact, conceal, censor

**Raw Yank**:
A deliberate, separately-bound copy that skips Masking, for when the true Secret is the point.
_Avoid_: unmask, reveal, copy-real

## Settled boundaries

- Masking applies only to the system clipboard. The unnamed register, the buffer and the file on
  disk are never touched.
- Text selected with the terminal's own mouse selection never reaches the plugin and is never Masked.
- The Watchlist is stored in plain text and holds the real Secret values, since substring matching
  makes hashed storage impossible.
- No shape-based detection and no LSP in v1. Matching is literal, case-sensitive, anywhere in the
  line, minimum 8 characters.
