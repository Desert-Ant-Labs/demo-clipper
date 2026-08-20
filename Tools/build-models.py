#!/usr/bin/env python3
"""Put the models where Clipper looks for them.

    Tools/build-models.py                      # all three from the Hub
    Tools/build-models.py --clips-local ../clips-training/release/clip-sdk
    Tools/build-models.py --title ../title-training/release/title

What it makes, under `~/Library/Application Support/Clipper/Models`:

    clips/clips.mlmodelc          the multifunction Core ML package
    clips/clip_tokenizer.bin      the vocab, as published
    voz/                          the recognizer, three Core ML programs and sidecars
    title/                        the MLX card model, ~280 MB

The names are the SDK's, not ours: `Clips(directory:)` adopts a directory only
when every file `ClipModel` declares is present under exactly those names, and
falls through to a Hub download when one is missing. `ModelLocations.swift`
derives that list from `ClipModel` rather than repeating it.

EVERYTHING COMES OFF THE HUB, and this file no longer builds anything. It used
to compile Clips from local `.mlpackage`s while the Hub repository was
mid-rebuild, and to symlink the card model off local disk while it had no
published repository. Both landed: `desert-ant-labs/clips` and
`desert-ant-labs/title` are tagged, and downloading the published bytes rather
than rebuilding them locally means the demo runs the artifact a consumer gets,
which is the only version of it anyone has verified. The repositories are
public, so nothing here needs a token; the prefetch exists so a demo of the
models does not become a demo of a download.

`--clips-local` and `--title` install a local build instead, for testing one
before it is published. `--title` stays a symlink: the directory is 280 MB and
moves often.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
from pathlib import Path

HOME = Path.home()
DEFAULT_DEST = HOME / "Library/Application Support/Clipper/Models"
REPO = "desert-ant-labs/clips"
VOZ_REPO = "desert-ant-labs/voz"
TITLE_REPO = "desert-ant-labs/title"

#: The published tags to install. Kept in step with `ClipModel.revision`,
#: `VozModel.revision` and `TitleModel.revision` in the core, which are the
#: SDK's own pins, and checked against them rather than trusted. A demo running
#: different weights than the SDK declares is a bug that looks like a model
#: regression.
REVISION = "v0.1.0"
VOZ_REVISION = "v0.1.0"
TITLE_REVISION = "v0.1.0"
CORE = Path(__file__).resolve().parent.parent.parent / "desert-ant-core"


def check_revision(catalog: Path, revision: str) -> None:
    """Warn when this file and the SDK disagree about which release to run."""
    try:
        text = catalog.read_text()
    except OSError:
        return  # the core is not beside us; the download still works
    found = re.search(r'static let revision\s*=\s*"([^"]+)"', text)
    if found and found.group(1) != revision:
        print(f"  ! this script installs {revision} but the SDK pins "
              f"{found.group(1)}; the app would load one and resolve the other")


def fetch_clips(destination: Path) -> None:
    """Download the Apple artifacts at the pinned tag and lay them out flat."""
    try:
        from huggingface_hub import snapshot_download
    except ImportError:
        sys.exit("huggingface_hub is not installed: pip install huggingface_hub, "
                 "or pass --clips-local to install from a local build instead")
    check_revision(CORE / "Sources/Clips/Catalog.swift", REVISION)
    print(f"Clips from {REPO} at {REVISION}")
    # `HF_TOKEN` is often a stale token on a dev machine, and it takes precedence
    # over the credential `hf auth login` stored. These repositories are public,
    # so drop the variable rather than fail on someone else's expired key.
    os.environ.pop("HF_TOKEN", None)
    snapshot = Path(snapshot_download(
        REPO, revision=REVISION,
        allow_patterns=["clips.mlmodelc/*", "clip_tokenizer.bin"]))
    install(snapshot, destination, ("clips.mlmodelc", "clip_tokenizer.bin"))


def fetch_voz(destination: Path) -> None:
    """Download the recognizer and lay its declared files out flat."""
    try:
        from huggingface_hub import snapshot_download
    except ImportError:
        sys.exit("huggingface_hub is not installed: pip install huggingface_hub")
    check_revision(CORE / "Sources/Voz/Catalog.swift", VOZ_REVISION)
    print(f"Voz from {VOZ_REPO} at {VOZ_REVISION} (~489 MB)")
    os.environ.pop("HF_TOKEN", None)
    snapshot = Path(snapshot_download(
        VOZ_REPO, revision=VOZ_REVISION,
        allow_patterns=["*.mlmodelc/*", "meta.json", "vocab.json", "embedding.f16"]))
    install(snapshot, destination,
            ("encoder.mlmodelc", "mel.mlmodelc", "decoder.mlmodelc",
             "meta.json", "vocab.json", "embedding.f16"))


def fetch_title(destination: Path) -> None:
    """Download the card model at the pinned tag."""
    try:
        from huggingface_hub import snapshot_download
    except ImportError:
        sys.exit("huggingface_hub is not installed: pip install huggingface_hub, "
                 "or pass --title to install from a local build instead")
    check_revision(CORE / "Sources/Title/Catalog.swift", TITLE_REVISION)
    print(f"Title from {TITLE_REPO} at {TITLE_REVISION} (~280 MB)")
    os.environ.pop("HF_TOKEN", None)
    snapshot = Path(snapshot_download(TITLE_REPO, revision=TITLE_REVISION))
    if destination.is_symlink():
        destination.unlink()
    destination.mkdir(parents=True, exist_ok=True)
    install(snapshot, destination,
            ("config.json", "generation_config.json", "model.safetensors",
             "model.safetensors.index.json", "tokenizer.json",
             "tokenizer_config.json", "chat_template.jinja"))


def install(source: Path, destination: Path, names: tuple[str, ...]) -> None:
    """Copy each named file or directory into place, replacing what is there."""
    for name in names:
        origin = source / name
        if not origin.exists():
            sys.exit(f"no {name} in {source}")
        target = destination / name
        if target.is_symlink() or target.is_file():
            target.unlink()
        elif target.is_dir():
            shutil.rmtree(target)
        if origin.is_dir():
            shutil.copytree(origin, target)
        else:
            shutil.copy2(origin, target)
        print(f"  {name}")


def link_title(source: Path, destination: Path) -> None:
    if not (source / "config.json").exists():
        sys.exit(f"no MLX model at {source} (config.json missing)")
    if destination.is_symlink() or destination.exists():
        if destination.is_symlink() or destination.is_file():
            destination.unlink()
        else:
            shutil.rmtree(destination)
    destination.symlink_to(source)
    print(f"  title -> {source}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clips-local", type=Path,
                        default=os.environ.get("CLIPPER_CLIPS_RELEASE"),
                        help="install from a local directory holding clips.mlmodelc and "
                             "clip_tokenizer.bin (clips-training/release/clip-sdk) instead "
                             "of downloading. For testing a build before it is published")
    parser.add_argument("--title", type=Path,
                        default=os.environ.get("CLIPPER_TITLE_RELEASE"),
                        help="symlink a local MLX model directory "
                             "(title-training/release/title) instead of downloading. "
                             "For testing a build before it is published")
    parser.add_argument("--dest", type=Path,
                        default=Path(os.environ.get("CLIPPER_MODELS", DEFAULT_DEST)))
    options = parser.parse_args()

    clips = options.dest / "clips"
    clips.mkdir(parents=True, exist_ok=True)

    if options.clips_local:
        local = Path(options.clips_local)
        print(f"Clips from {local} (local, NOT the published artifact)")
        install(local, clips, ("clips.mlmodelc", "clip_tokenizer.bin"))
    else:
        fetch_clips(clips)

    voz = options.dest / "voz"
    voz.mkdir(parents=True, exist_ok=True)
    fetch_voz(voz)

    title = options.dest / "title"
    if options.title:
        local = Path(options.title)
        print(f"Title from {local} (local, NOT the published artifact)")
        link_title(local, title)
    else:
        fetch_title(title)

    print(f"\n{options.dest}")


if __name__ == "__main__":
    main()
