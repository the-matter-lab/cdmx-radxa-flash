#!/usr/bin/env python3
"""Confirm and remove only the participant BayesOpt checkout."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import sys


CHECKOUT_NAME = "cdmx-bayesopt"


def reset_checkout(workspace: Path) -> bool:
    workspace = workspace.expanduser().resolve(strict=True)
    target = workspace / CHECKOUT_NAME

    if target.is_symlink() or (target.exists() and not target.is_dir()):
        target.unlink()
        return True
    if target.is_dir():
        shutil.rmtree(target)
        return True
    return False


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
        "Reset BayesOpt",
        "Are you sure?\n\n"
        "This deletes ~/workspace/cdmx-bayesopt and all BayesOpt results.\n"
        "Stop any running BayesOpt job first. Other workshop files are kept.",
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
    root = None

    try:
        if not args.yes:
            root, confirmed = confirm_with_dialog()
            if not confirmed:
                root.destroy()
                return 0

        removed = reset_checkout(workspace)
        if root is not None:
            from tkinter import messagebox

            message = (
                "BayesOpt was reset. Run ./get-bayesopt-code for a clean clone."
                if removed
                else "BayesOpt is already clean. Run ./get-bayesopt-code to begin."
            )
            messagebox.showinfo("Reset BayesOpt", message, parent=root)
            root.destroy()
        return 0
    except Exception as exc:
        if root is not None:
            from tkinter import messagebox

            messagebox.showerror("Reset BayesOpt", str(exc), parent=root)
            root.destroy()
        else:
            print(f"Reset BayesOpt failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

