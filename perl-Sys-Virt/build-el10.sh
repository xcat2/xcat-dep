#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPEC="$SCRIPT_DIR/Sys-Virt.spec"
MOCK_CFG="${MOCK_CFG:-almalinux-10-x86_64}"
WORK_DIR="${WORK_DIR:-/tmp/perl-Sys-Virt-mockbuild}"
RESULT_DIR="${RESULT_DIR:-$REPO_ROOT/build-output/perl-Sys-Virt}"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/build-logs/perl-Sys-Virt}"

# --- Deterministic build timestamp ---
if [[ -z "${SOURCE_DATE_EPOCH:-}" ]]; then
    if [[ -f "$REPO_ROOT/Gitepoch" ]]; then
        SOURCE_DATE_EPOCH="$(cat "$REPO_ROOT/Gitepoch")"
    else
        SOURCE_DATE_EPOCH="$(git -C "$REPO_ROOT" log -1 --format=%ct HEAD 2>/dev/null || date +%s)"
    fi
fi
export SOURCE_DATE_EPOCH

echo "== Configuration =="
echo "spec:       $SPEC"
echo "mock_cfg:   $MOCK_CFG"
echo "work_dir:   $WORK_DIR"
echo "result_dir: $RESULT_DIR"
echo "log_dir:    $LOG_DIR"
echo "SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$RESULT_DIR" "$LOG_DIR"

# --- Deterministic mock config overlay ---
DET_MOCK_CFG="$WORK_DIR/mock-deterministic.cfg"
cat > "$DET_MOCK_CFG" <<EOF
include('/etc/mock/${MOCK_CFG}.cfg')
config_opts['environment']['SOURCE_DATE_EPOCH'] = '${SOURCE_DATE_EPOCH}'
EOF

MOCK_UNIQUEEXT="${MOCK_UNIQUEEXT:-perl-sys-virt-$$}"

# --- Build SRPM via mock ---
echo ""
echo "== Build SRPM =="
SRPM_OUT="$WORK_DIR/srpm"
mkdir -p "$SRPM_OUT"
mock -r "$DET_MOCK_CFG" \
    --uniqueext "$MOCK_UNIQUEEXT" \
    --buildsrpm \
    --spec "$SPEC" \
    --sources "$SCRIPT_DIR" \
    --define "use_source_date_epoch_as_buildtime 1" \
    --define "clamp_mtime_to_source_date_epoch 1" \
    --define "_buildhost xcat-build" \
    --resultdir "$SRPM_OUT" \
    2>&1 | tee "$LOG_DIR/mock-buildsrpm.log"

SRPM="$(ls -t "$SRPM_OUT"/*.src.rpm 2>/dev/null | head -1)"
if [[ -z "$SRPM" ]]; then
    echo "ERROR: No SRPM produced"
    exit 1
fi
echo "SRPM: $SRPM"

# --- Rebuild RPM via mock ---
echo ""
echo "== Rebuild RPM =="
RPM_OUT="$WORK_DIR/rpm"
mkdir -p "$RPM_OUT"
mock -r "$DET_MOCK_CFG" \
    --uniqueext "$MOCK_UNIQUEEXT" \
    --rebuild "$SRPM" \
    --define "use_source_date_epoch_as_buildtime 1" \
    --define "clamp_mtime_to_source_date_epoch 1" \
    --define "_buildhost xcat-build" \
    --resultdir "$RPM_OUT" \
    2>&1 | tee "$LOG_DIR/mock-rebuild.log"

# --- Collect artifacts ---
echo ""
echo "== Collect artifacts =="
cp -v "$RPM_OUT"/*.rpm "$RESULT_DIR/"
for log in build.log root.log state.log hw_info.log installed_pkgs.log; do
    [[ -f "$RPM_OUT/$log" ]] && cp "$RPM_OUT/$log" "$LOG_DIR/"
done

echo ""
echo "== Completed =="
ls -lh "$RESULT_DIR"/*.rpm
echo "Artifacts: $RESULT_DIR"
echo "Logs:      $LOG_DIR"
