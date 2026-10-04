#!/usr/bin/env python3
"""End-to-end autoinstall test for the X live ISO (local only, no CI).

Automates the full unattended path in QEMU:

  1. Boots the live ISO (BIOS/syslinux or UEFI/GRUB) and selects the
     "autoinstall" menu entry by sending its hotkey ('a') through the QEMU
     monitor.
  2. Attaches a seed disk labeled `cidata` with x-install.json, so
     x-autoinstall.service runs the text installer.
  3. Waits on the serial console for `installation complete` and a zero
     installer exit code; fails on known error markers.
  4. Powers the guest off cleanly via ACPI.
  5. Boots the installed disk, logs in on the serial console (ttyS0) and
     asserts `x gen status` (running/default = 0001) and `x gen verify`
     (live system matches generation 0001).

Everything is local: this is the repeatable harness for the VM validation
door. It needs no GitHub Actions and no root on the host (QEMU/KVM only).

Requires: qemu-system-x86_64, qemu-img, python3, mkfs.vfat + mcopy (dosfstools,
mtools); for --mode uefi the OVMF 4m firmware (edk2-ovmf).

Usage:
    ./tests/e2e-autoinstall.py --mode uefi
    ./tests/e2e-autoinstall.py --mode bios --profile core --encryption no
    ./tests/e2e-autoinstall.py --mode uefi --iso out/x-2026.10.03-x86_64.iso
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

SELF_DIR = Path(__file__).resolve().parent
X_DIR = SELF_DIR.parent
WORKSPACE = X_DIR.parent

OVMF_CODE = Path("/usr/share/edk2/x64/OVMF_CODE.4m.fd")
OVMF_VARS = Path("/usr/share/edk2/x64/OVMF_VARS.4m.fd")

RUNNING_ID = "0001"


class E2EError(RuntimeError):
    pass


class E2EExpectTimeout(E2EError):
    pass


def log(msg: str) -> None:
    print(f"[e2e] {msg}", flush=True)


class Console:
    """Serial console over a QEMU unix chardev (we connect, QEMU listens)."""

    def __init__(self, sock_path: Path, log_path: Path) -> None:
        self.sock_path = sock_path
        self.log = open(log_path, "wb")
        self.text = ""
        self.cursor = 0
        self.sock: socket.socket | None = None

    def connect(self, timeout: float = 20.0) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(str(self.sock_path))
                s.settimeout(0.25)
                self.sock = s
                return
            except OSError:
                time.sleep(0.1)
        raise E2EError(f"serial console {self.sock_path} did not accept a connection")

    def pump(self, duration: float) -> None:
        assert self.sock is not None
        end = time.time() + duration
        while True:
            remain = end - time.time()
            if remain <= 0:
                return
            self.sock.settimeout(min(0.25, remain))
            try:
                data = self.sock.recv(4096)
            except socket.timeout:
                continue
            if not data:
                return
            self.log.write(data)
            self.log.flush()
            self.text += data.decode("utf-8", "replace")

    def expect(
        self,
        pattern: str,
        timeout: float,
        *,
        fails: list[str] | None = None,
        start: int | None = None,
    ) -> tuple[re.Match[str], str]:
        rx = re.compile(pattern)
        frx = [re.compile(p) for p in (fails or [])]
        pos = self.cursor if start is None else start
        deadline = time.time() + timeout
        while True:
            m = rx.search(self.text, pos)
            if m:
                self.cursor = m.end()
                return m, self.text[pos : m.end()]
            if frx:
                for f in frx:
                    fm = f.search(self.text, pos)
                    if fm:
                        raise E2EError(
                            f"failure marker {f.pattern!r} found:\n{self.tail()}"
                        )
            if time.time() >= deadline:
                raise E2EExpectTimeout(
                    f"timeout waiting for {pattern!r} after {timeout:.0f}s\n{self.tail()}"
                )
            self.pump(0.3)

    def expect_opt(self, pattern: str, timeout: float) -> bool:
        try:
            self.expect(pattern, timeout)
            return True
        except E2EExpectTimeout:
            return False

    def send(self, data: str) -> None:
        assert self.sock is not None
        self.sock.sendall(data.encode())

    def tail(self, n: int = 3000) -> str:
        return self.text[-n:]

    def close(self) -> None:
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass
        self.log.close()


class Monitor:
    """QEMU HMP monitor over a unix socket."""

    def __init__(self, sock_path: Path) -> None:
        self.sock_path = sock_path
        self.sock: socket.socket | None = None

    def connect(self, timeout: float = 20.0) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(str(self.sock_path))
                s.settimeout(0.25)
                self.sock = s
                time.sleep(0.1)
                try:
                    s.recv(4096)
                except OSError:
                    pass
                return
            except OSError:
                time.sleep(0.1)
        raise E2EError(f"monitor {self.sock_path} did not accept a connection")

    def cmd(self, line: str) -> None:
        assert self.sock is not None
        self.sock.sendall((line + "\n").encode())

    def sendkey(self, key: str) -> None:
        self.cmd(f"sendkey {key}")

    def powerdown(self) -> None:
        self.cmd("system_powerdown")

    def quit(self) -> None:
        self.cmd("quit")

    def close(self) -> None:
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass


class E2E:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.workdir = Path(args.workdir).resolve()
        self.disk = self.workdir / "disk.qcow2"
        self.vars = self.workdir / "OVMF_VARS.fd"
        self.seed = self.workdir / "cidata.img"
        self.console: Console | None = None
        self.monitor: Monitor | None = None
        self.proc: subprocess.Popen[bytes] | None = None

    # --- preparation -----------------------------------------------------
    def which(self, *tools: str) -> None:
        missing = [t for t in tools if shutil.which(t) is None]
        if missing:
            raise E2EError(f"missing required tools: {', '.join(missing)}")

    def prepare(self) -> None:
        for tool in ("qemu-system-x86_64", "qemu-img", "mkfs.vfat", "mcopy"):
            self.which(tool)
        if not self.args.iso.is_file():
            raise E2EError(f"ISO not found: {self.args.iso}")
        if self.args.mode == "uefi":
            for f in (OVMF_CODE, OVMF_VARS):
                if not f.is_file():
                    raise E2EError(f"OVMF firmware not found: {f}")

        self.workdir.mkdir(parents=True, exist_ok=True)
        for stale in ("serial.sock", "monitor.sock"):
            (self.workdir / stale).unlink(missing_ok=True)
        for stale in ("serial.log", "qemu.log"):
            (self.workdir / stale).unlink(missing_ok=True)

        log(f"ISO     {self.args.iso}")
        log(f"workdir {self.workdir}")

        if self.args.skip_install:
            if not self.disk.exists():
                raise E2EError(f"--skip-install: no installed disk in {self.workdir}")
            log("reusing the installed disk (--skip-install)")
            return

        self.disk.unlink(missing_ok=True)
        subprocess.run(
            ["qemu-img", "create", "-f", "qcow2", str(self.disk), self.args.disk_size],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        seed_json = self.workdir / "x-install.json"
        luks = f',"luks_password":"{self.args.password}"' if self.args.encryption == "yes" else ""
        hypr = "yes" if self.args.hyprland else "no"
        seed_json.write_text(
            "{"
            f'"disk":"/dev/vda","hostname":"{self.args.hostname}",'
            f'"username":"{self.args.user}","password":"{self.args.password}",'
            f'"profile":"{self.args.profile}","bootloader":"{self.args.bootloader}",'
            f'"encryption":"{self.args.encryption}","hyprland":"{hypr}"{luks},'
            '"kernel_params":"console=ttyS0"'
            "}\n"
        )
        subprocess.run(
            ["qemu-img", "create", "-f", "raw", str(self.seed), "64M"],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        subprocess.run(["mkfs.vfat", "-n", "cidata", str(self.seed)], check=True, stdout=subprocess.DEVNULL)
        subprocess.run(
            ["mcopy", "-i", str(self.seed), str(seed_json), "::x-install.json"],
            check=True,
        )
        if self.args.mode == "uefi":
            shutil.copyfile(OVMF_VARS, self.vars)

    # --- QEMU ------------------------------------------------------------
    def qemu_cmd(self, boot: str) -> list[str]:
        accel: list[str] = ["-enable-kvm", "-cpu", "host"] if self.args.kvm else []
        fw: list[str] = []
        if self.args.mode == "uefi":
            fw = [
                "-drive", f"file={OVMF_CODE},if=pflash,format=raw,readonly=on",
                "-drive", f"file={self.vars},if=pflash,format=raw",
            ]
        cmd = [
            "qemu-system-x86_64",
            *accel,
            "-m", str(self.args.ram),
            "-smp", str(self.args.cpus),
            *fw,
        ]
        if boot == "iso":
            cmd += [
                "-cdrom", str(self.args.iso),
                "-drive", f"file={self.disk},if=virtio,format=qcow2",
                "-drive", f"file={self.seed},format=raw,if=virtio",
                "-boot", "order=d,menu=on",
            ]
        else:
            cmd += [
                "-drive", f"file={self.disk},if=virtio,format=qcow2",
                "-boot", "order=c,menu=on",
            ]
        cmd += [
            "-netdev", "user,id=net0",
            "-device", "virtio-net-pci,netdev=net0",
            "-display", "none",
            "-serial", f"unix:{self.workdir / 'serial.sock'},server=on,wait=on",
            "-monitor", f"unix:{self.workdir / 'monitor.sock'},server=on,wait=off",
        ]
        return cmd

    def start_qemu(self, boot: str) -> None:
        qlog = open(self.workdir / "qemu.log", "ab")
        self.proc = subprocess.Popen(self.qemu_cmd(boot), stdout=qlog, stderr=subprocess.STDOUT)
        self.console = Console(self.workdir / "serial.sock", self.workdir / "serial.log")
        self.console.connect()
        self.monitor = Monitor(self.workdir / "monitor.sock")
        self.monitor.connect()

    def stop_qemu(self, timeout: float = 150.0) -> None:
        assert self.proc is not None and self.monitor is not None and self.console is not None
        if self.proc.poll() is not None:
            return
        log("ACPI powerdown")
        self.monitor.powerdown()
        deadline = time.time() + timeout
        while self.proc.poll() is None and time.time() < deadline:
            self.console.pump(0.5)
        if self.proc.poll() is None:
            log("guest did not power off; quitting QEMU")
            self.monitor.quit()
            try:
                self.proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()

    def cleanup(self) -> None:
        if self.proc is not None and self.proc.poll() is None:
            if self.monitor is not None:
                self.monitor.quit()
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
        for obj in (self.console, self.monitor):
            if obj is not None:
                obj.close()

    # --- phases ----------------------------------------------------------
    FAILS = [
        r"autoinstall: no xauto=1; skipping",
        r"installer: no network after 120s; aborting",
        r"warning: the first generation could not be created",
        r"installer: x CLI not found in the target",
        r"autoinstall: install\.sh rc=(?!0)\d+",
    ]

    def select_autoinstall_entry(self) -> None:
        """Send the menu hotkey until the kernel starts booting."""
        assert self.console is not None and self.monitor is not None
        deadline = time.time() + 45
        while time.time() < deadline:
            self.monitor.sendkey("a")
            self.console.pump(1.0)
            # OVMF also mirrors its own messages to the serial port, so only
            # kernel/initramfs output proves the entry actually booted (the
            # non-autoinstall entries have no console=ttyS0).
            if re.search(
                r"Linux version|running early hook|systemd-udevd|autoinstall:",
                self.console.text,
            ):
                return
        raise E2EError("the autoinstall boot entry never booted (hotkey 'a' lost)")

    def phase_install(self) -> None:
        log("phase 1/2: boot the ISO and run the unattended install")
        self.start_qemu("iso")
        self.select_autoinstall_entry()
        assert self.console is not None
        self.console.expect(r"autoinstall: unattended install from", 240, fails=self.FAILS)
        log("installer running (this takes a while)")
        # The log is echoed at the end; accept either marker as completion and
        # then require the explicit rc=0 line.
        self.console.expect(
            r"installation complete|autoinstall: install\.sh rc=0",
            self.args.timeout,
            fails=self.FAILS,
        )
        self.console.expect(r"autoinstall: install\.sh rc=0", 180, fails=self.FAILS)
        self.console.pump(3)
        self.stop_qemu()
        log("phase 1 OK: unattended install finished with rc=0")

    def expect_ok(self, check: str, timeout: float = 90) -> None:
        """Run a shell check as the user and assert it succeeds."""
        assert self.console is not None
        self.console.send(f'{{ {check}; }} && echo E2E_CHK" "_OK || echo E2E_CHK" "_FAIL\n')
        _, seg = self.console.expect(r"E2E_CHK _(?:OK|FAIL)", timeout)
        if "E2E_CHK _FAIL" in seg:
            raise E2EError(f"check failed: {check}\n{seg[-800:]}")

    def verify_payload(self) -> None:
        """Assert the base tools (and the desktop payload when requested)."""
        user = self.args.user
        log("checking base tools (xfetch/xtop)")
        self.expect_ok("command -v xfetch")
        self.expect_ok("command -v xtop")
        if self.args.profile == "full" and self.args.hyprland:
            log("checking desktop payload (zsh + kitty shaders)")
            self.expect_ok(f"test -f /home/{user}/.config/kitty/shaders/x-trail.pipeline")
            self.expect_ok(f"grep -q '^custom_shaders' /home/{user}/.config/kitty/kitty.conf")
            self.expect_ok("command -v slangc")
            self.expect_ok(f"test -f /home/{user}/.zshrc")
            self.expect_ok(f"grep -q 'starship init zsh' /home/{user}/.zshrc")
            self.expect_ok("pacman -Qq noto-fonts-cjk")

    def phase_verify(self) -> None:
        log("phase 2/2: boot the installed disk and verify the generation")
        self.start_qemu("disk")
        assert self.console is not None and self.monitor is not None
        if self.args.encryption == "yes":
            # initramfs encrypt hook prompts on /dev/console (serial here).
            self.console.expect(r"[Ee]nter passphrase", self.args.boot_timeout)
            self.console.send(f"{self.args.password}\n")
            log("LUKS passphrase sent")
        self.console.expect(r"login:", self.args.boot_timeout)
        self.console.send(f"{self.args.user}\n")
        self.console.expect(r"[Pp]assword[^\n]*:", 60)
        self.console.send(f"{self.args.password}\n")
        # Wait for the shell prompt: input sent during `login` is discarded.
        self.console.expect(r"[$#] ", 60)
        self.console.send('echo E2E_LOGIN" "_OK\n')
        self.console.expect(r"E2E_LOGIN _OK", 60)
        log("logged in on the serial console")
        self.verify_payload()

        self.console.send("sudo x gen status; echo E2E_STATUS\" \"_END\n")
        if self.console.expect_opt(r"[Pp]assword[^\n]*:", 10):
            self.console.send(f"{self.args.password}\n")
        _, seg = self.console.expect(r"E2E_STATUS _END", 90)
        if not re.search(r"running:\s+" + RUNNING_ID, seg):
            raise E2EError(f"x gen status does not show running={RUNNING_ID}:\n{seg}")
        if not re.search(r"default:\s+" + RUNNING_ID, seg):
            raise E2EError(f"x gen status does not show default={RUNNING_ID}:\n{seg}")
        log(f"status OK: running/default = {RUNNING_ID}")

        self.console.send("sudo x gen verify; echo E2E_VERIFY\" \"_END\n")
        if self.console.expect_opt(r"[Pp]assword[^\n]*:", 10):
            self.console.send(f"{self.args.password}\n")
        _, seg = self.console.expect(r"E2E_VERIFY _END", 180)
        if f"live system matches generation {RUNNING_ID}" not in seg:
            raise E2EError(f"x gen verify did not report a clean match:\n{seg}")
        log(f"verify OK: live system matches generation {RUNNING_ID}")

        self.stop_qemu()
        log("phase 2 OK: installed system boots with a verified generation")

    def run(self) -> int:
        try:
            self.prepare()
            if not self.args.skip_install:
                self.phase_install()
            self.phase_verify()
            log(f"E2E OK ({self.args.mode}, profile {self.args.profile})")
            return 0
        except E2EError as exc:
            log(f"E2E FAILED: {exc}")
            log(f"serial log: {self.workdir / 'serial.log'}")
            return 1
        except Exception as exc:  # noqa: BLE001 - report and keep the logs
            log(f"E2E ERROR: {type(exc).__name__}: {exc}")
            log(f"serial log: {self.workdir / 'serial.log'}")
            return 2
        finally:
            self.cleanup()


def parse_args(argv: list[str]) -> argparse.Namespace:
    iso_default = sorted((X_DIR / "out").glob("*.iso"), key=os.path.getmtime)
    ap = argparse.ArgumentParser(
        description="E2E autoinstall test for the X live ISO (local QEMU).",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("--mode", choices=("bios", "uefi"), default="uefi")
    ap.add_argument(
        "--iso",
        type=Path,
        default=iso_default[-1] if iso_default else None,
        help="live ISO (default: newest x/out/*.iso)",
    )
    ap.add_argument("--workdir", type=Path, default=WORKSPACE / "tmp" / "e2e")
    ap.add_argument("--profile", default="core", choices=("core", "full"))
    ap.add_argument("--bootloader", default="grub", choices=("grub", "systemd-boot"))
    ap.add_argument("--encryption", default="no", choices=("no", "yes"))
    ap.add_argument(
        "--hyprland",
        action="store_true",
        help="install the Hyprland/equisdots desktop (JSON hyprland=yes)",
    )
    ap.add_argument("--hostname", default="x-vm")
    ap.add_argument("--user", default="x")
    ap.add_argument("--password", default="secret")
    ap.add_argument("--disk-size", default="32G")
    ap.add_argument("--ram", type=int, default=4096)
    ap.add_argument("--cpus", type=int, default=4)
    ap.add_argument("--no-kvm", dest="kvm", action="store_false", default=True)
    ap.add_argument("--timeout", type=float, default=2700, help="install timeout (s)")
    ap.add_argument("--boot-timeout", type=float, default=300, help="installed boot timeout (s)")
    ap.add_argument(
        "--skip-install",
        action="store_true",
        help="reuse the installed disk of --workdir (skip phase 1)",
    )
    args = ap.parse_args(argv)
    if args.iso is None:
        ap.error("no ISO in x/out; pass --iso")
    args.iso = args.iso.resolve()
    return args


if __name__ == "__main__":
    ns = parse_args(sys.argv[1:])
    try:
        sys.exit(E2E(ns).run())
    except KeyboardInterrupt:
        print("\n[e2e] interrupted")
        sys.exit(130)
