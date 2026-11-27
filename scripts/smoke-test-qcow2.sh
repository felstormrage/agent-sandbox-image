#!/usr/bin/env bash
# Boot a host qcow2 under QEMU, log in on the serial console, and check the
# basic host contract. Intended for CI after the disk artifact is built.
set -euo pipefail

qcow="${1:?usage: smoke-test-qcow2.sh <qcow2> <console-password> <kairos|fedora>}"
password="${2:?console password is required}"
flavor="${3:?flavor must be kairos or fedora}"

case "${flavor}" in
    kairos|fedora) ;;
    *) echo "unknown flavor: ${flavor}" >&2; exit 2 ;;
esac

command -v qemu-system-x86_64 >/dev/null
command -v expect >/dev/null

firmware_code="/usr/share/OVMF/OVMF_CODE_4M.fd"
firmware_vars="/usr/share/OVMF/OVMF_VARS_4M.fd"
if [[ ! -f "${firmware_code}" || ! -f "${firmware_vars}" ]]; then
    firmware_code="/usr/share/OVMF/OVMF_CODE.fd"
    firmware_vars="/usr/share/OVMF/OVMF_VARS.fd"
fi
if [[ ! -f "${firmware_code}" || ! -f "${firmware_vars}" ]]; then
    echo "OVMF firmware not found" >&2
    exit 1
fi

vars_copy="$(mktemp)"
cp "${firmware_vars}" "${vars_copy}"
trap 'rm -f "${vars_copy}"' EXIT

export SMOKE_QCOW="${qcow}"
export SMOKE_PASSWORD="${password}"
export SMOKE_FLAVOR="${flavor}"
export SMOKE_CODE="${firmware_code}"
export SMOKE_VARS="${vars_copy}"

expect <<'EOF'
set timeout 1200
log_user 0

spawn qemu-system-x86_64 -machine q35,accel=tcg -cpu max -m 4096 -smp 2 \
    -drive if=pflash,format=raw,readonly=on,file=$env(SMOKE_CODE) \
    -drive if=pflash,format=raw,file=$env(SMOKE_VARS) \
    -drive file=$env(SMOKE_QCOW),if=virtio,format=qcow2,snapshot=on \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -display none -serial stdio -monitor none -no-reboot

set login_sent 0
set password_sent 0

expect {
    -re "(?i)login:" {
        if {$login_sent == 0} {
            send "nithin\r"
            set login_sent 1
        }
        exp_continue
    }
    -re "(?i)password:" {
        if {$password_sent == 0} {
            send "$env(SMOKE_PASSWORD)\r"
            set password_sent 1
        }
        exp_continue
    }
    timeout {
        puts "Timed out waiting for the serial login prompt"
        exit 1
    }
    eof {
        puts "QEMU exited before login"
        exit 1
    }
}

after 15000
send "bash -lc 'echo SMOKE_READY'\r"
expect {
    -re "SMOKE_READY" {}
    timeout {
        puts "Timed out waiting for the shell after login"
        exit 1
    }
}

proc run_check {command label} {
    send "bash -lc '$command; echo $label=\$?'\r"
    expect {
        -re "$label=(\[0-9\]+)" {
            if {$expect_out(1,string) != 0} {
                puts "FAILED: $label"
                exit 1
            }
        }
        timeout {
            puts "Timed out waiting for $label"
            exit 1
        }
    }
}

run_check "sudo /usr/sbin/sshd -T | grep -qx \"passwordauthentication no\"" SSH_POLICY
run_check "systemctl is-active --quiet sshd" SSHD_ACTIVE

if {$env(SMOKE_FLAVOR) eq "kairos"} {
    run_check "runsc --version" RUNSC
    run_check "firecracker --version" FIRECRACKER
    run_check "sudo podman info >/dev/null" PODMAN
    run_check "test -x /usr/bin/kairos-auto-update" AUTO_UPDATE_BINARY
    run_check "systemctl is-enabled --quiet kairos-auto-update.timer" AUTO_UPDATE_TIMER
} else {
    run_check "sudo bootc status >/dev/null" BOOTC_STATUS
    run_check "systemctl is-active --quiet firewalld" FIREWALLD
    run_check "systemctl is-active --quiet auditd" AUDITD
    run_check "systemctl is-active --quiet fail2ban" FAIL2BAN
}

send "sudo /usr/bin/systemctl poweroff\r"
expect {
    eof {}
    timeout {
        puts "Timed out waiting for poweroff"
        exit 1
    }
}

puts "Boot smoke test passed for $env(SMOKE_FLAVOR)"
exit 0
EOF
