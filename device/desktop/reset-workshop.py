#!/usr/bin/env python3
"""Confirm and restore the participant workspace to its pristine three files."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import sys


BASELINE_FILES = {
    "README.md": "WORKSHOP-README.txt",
    "get-bayesopt-code": "get-bayesopt-code",
    "get-localai-code": "get-localai-code",
}
LOCAL_AI_STATE_DIRS = (".picoclaw", ".pi")


def remove_path(path: Path) -> bool:
    if path.is_symlink() or (path.exists() and not path.is_dir()):
        path.unlink()
        return True
    if path.is_dir():
        shutil.rmtree(path)
        return True
    return False


def restore_workspace(workspace: Path, home: Path, source_dir: Path) -> int:
    workspace = workspace.expanduser().resolve(strict=True)
    home = home.expanduser().resolve(strict=True)
    source_dir = source_dir.expanduser().resolve(strict=True)
    if not workspace.is_dir():
        raise RuntimeError(f"Workspace is not a directory: {workspace}")
    if workspace == Path("/") or workspace == home or home == Path("/"):
        raise RuntimeError("Refusing to reset an unsafe workspace or home path.")

    baseline_sources = {
        destination_name: source_dir / source_name
        for destination_name, source_name in BASELINE_FILES.items()
    }
    for source in baseline_sources.values():
        if not source.is_file():
            raise RuntimeError(f"Missing pristine workspace file: {source}")

    removed = 0
    for child in workspace.iterdir():
        removed += int(remove_path(child))

    for destination_name, source in baseline_sources.items():
        destination = workspace / destination_name
        shutil.copyfile(source, destination)
        mode = 0o755 if destination_name.startswith("get-") else 0o644
        destination.chmod(mode)

    for state_name in LOCAL_AI_STATE_DIRS:
        state_dir = home / state_name
        if state_dir.is_dir() and not state_dir.is_symlink():
            for child in state_dir.iterdir():
                removed += int(remove_path(child))
        else:
            removed += int(remove_path(state_dir))
            state_dir.mkdir(mode=0o750)

    expected = set(BASELINE_FILES)
    actual = {path.name for path in workspace.iterdir()}
    if actual != expected:
        raise RuntimeError(
            "Workspace reset did not produce the expected pristine files: "
            f"{sorted(actual)}"
        )
    return removed


def confirm_with_dialog() -> tuple[object, bool]:
    try:
        import tkinter as tk
        from tkinter import messagebox
    except ImportError as exc:  # pragma: no cover - guarded by image validation
        raise RuntimeError("The reset dialog requires python3-tk.") from exc

    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    root.update_idletasks()
    confirmed = messagebox.askyesno(
        "Reset Workshop",
        "Are you sure?\n\n"
        "This deletes all participant work, including the BayesOpt and Local AI "
        "clones, skills, tools, agent files, and Local AI settings.\n\n"
        "Stop any running BayesOpt or PicoClaw job first.\n\n"
        "The workspace will contain only README.md, get-bayesopt-code, and "
        "get-localai-code.",
        parent=root,
    )
    return root, confirmed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yes", action="store_true", help=argparse.SUPPRESS)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    workspace = Path(os.environ.get("CDMX_WORKSPACE", Path.home() / "workspace"))
    home = Path(os.environ.get("CDMX_HOME", Path.home()))
    source_dir = Path(
        os.environ.get("CDMX_BASELINE_SOURCE", Path(__file__).resolve().parent)
    )
    root = None

    try:
        if not args.yes:
            root, confirmed = confirm_with_dialog()
            if not confirmed:
                root.destroy()
                return 0

        removed = restore_workspace(workspace, home, source_dir)
        if root is not None:
            from tkinter import messagebox

            messagebox.showinfo(
                "Reset Workshop",
                "Workshop reset complete. The workspace now contains only the "
                "README and two clean-clone helpers."
                + (f" Removed {removed} participant item(s)." if removed else ""),
                parent=root,
            )
            root.destroy()
        return 0
    except Exception as exc:
        if root is not None:
            from tkinter import messagebox

            messagebox.showerror("Reset Workshop", str(exc), parent=root)
            root.destroy()
        else:
            print(f"Reset Workshop failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
