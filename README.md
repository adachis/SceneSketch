# SceneSketch 0.3.0

SceneSketch is an Apple Silicon Mac app for making sketch storyboards with local models.  It requires macOS 15 or later.  Story files use the existing `.sketchboard` extension.

## Install and set up

Extract `SceneSketch.zip`, move SceneSketch.app to Applications, and open it.  The release is Developer ID signed, notarized, and stapled.  Quit an older Storyboard copy before opening SceneSketch: both versions deliberately share the same app identity, preferences, and document association.

The first-launch setup offers one download for drawing, prompt cleanup, and image descriptions.  A new installation downloads approximately **12.4 GB**; the exact remaining size appears before downloading.  The trained sketch LoRA is already in the app.  Existing Storyboard model files are reused.  Downloads can pause, resume, and retry, and each completed file is checked against its pinned SHA-256 hash.  All creative processing works offline after setup.  Initial downloads contact Hugging Face; story content and reference images stay on the Mac.

**SceneSketch → Settings** controls the interface language, short-prompt cleanup, export defaults, and model storage.  The Models tab also downloads, verifies, removes, or repairs models.  Choosing a different storage folder uses that folder; it does not silently move or delete the old cache.  Model changes are disabled while rendering or generating a scene.

The default paper setting is **Ask when exporting**.  Choose Letter or A4 in the export sheet, or save a preference in Settings.

## Stories, characters, and locations

Each file contains one story, ordered scenes and shots, character and location records, reference images, and optional production metadata.  Images are embedded, so the document does not depend on original photo paths.  Versions 1 and 2 migrate when opened and saved.

Use **Story Library** to add or edit characters and locations.  Drop or select reference images, choose a primary reference, remove images, or merge duplicate records.  Adding references to an existing description offers **Visual references only**, **Enhance existing description**, or **Recreate description**.  Generated text is reviewed before replacing saved text.  Character image analysis focuses on stable physical appearance and filters out clothing and accessories; clothing can still be added manually.

Use **Insert** to place character or location pills in shot descriptions.  Pills use stable IDs, so later library edits are reflected when rendering.  References are selected from the shot and its linked records.  The meter shows the three-image rendering limit.  Extra library images stay available without being sent to the renderer.  Reference encoding is bounded to 256 × 256 pixels per image; detected character faces receive a focused crop.

Scenes can collapse and move, and shots can be reordered or moved between scenes.  Generate a frame or its whole scene.  **Stop after frame** retains completed renders.  The Story Library fills its sheet immediately, including before an entry is selected.

## Screenplay import

Import PDF, scanned PDF, Final Draft `.fdx`, Fountain, or UTF-8 text.  PDFs use text positions to recover screenplay structure; scans use Apple's on-device text recognition.  Review detected scenes, shots, characters, and locations before importing, and uncheck items you do not want.  Import preserves existing descriptions when merging matching entities.  Source passages stay attached for reference.

Shot proposals follow action beats and need editorial review.  Long screenplays can produce many shots.  The importer does not invent missing physical appearance details.

## Export and print

Choose **File → Export Storyboard** or the Export toolbar control.  Select scenes and whether to include shots that have not been rendered.

- **PDF:** Letter or A4, landscape or portrait, with 2, 3, 4, 6, 12, or 16 panels.  Choose descriptions, optional metadata, and whether each scene starts on a new page.  The live preview shows the result before saving.  Long notes continue on extra pages instead of being discarded.
- **Images and data:** PNG frames, a CSV shot list, and structured JSON scene data in a new folder.
- **Shot list:** CSV alone for a spreadsheet or production tool.

Production details include company, director, storyboard artist, revision, and date.  Each shot can also store a production number, lens, duration, camera movement, dialogue, and notes.  These fields are optional.  The layouts are original implementations informed by the supplied printable templates.

## Languages and prompts

The interface includes machine translations for the 119 languages and dialects listed by the bundled Qwen3 model.  Settings uses each language's native name, and the default follows the system language.  Arabic, Hebrew, Persian, Urdu, and related right-to-left interfaces mirror their layout.  Some macOS menus follow a changed language after relaunching.

Descriptions in other languages are translated locally into English for the image model, including linked character and location descriptions.  Original story text remains unchanged.  Translation reuses the four-bit Qwen3 4B text encoder already downloaded for drawing.  Short English prompt cleanup uses Qwen3 0.6B.  Image descriptions use Qwen3.5 2B in four-bit form.

Rendered compositions request blank signs, covers, and other unmarked surfaces.  Common text-bearing props are neutralized only in the rendering prompt; dialogue, captions, and notes remain available in the document and exports.  An on-device text check triggers at most one additional render when lettering is detected, and keeps the result with less detected text.  The extra attempt can take additional time.  Image models and text recognition can still miss or invent marks, so inspect the result.

Translations were checked for complete resource coverage and matching format placeholders, with representative interface and prompt tests.  They have not all received native-speaker review, and language quality varies by model and language.  English remains the fallback for missing strings.

## Runtime and validation

The tested drawing configuration is unchanged: FLUX.2 Klein 4B, four-bit execution, four steps, 1024 × 576 output, and the bundled sketch LoRA.  Loading it requires more disk storage than runtime memory because the transformer is stored in its source precision and quantized when loaded.  Text, vision, and image operations run serially and release model memory between operations.

Prior reference-conditioned renders peaked around 7.6 GB on an M5 Max with 128 GiB unified memory, and image descriptions around 3.7 GB.  These are measurements on that machine, **not validation on a 16 GB Mac**.  No additional Modal training was used for this release.  Current release checks and samples are in `Validation/` and `Examples/`.

The model can still duplicate subjects or drift in facial details.  Library descriptions and reference images help continuity but do not guarantee identical characters.

## Before a public release

The next priorities are testing first launch and sustained rendering on a real 16 GB Mac; native-speaker and accessibility review; a signed update mechanism; and explicit undo/recovery plus image-version history.  Confirm redistribution permissions for the training images and all shipped model/dependency assets before public distribution.

## Build from source

Use Xcode with Swift 6.3 and XcodeGen.  Run `./build.sh` from `Source/`.  The script can copy the adjacent `../LoRA/StoryboardStyle.safetensors`, resolves pinned dependencies, and writes `dist/SceneSketch.zip`.  Set `STORYBOARD_SIGN_IDENTITY` to a Developer ID identity for signing; otherwise the script uses ad hoc signing.  Notarization is a separate release step.  Internal target and preference identifiers retain the original Storyboard name for compatibility.

## Model and format references

- [Qwen3 languages](https://qwenlm.github.io/blog/qwen3/)
- [FLUX.2 Klein 4B](https://huggingface.co/black-forest-labs/FLUX.2-klein-4B)
- [Qwen3.5 2B](https://huggingface.co/Qwen/Qwen3.5-2B)
- [Fountain syntax](https://fountain.io/syntax/)
