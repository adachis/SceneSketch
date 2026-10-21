# Storyboard 0.2 — local Mac app

## Open and review

Extract `Storyboard.zip`, move the app to Applications, and open it.  The build targets Apple Silicon and macOS 15 or later.  It is signed with the available Developer ID certificate; notarization is a separate release check.  Open `Story Library Demo.sketchboard` to explore the new library and scene controls.

## Story files and libraries

Each `.sketchboard` file contains one story, its ordered scenes and shots, its character and location records, and its reference images.  Images travel with the file; they do not depend on the original photo paths.  Version 1 documents migrate when opened.

Use **Story library** to add and edit characters or locations.  Images can be selected or dropped into the library.  Choose a primary reference, remove unneeded images, or merge duplicate entries.  Merging preserves descriptions and images and redirects linked shots.

Adding images offers **Visual references only**, **Enhance existing description**, or **Recreate description** when a description already exists.  A new entry instead offers creation.  Generated changes appear in an editable review before they can replace saved text.  Character image analysis passes only permitted physical appearance fields; clothing and accessories cannot be emitted through that filter.  Manually entered details are retained when enhancing.

## Shots and references

Use **Insert** in a shot description to add character or location pills.  The pills retain stable IDs; renaming a library entry updates its meaning without rewriting every shot.  Rendering resolves the current descriptions, scene context, and selected visual references.

The **References** meter shows the images used for that shot.  The current native engine accepts three.  Automatic selection takes shot images first, then primary images for linked characters and locations.  Choose images in the picker to override that selection.  Extra library images remain available without being sent to the renderer.  Each reference is bounded to 65,536 pixels during encoding.  Character conditioning uses a face-focused crop when a face is detected.

Add scenes and shots from the toolbar.  Scenes can collapse and move up or down; shots can be reordered within a scene or assigned to another scene.  Generate one frame or the current scene.  **Stop after frame** stops a batch without losing completed images.  PNG export and native document saving remain available.

## Screenplay import

Import PDF, scanned PDF, Final Draft `.fdx`, Fountain, or UTF-8 text.  PDF import uses text positions to distinguish action, dialogue cues, and wrapped scene headings.  Scanned pages use Apple's on-device text recognition.  Final Draft uses its typed XML paragraphs; Fountain uses screenplay syntax.

Review scenes, proposed shots, character names, locations, and available description data before importing.  Uncheck scenes or individual shots you do not want.  Import merges matching entity names and preserves existing descriptions.  Source text stays attached to scenes and shots for checking.  Missing appearance information is left for manual entry or image references instead of being invented.

Shot proposals follow action beats, not a finished director's shooting plan.  Long scripts can produce hundreds of proposals; review and regroup them as needed.  The four supplied sample scripts are included in the validation summary, not redistributed in this folder.

## Local models and validation

The image engine remains four-bit FLUX.2 Klein 4B with the trained storyboard LoRA.  Prompt cleanup uses local Qwen3 0.6B.  Image descriptions use Qwen3.5 2B in four-bit form; smaller vision models failed the appearance test.  Vision analysis and image generation share a serialized compute gate and release cached memory between operations.

Reference-conditioned test renders peaked around 7.6 GB on an M5 Max with 128 GiB unified memory.  Character image analysis peaked around 3.7 GB.  These are measurements on this Mac, not certification on a 16 GB machine.  No new Modal training was used for this update.  Model files download once when needed; cached generation and analysis work offline.

Generation can still duplicate a subject, invent lettering, or drift in fine facial details.  The library and image references improve continuity; they do not make the image model infallible.  A failed duplicate-person frame is retained in `Validation/` so this limit is visible.

`Source/` includes the app source and pinned dependencies.  `Validation/` includes parser summaries, runtime logs, and build checks.  `Training/` and `LoRA/` retain the previous training provenance and both formats of the selected adapter.

## Research

- [Fountain syntax](https://fountain.io/syntax/) informs text parsing.
- [BFL reference editing](https://help.bfl.ai/articles/6546682167-what-is-multi-reference-editing) explains image conditioning.  The pinned Swift engine enforces its own three-image limit.
- [Qwen3.5](https://huggingface.co/Qwen/Qwen3.5-2B) provides the small local vision model.
- [EmbeddingGemma 2](https://ai.google.dev/gemma/docs/embeddinggemma/model_card_2?hl=en) produces representations for matching and retrieval.  It was not added: screenplay structure extraction does not require an embedding model.

## Build from source

Use Xcode with the Swift 6.3 toolchain and XcodeGen.  In the source directory, run `./build.sh`.  The script copies the adjacent `../LoRA/StoryboardStyle.safetensors` when needed, resolves the pinned dependencies, and packages `dist/Storyboard.zip`.  Set `STORYBOARD_SIGN_IDENTITY` to your signing identity to produce a Developer ID build; otherwise it uses development ad hoc signing.
