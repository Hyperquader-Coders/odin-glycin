# MoSCoW: odin-glycin

Prioritisation by **Must / Should / Could / Won't have** (the lower-case Os just make it
pronounceable). This is the **scope** document, and it holds only what is **still open**: an
item leaves this file the moment it ships. Nothing here records work done: `git log` is for
that.

An empty band means that band is finished, not that it was never populated.

## Must have

- nada

## Should have

- **Skip, do not fail, where bubblewrap is refused.** `GLYCIN_DISABLE_SANDBOX` and
  `SandboxSelector.NOT_SANDBOXED` are bound but untested, and CI hosts that forbid unprivileged
  user namespaces (some containers) cannot run `make test`. A test that detects the refusal and
  says so, as amber-glycin's `scripts/smoke` does, turns a red CI into a clear skip.
- **A helper for the end-of-frames check.** Every caller of `loader_load` and `image_next_frame`
  repeats `error_matches(err, loader_error_quark(), NO_MORE_FRAMES)`. A small `glycin` procedure
  would keep the SVG-never-ends and PNG-second-frame-fails rules in one place in code; the README
  and the cheat sheet state them for readers.

## Could have

- **Test the editor operations once a consumer needs them.** The headers of 2.2.1 bind only the
  creator; the loader configs list editor operations (clip, rotate, mirror) with no C API.
  Revisit when a glycin release exposes them.
- **Report the missing-file error upstream.** A missing file arrives as `LOADER_ERROR` /
  `FAILED`, not `G_IO_ERROR_NOT_FOUND`, so a consumer cannot tell it from a decoder failure except
  by the message text. The README states it; glycin itself would need a distinct code.

## Won't have (this time)

- nada
