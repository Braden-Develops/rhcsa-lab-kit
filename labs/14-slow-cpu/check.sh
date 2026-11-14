#!/bin/bash
. /opt/labkit/lib/check.sh
. /opt/labkit/lib/hw.sh
grubargs() { grubby --info=ALL 2>/dev/null | grep '^args='; }

section "Task 1: all CPUs, now and after reboot"
check "every present CPU is online" '[ "$(cat /sys/devices/system/cpu/online)" = "$(cat /sys/devices/system/cpu/present)" ]'
check "no kernel argument limits CPUs (grubby)" '! grubargs | grep -Eq "maxcpus=|nr_cpus="'
check "the running kernel was booted without it" '! grep -Eq "maxcpus=|nr_cpus=" /proc/cmdline'

section "Task 2: the benchmark's own limits"
check "labbench.service has no CPU quota" '[ "$(systemctl show -p CPUQuotaPerSecUSec --value labbench.service)" = infinity ]'

section "Task 3: the CPU hog"
check "no telemetry-agent process is running" '! pgrep -f /usr/local/libexec/telemetry-agent'
check "its timer is stopped and disabled (or masked), so it cannot come back" '! systemctl is-active -q telemetry-agent.timer && ! systemctl is-enabled -q telemetry-agent.timer'

section "Task 4: tuning"
check "tuned runs the profile tuned recommends for this machine" 'systemctl is-active -q tuned && [ "$(tuned-adm active | sed -n "s/^Current active profile: //p")" = "$(tuned-adm recommend)" ]'

section "Task 5: the benchmark is back to normal"
check "latest labbench run saw every CPU and finished after setup" 'l=$(tail -1 /var/log/labbench.log); echo "$l" | grep -q "cpus=$(nproc --all) " && [ $(date -d "$(echo $l | cut -d" " -f1-2)" +%s) -ge $(stat -c %Y /var/lib/labkit/setup-done) ]'

section "Task 6: hardware events (in /root/answers.txt)"
check "mce_cpu = the CPU that logged the machine check" 'answer_is mce_cpu'
check "mce_bank = its MCA bank" 'answer_is mce_bank'
check "mce_type = corrected or uncorrected, decoded from the status" 'answer_is mce_type'
check "throttled_cpu = the CPU that hit its thermal limit" 'answer_is throttled_cpu'

section "Overall"
check "rebooted since setup (persistence proven)" '[ "$(stat -c %Y /var/lib/labkit/setup-done)" -lt "$(date -d "$(uptime -s)" +%s)" ]'
summary
