# Chat attachment model contract (model layer only)

This stage supplies a transient model input, not file selection, a chat UI,
persistence, a workspace or an end-to-end attachment flow. No app code creates
these attachments yet. A future host must obtain bytes from an explicit user
selection, validate/decode images before preview or sending, disclose the exact
model destination and transmitted data, and handle cancellation, cleanup,
errors and any later re-selection. It must not treat the data as authorization.

- `ModelAttachment.image` accepts JPEG or PNG, matching the declared MIME and
  signature, from 1 byte up to 5 MiB. The marker check is not a full image
  decoder. `text(utf8:)` accepts nonempty, strictly valid UTF-8 without NUL,
  up to 32 KiB. Neither input is silently truncated or repaired.
- `ModelMessage(userText:attachment:)` is transient and refuses generic Codable
  encoding, to avoid accidentally placing bytes in an archive. The request
  serializer accepts at most one attachment, only on the final user message;
  it rejects replay in history. Attachment requests have at most 32 messages
  and at most 8 MiB of actual encoded JSON. Plain text requests keep their
  existing shape and limits.
- Images require a host declaration of `.supported` for the exact configured
  service and model. `.unknown` is the default and both unknown and unsupported
  fail before network I/O. A declaration is not proof of provider support;
  service-side rejection remains possible. The host is responsible for binding
  the declaration and any user consent to the actual destination.
- The OpenAI-compatible wire format uses a text part plus `image_url` data URL,
  or two text parts for a text attachment, marked as untrusted data. This marker
  does not enforce model behavior. A provider receives the complete attachment
  and prompt, and may have stricter limits or a different protocol.
- Both complete and streaming use the same builder. Errors do not expose bytes,
  text, credentials or endpoint. The host must surface errors and cannot assume
  that this layer has implemented UI, storage, consent or retry behavior.

Run `python3 ios/scripts/check_model_attachments.py` from the repository root.
The standalone checks compile the actual model client with `swiftc`, inspect its
constructed HTTP JSON and do not contact a server. Full SDK and iOS simulator
validation remains necessary when integrating the app flow.
