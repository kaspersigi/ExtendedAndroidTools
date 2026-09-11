#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Offline regression checks for the shared NDK manifest and build entrypoints."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MAKE = shutil.which("make")


class NdkConfigTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="eat-ndk-config-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "scripts").mkdir()
        (self.root / "projects").mkdir()
        shutil.copy(ROOT / "projects/versions.mk", self.root / "projects")
        for name in (
            "ndk-config.sh",
            "resolute-local-build.sh",
            "build-docker-image.sh",
            "run-docker-build-env.sh",
        ):
            shutil.copy(ROOT / "scripts" / name, self.root / "scripts")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "commands"
        self.env = {
            k: v
            for k, v in os.environ.items()
            if not k.startswith(("NDK_", "DOCKER_", "CLEAN_", "MAKE"))
        }
        self.env.update(
            PATH=f"{self.bin}:{os.environ['PATH']}",
            PREFERRED_NDK_PATH=str(self.root / "absent"),
            NDK_TMP_DIR=str(self.root / "cache"),
            ALLOW_UNSUPPORTED_HOST="1",
            DEVICE_TEST="0",
            THREADS="2",
            TEST_COMMAND_LOG=str(self.log),
        )
        self.write_command("uname", 'echo "${TEST_HOST_ARCH:-x86_64}"')
        self.write_command("make", 'printf "%s\\n" "$@" >> "$TEST_COMMAND_LOG"')
        self.write_command("docker", 'printf "%s\\n" "$@" >> "$TEST_COMMAND_LOG"')
        self.write_command("curl", "echo 'unexpected download' >&2; exit 99")
        # These tests validate configuration only; no host packages are required.
        for name in (
            "autoreconf",
            "autopoint",
            "bison",
            "flex",
            "g++",
            "git",
            "help2man",
            "libtoolize",
            "perl",
            "pkg-config",
            "po4a",
            "readelf",
            "texi2any",
            "unzip",
            "wget",
            "xxd",
            "zstd",
        ):
            self.write_command(name, "exit 0")
        self.version, self.revision, self.api = self.shell(
            'printf "%s %s %s" "$NDK_VERSION" "$NDK_REVISION" "$NDK_API"'
        ).stdout.split()

    def write_command(self, name, body):
        p = self.bin / name
        p.write_text("#!/usr/bin/env bash\nset -eu\n" + body + "\n")
        p.chmod(0o755)

    def run_command(self, args, ok=True, **env):
        result = subprocess.run(
            args,
            cwd=self.root,
            env=self.env | env,
            text=True,
            capture_output=True,
        )
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def shell(self, body, **kwargs):
        return self.run_command(
            ["bash", "-euc", "source scripts/ndk-config.sh; " + body], **kwargs
        )

    def local(self, **kwargs):
        return self.run_command(
            ["bash", "scripts/resolute-local-build.sh", "python"], **kwargs
        )

    def ndk(self, host="linux-x86_64", revision=None):
        ndk = self.root / f"android-ndk-{self.version}"
        compiler = ndk / "toolchains/llvm/prebuilt" / host / "bin"
        compiler.mkdir(parents=True, exist_ok=True)
        for triple in ("aarch64-linux-android", "x86_64-linux-android"):
            p = compiler / f"{triple}{self.api}-clang"
            p.write_text("#!/bin/sh\nexit 0\n")
            p.chmod(0o755)
        (ndk / "source.properties").write_text(
            f"Pkg.Revision = {revision or self.revision}\n"
        )
        return str(ndk)

    def test_manifest_is_shared_with_make(self):
        manifest = self.root / "projects/versions.mk"
        manifest.write_text(
            "NDK_VERSION := fixture\nNDK_REVISION := 99.1.2\n"
            "NDK_API := 36\nNDK_LINUX_X86_64_SHA256 := " + "a" * 64 + "\n"
        )
        actual = self.shell(
            'printf "%s %s %s" "$NDK_VERSION" "$NDK_REVISION" "$NDK_API"'
        ).stdout
        expected = self.run_command(
            [
                MAKE,
                "-s",
                "-f",
                str(manifest),
                "--eval",
                "probe:;@printf '%s %s %s' '$(NDK_VERSION)' '$(NDK_REVISION)' '$(NDK_API)'",
                "probe",
            ]
        ).stdout
        self.assertEqual(actual, expected)
        self.assertEqual(actual, "fixture 99.1.2 36")

    def test_generated_paths_refresh_when_ndk_or_api_changes(self):
        build = self.root / "build"
        out = self.root / "out"
        strip = out / "host/bpftrace-strip-thunk"
        site = out / "android/arm64/share/config.site"
        common = [
            MAKE,
            "-s",
            "--no-print-directory",
            "-C",
            str(ROOT),
            f"BUILD_DIR={build}",
            f"OUT_DIR={out}",
            str(strip),
            str(site),
        ]
        ndk = self.ndk()
        self.run_command(
            common + [f"NDK_PATH={ndk}", "HOST_MACHINE=x86_64", "NDK_API=35"]
        )
        self.assertIn(
            f"{ndk}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip",
            strip.read_text(),
        )
        times = (strip.stat().st_mtime_ns, site.stat().st_mtime_ns)
        self.run_command(
            common + [f"NDK_PATH={ndk}", "HOST_MACHINE=x86_64", "NDK_API=35"]
        )
        self.assertEqual(times, (strip.stat().st_mtime_ns, site.stat().st_mtime_ns))
        other_ndk = self.root / "other-ndk"
        other_ndk.mkdir()
        shutil.copy(Path(ndk) / "source.properties", other_ndk)
        self.run_command(
            common + [f"NDK_PATH={other_ndk}", "HOST_MACHINE=aarch64", "NDK_API=36"]
        )
        self.assertIn(
            f"{other_ndk}/toolchains/llvm/prebuilt/linux-aarch64/bin/llvm-strip",
            strip.read_text(),
        )
        self.assertIn(
            "linux-aarch64/bin/aarch64-linux-android36-clang", site.read_text()
        )

    def test_version_override_rejected(self):
        r = self.shell("true", ok=False, NDK_VERSION="different")
        self.assertIn("configure NDK_VERSION", r.stderr)

    def test_official_download_uses_manifest_hash(self):
        r = self.shell(
            'ndk_download_defaults linux-x86_64; printf "%s %s" "$NDK_DOWNLOAD_URL" "$NDK_DOWNLOAD_SHA256"'
        )
        self.assertIn(f"android-ndk-{self.version}-linux.zip", r.stdout)
        expected = self.shell(
            "ndk_manifest_value NDK_LINUX_X86_64_SHA256"
        ).stdout.strip()
        self.assertTrue(r.stdout.endswith(expected))

    def test_custom_download_requires_own_hash(self):
        self.shell(
            "ndk_download_defaults linux-x86_64",
            ok=False,
            NDK_DOWNLOAD_URL="https://example.invalid/ndk.zip",
        )
        r = self.shell(
            'ndk_download_defaults linux-aarch64; echo "$NDK_DOWNLOAD_SHA256"',
            NDK_DOWNLOAD_URL="https://example.invalid/ndk.zip",
            NDK_DOWNLOAD_SHA256="a" * 64,
        )
        self.assertEqual(r.stdout.strip(), "a" * 64)

    def test_x64_local_selects_api35_compiler(self):
        self.local(NDK_PATH=self.ndk())
        self.assertIn("NDK_HOST_TAG=linux-x86_64", self.log.read_text())
        self.assertIn(f"NDK_API={self.api}", self.log.read_text())

    def test_arm64_local_selects_native_compiler(self):
        self.local(NDK_PATH=self.ndk("linux-aarch64"), TEST_HOST_ARCH="aarch64")
        self.assertIn("NDK_HOST_TAG=linux-aarch64", self.log.read_text())

    def test_arm64_rejects_x64_only_ndk(self):
        r = self.local(ok=False, NDK_PATH=self.ndk(), TEST_HOST_ARCH="aarch64")
        self.assertIn("linux-aarch64/bin", r.stderr)
        self.assertFalse(self.log.exists())

    def test_arm64_missing_ndk_does_not_download_official_x64(self):
        r = self.local(ok=False, TEST_HOST_ARCH="aarch64")
        self.assertIn("requires a self-built NDK", r.stderr)
        self.assertNotIn("unexpected download", r.stderr)
        self.assertFalse(self.log.exists())

    def fixture_download(self):
        # Use real curl/unzip for a local ZIP; the compiler is an executable stub.
        (self.bin / "curl").unlink()
        (self.bin / "unzip").unlink()
        ndk = Path(self.ndk())
        compiler_dir = ndk / "toolchains/llvm/prebuilt/linux-x86_64/bin"
        shutil.copy(
            compiler_dir / f"aarch64-linux-android{self.api}-clang",
            compiler_dir / "clang",
        )
        archive = self.root / "ndk.zip"
        with zipfile.ZipFile(archive, "w") as z:
            for path in ndk.rglob("*"):
                if path.is_file():
                    z.write(path, path.relative_to(self.root))
        return {
            "NDK_DOWNLOAD_URL": archive.as_uri(),
            "NDK_DOWNLOAD_SHA256": hashlib.sha256(archive.read_bytes()).hexdigest(),
        }

    def test_verified_download_enters_cache(self):
        self.local(**self.fixture_download())
        cached = self.root / "cache" / f"android-ndk-{self.version}"
        self.assertTrue((cached / "source.properties").is_file())
        self.assertIn(f"NDK_PATH={cached}", self.log.read_text())

    def test_corrupt_download_never_enters_cache(self):
        env = self.fixture_download()
        env["NDK_DOWNLOAD_SHA256"] = "0" * 64
        r = self.local(ok=False, **env)
        self.assertIn("checksum does not match", r.stderr)
        self.assertEqual(list((self.root / "cache").iterdir()), [])
        self.assertFalse(self.log.exists())

    def test_wrong_revision_rejected(self):
        r = self.local(ok=False, NDK_PATH=self.ndk(revision="27.3.0"))
        self.assertIn("expected NDK", r.stderr)
        self.assertFalse(self.log.exists())

    def test_x64_docker_uses_manifest(self):
        self.run_command(["bash", "scripts/build-docker-image.sh"])
        args = self.log.read_text()
        self.assertIn("linux/amd64", args)
        self.assertIn(f"android-ndk-{self.version}-linux.zip", args)
        self.assertTrue(args.endswith(str(self.root) + "\n"))

    def test_arm64_docker_requires_custom_archive(self):
        self.run_command(
            ["bash", "scripts/build-docker-image.sh"],
            ok=False,
            TEST_HOST_ARCH="aarch64",
        )
        self.assertFalse(self.log.exists())
        self.run_command(
            ["bash", "scripts/build-docker-image.sh"],
            TEST_HOST_ARCH="aarch64",
            NDK_DOWNLOAD_URL="https://example.invalid/ndk.zip",
            NDK_DOWNLOAD_SHA256="a" * 64,
        )
        self.assertIn("linux/arm64", self.log.read_text())

    def test_docker_run_selects_native_platform_and_path(self):
        self.run_command(
            ["bash", "scripts/run-docker-build-env.sh"], TEST_HOST_ARCH="aarch64"
        )
        args = self.log.read_text()
        self.assertIn("linux/arm64", args)
        self.assertIn(f"NDK_PATH=/opt/ndk/android-ndk-{self.version}", args)
        self.assertIn(f"NDK_API={self.api}", args)


if __name__ == "__main__":
    unittest.main(verbosity=2)
