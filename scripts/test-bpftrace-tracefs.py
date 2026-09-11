#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Apply the selected release patches and fault-test the actual kprobe class.

The host harness replaces libbpf/kernel calls, not the attachment implementation.
It needs a fetched bpftrace Git checkout and a native C++17 compiler, but no root,
Android device, LLVM build or network access. Kernel behavior needs device tests.
"""

import argparse
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source-dir", type=Path, default=ROOT / "projects/bpftrace/sources"
    )
    args = parser.parse_args()
    version = subprocess.check_output(
        [
            "make",
            "--no-print-directory",
            "-s",
            "-f",
            str(ROOT / "projects/versions.mk"),
            "--eval=print-version:;@echo $(BPFTRACE_COMMIT)",
            "print-version",
        ],
        text=True,
    ).strip()
    patches = [
        ROOT / f"projects/bpftrace/tracefs_fallback_{version}.patch",
        ROOT / "projects/bpftrace/version_from_git_tag.patch",
    ]
    with tempfile.TemporaryDirectory(prefix="eat-tracefs-test-") as directory:
        work = Path(directory)
        # Read pristine files from the tag; never modify the fetched checkout.
        for patch in patches:
            for line in patch.read_text().splitlines():
                if line.startswith("+++ b/"):
                    name = line.removeprefix("+++ b/")
                    target = work / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(
                        subprocess.check_output(
                            [
                                "git",
                                "-C",
                                str(args.source_dir),
                                "show",
                                f"{version}:{name}",
                            ]
                        )
                    )
        for patch in patches:
            subprocess.run(
                ["git", "apply", "--check", str(patch)], cwd=work, check=True
            )
            subprocess.run(["git", "apply", str(patch)], cwd=work, check=True)
        source = (work / "src/attached_probe.cpp").read_text()
        start = source.index("class AttachedKprobeProbe :")
        end = source.index("class AttachedMultiKprobeProbe :", start)
        (work / "attached-kprobe.inc").write_text(source[start:end])
        compiler = shlex.split(os.environ.get("CXX", "c++"))
        executable = work / "tracefs-test"
        subprocess.run(
            compiler
            + [
                "-std=c++17",
                "-Wall",
                "-Wextra",
                "-Werror",
                "-I",
                str(work),
                str(ROOT / "projects/bpftrace/tests/tracefs_fallback.cpp"),
                "-o",
                str(executable),
            ],
            check=True,
        )
        subprocess.run([str(executable)], check=True)
    print(
        f"PASS: {version} patches apply to the pristine tag; tracefs fault tests pass"
    )


if __name__ == "__main__":
    main()
