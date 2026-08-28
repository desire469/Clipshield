# Mask the clipboard, not the screen or the file

The original request was to "replace credentials in certain files", which reads as hiding Secrets
on screen or on disk. We deliberately do neither: Secrets stay fully visible while editing and the
file on disk is never touched. Masking happens at exactly one point — when text is written to the
system clipboard — because the actual risk being addressed is pasting a Secret into a chat window,
not seeing it in one's own editor.

## Considered Options

- **Render-level masking (conceal + extmarks).** Hides Secrets on screen behind Placeholders.
  Rejected: it protects against onlookers but not against pasting, and it fights the user, who
  needs to read and edit these values constantly.
- **Disk-level masking with a vault.** The file holds Placeholders and real values live encrypted
  elsewhere. Rejected: this is a secret-management product, not an editor plugin. It breaks every
  other tool that reads the file, and a bug in it loses data.
- **Clipboard-level masking.** Chosen. The buffer, the file and the screen keep working exactly as
  before; only what leaves the editor changes.

## Consequences

- Text selected with the terminal's own mouse selection never passes through Neovim and is
  therefore never Masked. The plugin cannot close this hole, and the README must say so plainly —
  a user who believes they are protected while dragging with the mouse is worse off than one who
  knows they are not.
- Only the system clipboard is intercepted. The unnamed register keeps the true value, so ordinary
  in-buffer editing (`yy`, `p`) is unaffected.
- Because nothing is hidden on screen, there is no reveal toggle and no state to get stuck in.
