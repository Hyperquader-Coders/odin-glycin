# MoSCoW — odin-glycin

Prioritisation by **Must / Should / Could / Won't have** (the lower-case Os just make it
pronounceable). This is the **scope** document, and it holds only what is **still open**: an
item leaves this file the moment it ships. Nothing here records work done — `git log` is for
that.

An empty band means that band is finished, not that it was never populated.

## Must have

## Should have

- **Skip, do not fail, where bubblewrap is refused.** `GLYCIN_DISABLE_SANDBOX` and
  `SandboxSelector.NOT_SANDBOXED` are bound but untested: CI hosts that forbid unprivileged user
  namespaces (some containers) cannot run `make test`. Found while writing the tests; a test
  that detects bubblewrap refusal and says so, as amber-glycin's `scripts/smoke` does, would turn a
  red CI into a clear skip.
- **Wrap the error-code idiom.** Every caller of `loader_load` and `image_next_frame` repeats
  `error_matches(err, LOADER_ERROR(), NO_MORE_FRAMES)`. A small `glycin` helper (or a note in a
  consumers' guide) would keep the SVG-never-ends and PNG-second-frame-fails rules in one place.

## Could have

- **Test the editor operations once a consumer needs them.** The headers of 2.2.1 bind only the
  creator; the loader configs list editor operations (clip, rotate, mirror) with no C API.
  Revisit when a glycin release exposes them.
- **Pin the glycin error domain to a constant.** A missing file arrives as `LOADER_ERROR` /
  `FAILED`, not `G_IO_ERROR_NOT_FOUND`; a consumer cannot tell it from a decoder failure except by
  message text. Report upstream or document in the consumers' guide.

## Won't have (this time)
