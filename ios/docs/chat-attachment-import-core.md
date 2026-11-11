# Chat attachment import core

This framework is not connected to the composer, picker, destination review or
model send. Construct `ChatAttachmentSelection` only from an explicit picker
callback. It retains a URL in memory, not a bookmark or file copy. `load()`
consumes the selection and returns a filename, actual byte count and kind after
validation. A ready session permits exactly one `take()`, which returns the
existing `ModelAttachment`; failures require a new selection/session.

Supported extensions are `.jpg`, `.jpeg`, `.png`, `.txt`, `.md`, `.csv` and
`.tsv`. The filename is bounded and rejects control/format characters. The
opened file must be a regular file, not a symlink, and match the originally
selected inode through the coordinated read. Files changed during that read or
replaced after the initial stat fail closed; selection is not a byte snapshot.
This strict identity rule may reject file providers that materialize by replacing
an inode; select again after materialization. The reader releases any obtained
security scope and does not create files. It enforces 5 MiB per image and 32 KiB
of UTF-8 text while reading; empty, NUL-containing or malformed text is refused.

For images the default ImageIO validator checks the MIME and container trailer,
requires one complete image, dimensions at most 8192 and 20 million pixels,
and decoded data at most 80 million bytes. It forces the image provider to
produce its complete pixel data and rasterizes the image. JPEG/PNG data after
the end marker is rejected, as are multi-frame images. The raster buffer may
require another 80 million bytes. These conservative bounds and format
restrictions may reject otherwise displayable files. They do not establish that
image content is safe or that a remote service supports it.

`discard()`, task cancellation and a 30-second maximum import deadline revoke
publication, cancel file coordination and discard the session's reference to
loaded data. A provider or synchronous decoder may ignore cancellation and finish
later; its late result cannot return to the session, but its work, security scope
and memory may persist until it returns. Swift values cannot guarantee memory
zeroing. After `take()`, the caller owns its copies and must clear them on send,
cancel, settings change, conversation change and failure; the session cannot
revoke copies already handed out. Production uses a fresh reader per session;
the injectable reader and image validator exist for deterministic tests.

The eventual host must bind review to the exact selection, prompt, model and
endpoint, disclose transmitted bytes and reference context, apply the model's
vision capability gate, protect drafts from unintended discard, and decide
whether/how to obtain the attachment again after an unsuccessful send. It must
not imply that a consumed attachment remains available in future turns. The
existing PDF path remains separate.

Run `python3 ios/scripts/check_chat_attachment_import.py`. It compiles the real
core using `swiftc` and exercises synthetic files, ImageIO and a local file
coordinator, plus controlled stalled providers/decoders. It does not test the
iOS picker, third-party file providers, app lifecycle, network or UI. Those and
iOS SDK/device-specific behavior need Xcode/simulator or device validation.
