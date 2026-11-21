"""Tests for the Orbit session scripts.

Everything runs against a throwaway HOME and a --destdir staging folder, with
stub systemctl, notify-send and start-cosmic, so the real login screen, systemd
user manager and COSMIC settings are never touched.

Run: python3 -m unittest discover -s session/tests -v
"""
# SPDX-License-Identifier: GPL-3.0-only
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import time
import unittest

SESSION = Path(__file__).resolve().parents[1]
OWNER = "X-OrbitOwner=orbit-session-v1"


def write_exe(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


class SessionScripts(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="orbit-session-test-")
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        # Spaces on purpose: the real checkout lives under "Orbit WM".
        self.root = self.tmp / "dev dir" / "orbit-comp"
        shutil.copytree(SESSION, self.root / "session", ignore=shutil.ignore_patterns("tests", "__pycache__"))
        write_exe(self.root / "target/debug/cosmic-comp", "#!/bin/sh\necho fake compositor\n")
        applets = self.tmp / "dev dir" / "orbit-applets"
        write_exe(applets / "target/debug/cosmic-applet-tiling", "#!/bin/sh\n")
        data = applets / "cosmic-applet-tiling/data"
        (data / "icons/scalable/apps").mkdir(parents=True)
        (applets / "cosmic-applet-tiling/Cargo.toml").write_text("[package]\n")
        (data / "com.system76.CosmicAppletTiling.desktop").write_text(
            "[Desktop Entry]\nName=Window Layout\nCategories=COSMIC;\nExec=cosmic-applet-tiling\n"
        )
        for name in ("-symbolic", ".Scrolling"):
            (data / f"icons/scalable/apps/com.system76.CosmicAppletTiling{name}.svg").write_text("<svg/>")

        self.home = self.tmp / "home" / "testuser"
        self.home.mkdir(parents=True)
        self.stage = self.tmp / "stage"
        self.stubs = self.tmp / "stubs"
        self.calls = self.tmp / "calls.log"
        for tool in ("systemctl", "notify-send", "sudo", "pacman"):
            write_exe(self.stubs / tool, f'#!/bin/sh\necho "{tool} $*" >>"{self.calls}"\n')
        self.start_cosmic = self.tmp / "start-cosmic"
        write_exe(
            self.start_cosmic,
            f'#!/bin/sh\n{{ echo "args=$*"; echo "PATH=$PATH"; echo "XDG_DATA_DIRS=$XDG_DATA_DIRS";'
            f' echo "ORBIT_SESSION=${{ORBIT_SESSION-}}"; }} >"{self.tmp}/started"\n',
        )

    def env(self, **extra):
        env = {
            "HOME": str(self.home),
            "USER": "testuser",
            "PATH": f"{self.stubs}:/usr/bin:/bin",
            "LANG": "C.UTF-8",
        }
        env.update(extra)
        return env

    def run_script(self, name, *args, **env):
        return subprocess.run(
            [str(self.root / "session" / name), *args],
            env=self.env(**env), capture_output=True, text=True, timeout=60,
        )

    def install(self, *args, **env):
        return self.run_script("install.sh", "--no-build", "--debug", "--destdir", str(self.stage), *args, **env)

    @property
    def prefix(self):
        return self.home / ".local/share/orbit/prefix"

    def reports(self):
        return sorted((self.home / ".local/state/orbit/reports").glob("orbit-report-*.txt"))

    # --- install -----------------------------------------------------------

    def test_install_stages_session_and_private_prefix(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        for rel in ("bin/cosmic-comp", "bin/cosmic-applet-tiling", "bin/orbit-report", "share/orbit/lib.sh",
                    "share/orbit/build-info",
                    "share/icons/hicolor/scalable/apps/com.system76.CosmicAppletTiling.Scrolling.svg"):
            self.assertTrue((self.prefix / rel).exists(), rel)
        applet_desktop = self.prefix / "share/applications/com.system76.CosmicAppletTiling.desktop"
        self.assertNotIn("Categories=COSMIC;", applet_desktop.read_text())
        self.assertIn("profile: debug", (self.prefix / "share/orbit/build-info").read_text())
        launcher = self.stage / "usr/local/bin/orbit-session"
        desktop = self.stage / "usr/share/wayland-sessions/orbit.desktop"
        self.assertTrue(os.access(launcher, os.X_OK))
        self.assertIn(OWNER, desktop.read_text())
        self.assertIn("Exec=/usr/local/bin/orbit-session", desktop.read_text())
        self.assertFalse(self.calls.exists() and "sudo" in self.calls.read_text(), "staging must not use sudo")

    def test_reinstall_replaces_the_prefix(self):
        self.assertEqual(self.install().returncode, 0)
        (self.prefix / "bin/stale").write_text("old")
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.prefix / "bin/stale").exists())
        self.assertFalse((self.home / ".local/share/orbit/prefix.new").exists())

    def test_build_only_skips_the_login_screen(self):
        result = self.run_script("install.sh", "--no-build", "--debug", "--build-only")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.prefix / "bin/cosmic-comp").exists())
        self.assertFalse(self.stage.exists())

    def test_refuses_to_replace_a_foreign_session_entry(self):
        desktop = self.stage / "usr/share/wayland-sessions/orbit.desktop"
        desktop.parent.mkdir(parents=True)
        desktop.write_text("[Desktop Entry]\nName=Someone else\n")
        result = self.install()
        self.assertEqual(result.returncode, 1)
        self.assertIn("A file Orbit needs is already taken", result.stderr)
        self.assertIn("ORB-I08", result.stderr)
        self.assertEqual(desktop.read_text(), "[Desktop Entry]\nName=Someone else\n")

    def test_empty_leftover_session_files_are_replaced(self):
        launcher = self.stage / "usr/local/bin/orbit-session"
        desktop = self.stage / "usr/share/wayland-sessions/orbit.desktop"
        for path in (launcher, desktop):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("")
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(OWNER, desktop.read_text())
        self.assertGreater(launcher.stat().st_size, 0)
        self.assertEqual(list(launcher.parent.glob("*.orbit-new")), [])

    def test_refuses_a_foreign_orbit_folder(self):
        (self.home / ".local/share/orbit").mkdir(parents=True)
        (self.home / ".local/share/orbit/mine.txt").write_text("keep")
        result = self.install()
        self.assertEqual(result.returncode, 1)
        self.assertIn("ORB-I08", result.stderr)
        self.assertTrue((self.home / ".local/share/orbit/mine.txt").exists())

    def test_missing_applet_checkout_warns_and_continues(self):
        result = self.install(ORBIT_APPLETS_DIR=str(self.tmp / "nowhere"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ORB-W02", result.stderr)
        self.assertFalse((self.prefix / "bin/cosmic-applet-tiling").exists())
        self.assertIn("applet: system", (self.prefix / "share/orbit/build-info").read_text())

    def test_missing_build_fails_with_a_specific_code(self):
        (self.root / "target/debug/cosmic-comp").unlink()
        result = self.install()
        self.assertEqual(result.returncode, 1)
        self.assertIn("The compositor hasn't been built yet", result.stderr)
        self.assertIn("ORB-I06", result.stderr)

    def test_relative_destdir_is_rejected(self):
        result = self.run_script("install.sh", "--no-build", "--debug", "--destdir", "relative/path")
        self.assertEqual(result.returncode, 1)
        self.assertIn("ORB-I11", result.stderr)

    def test_failure_report_has_no_personal_details(self):
        (self.root / "target/debug/cosmic-comp").unlink()
        self.install()
        reports = self.reports()
        self.assertEqual(len(reports), 1)
        text = reports[0].read_text()
        self.assertIn("error: ORB-I06", text)
        self.assertNotIn(str(self.home), text)
        self.assertNotIn("testuser", text)
        self.assertIn("~/", text)

    def test_redaction_covers_emails_and_secrets(self):
        script = f'. "{self.root}/session/lib.sh"; printf "%s\\n" "$1" | orbit_redact'
        sample = f"{self.home}/x a.b@example.com token=abc123 title=\"Secret doc\" testuser"
        out = subprocess.run(["bash", "-c", script, "_", sample], env=self.env(),
                             capture_output=True, text=True).stdout
        self.assertEqual(out.strip(), '~/x <email> token=<redacted> title="<redacted>" <user>')

    # --- uninstall ---------------------------------------------------------

    def test_uninstall_removes_only_orbit_files(self):
        self.assertEqual(self.install().returncode, 0)
        other = self.stage / "usr/share/wayland-sessions/cosmic.desktop"
        other.write_text("[Desktop Entry]\n")
        result = self.run_script("uninstall.sh", "--destdir", str(self.stage))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.stage / "usr/local/bin/orbit-session").exists())
        self.assertFalse((self.stage / "usr/share/wayland-sessions/orbit.desktop").exists())
        self.assertFalse((self.home / ".local/share/orbit").exists())
        self.assertTrue(other.exists())
        self.assertTrue((self.home / ".local/state/orbit/install.log").exists())

    def test_uninstall_refuses_foreign_files(self):
        desktop = self.stage / "usr/share/wayland-sessions/orbit.desktop"
        desktop.parent.mkdir(parents=True)
        desktop.write_text("[Desktop Entry]\n")
        result = self.run_script("uninstall.sh", "--destdir", str(self.stage))
        self.assertEqual(result.returncode, 1)
        self.assertIn("ORB-U01", result.stderr)
        self.assertTrue(desktop.exists())

    def test_purge_removes_logs(self):
        self.assertEqual(self.install().returncode, 0)
        result = self.run_script("uninstall.sh", "--purge", "--destdir", str(self.stage))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / ".local/state/orbit").exists())

    # --- launcher ----------------------------------------------------------

    def launch(self, **env):
        base = {"ORBIT_START_COSMIC": str(self.start_cosmic), "ORBIT_NOTIFY_DELAY": "0"}
        base.update(env)
        return subprocess.run(
            [str(self.root / "session/orbit-session"), "--in-login-shell"],
            env=self.env(**base), capture_output=True, text=True, timeout=30,
        )

    def started(self):
        return dict(line.split("=", 1) for line in (self.tmp / "started").read_text().splitlines())

    def test_launcher_refuses_to_run_inside_a_desktop(self):
        result = self.launch(WAYLAND_DISPLAY="wayland-1")
        self.assertEqual(result.returncode, 1)
        self.assertIn("ORB-S03", result.stderr)
        self.assertFalse((self.tmp / "started").exists())

    def test_launcher_falls_back_to_plain_cosmic_when_orbit_is_missing(self):
        result = self.launch()
        self.assertEqual(result.returncode, 0, result.stderr)
        started = self.started()
        self.assertEqual(started["args"], "")  # plain start-cosmic, not --in-login-shell
        self.assertNotIn(str(self.prefix), started["PATH"])
        log = (self.home / ".local/state/orbit/session.log").read_text()
        self.assertIn("ORB-S01", log)
        # The notification is sent from a background process; wait for it so
        # it can't write into the temp folder while it's being removed.
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if self.calls.exists() and "notify-send" in self.calls.read_text():
                break
            time.sleep(0.05)
        self.assertIn("ORB-S01", self.calls.read_text())

    def test_launcher_runs_cosmic_with_orbit_first_and_restores_on_exit(self):
        self.assertEqual(self.install().returncode, 0)
        result = self.launch()
        self.assertEqual(result.returncode, 0, result.stderr)
        started = self.started()
        self.assertEqual(started["args"], "--in-login-shell")
        self.assertTrue(started["PATH"].startswith(f"{self.prefix}/bin:"))
        self.assertTrue(started["XDG_DATA_DIRS"].startswith(f"{self.prefix}/share:"))
        self.assertEqual(started["ORBIT_SESSION"], "1")
        engine = self.home / ".config/cosmic/com.system76.CosmicComp/v1/tiling_engine"
        self.assertEqual(engine.read_text(), "Scrolling\n")
        calls = self.calls.read_text()
        self.assertIn(f"systemctl --user set-environment PATH={self.stubs}:/usr/bin:/bin", calls)
        self.assertIn("systemctl --user unset-environment XDG_DATA_DIRS", calls)

    def test_launcher_keeps_an_existing_engine_choice(self):
        self.assertEqual(self.install().returncode, 0)
        engine = self.home / ".config/cosmic/com.system76.CosmicComp/v1/tiling_engine"
        engine.parent.mkdir(parents=True)
        engine.write_text("Classic\n")
        self.assertEqual(self.launch().returncode, 0)
        self.assertEqual(engine.read_text(), "Classic\n")


if __name__ == "__main__":
    unittest.main()
