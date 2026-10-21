# Storyboard

A native macOS prototype for making color sketch storyboard frames locally.

## Current scope

- Editable, reorderable storyboard frames with a camera framing selector.
- A local Qwen3 0.6B prompt normalizer followed by FLUX.2 Klein 4B generation.
- A private sketch style LoRA, four denoising steps, and 1024×576 output.
- Automatic `.sketchboard` document saving through the macOS document system, plus PNG export.
- Models are downloaded once and cached locally.  No prompts or images are sent to a generation service.

Screenplay import and character continuity are not implemented in this first prototype.

## Build

Requires Apple Silicon, macOS 15+, Xcode with a Swift 6.3+ toolchain, and XcodeGen.

```sh
xcodegen generate
xcodebuild -project Storyboard.xcodeproj -scheme Storyboard -configuration Release -derivedDataPath build -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO build
```

The private adapter must be present at `Resources/StoryboardStyle.safetensors` before building.  It is supplied with the local deliverable and intentionally excluded from git.  The generated Xcode project is also excluded; `project.yml` is the source of truth.

This is an unsigned development build.  Release signing, notarization, model download hardening, and testing on an actual 16 GB Mac remain release tasks.

## Model storage

Default: `~/Library/Application Support/Storyboard/Models`.

For local development, `STORYBOARD_MODELS_DIR` can point to a prepared model folder containing `flux/transformer`, `text`, `vae`, and the prompt model cache.  The image engine loads the text encoder and image transformer in separate phases to reduce peak memory.

The first local engine check used about 7.4 GB peak memory footprint on a 128 GB Apple Silicon Mac.  That is a measured result for one frame, not certification for every 16 GB Mac or every document size.

## Licenses

FLUX.2 Klein 4B and Qwen3 model licenses: Apache 2.0.  The Swift FLUX implementation is MIT licensed; its license is in `Resources/Flux2Core-LICENSE.txt`.  Upstream dependencies retain their own licenses.  The supplied sketch adapter and training data have not been published.
