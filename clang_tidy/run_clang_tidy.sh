#!/usr/bin/env bash
set -eof pipefail

# make templates locals
# TODO(micah) maybe we should be doing shell escapes on these vars....
PATCH=$PWD/%PATCH%
CLANG_APPLY=$PWD/%CLANG_APPLY%
CLANG_TIDY=$PWD/%CLANG_TIDY%
DIFF=$PWD/%DIFF%
CONFIG_FILE=$PWD/%CONFIG_FILE%
INPUTS=(%INPUTS%)
FLAGS=(%FLAGS%)

if [[ ${#INPUTS[@]} -eq 0 ]]; then
    touch $PATCH
    exit 0
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf -- "$TMPDIR"' EXIT

# validate inputs
ls $CLANG_APPLY >/dev/null
ls $CLANG_TIDY >/dev/null
ls $DIFF >/dev/null
ls $CONFIG_FILE >/dev/null
ls ${INPUTS[@]} >/dev/null

wrap() {
    $CLANG_TIDY --config-file=$CONFIG_FILE --quiet --export-fixes=$TMPDIR/fixes.yaml ${INPUTS[@]} -- ${FLAGS[@]} &>$TMPDIR/out
}

wrap || true

# Change /dev/shm/bazel-sandbox.990c4e53bb810cdca0a6f49be5e15ddaffd702bc860d7dbaef05656c4dbfec35/processwrapper-sandbox/2833/execroot/.../x.cc
# to x.cc
sed -i $TMPDIR/out -e "s#^$PWD/##" || true

# Suppress '5966 warnings generated.'
sed -i $TMPDIR/out -e '/^[0-9][0-9]* warnings generated/d' || true

# For the sake of compactness we'll only produce one output file, the top of
# a patch file is allowed to contain anything we want before ---/+++
# so we'll just add the messages there
cat $TMPDIR/out >$PATCH
echo '' >>$PATCH

if [[ -e $TMPDIR/fixes.yaml ]]; then
    # clang-tidy produces very brittle change sets, double applying will cause
    # gross errors, for instance.
    # instead we'll produce a diff by immediately applying the fixes

    # replace PWD with fixed dir to apply
    sed -i $TMPDIR/fixes.yaml -e "s#$PWD#$TMPDIR/fixed#"

    mkdir $TMPDIR/fixed $TMPDIR/orig
    mv $TMPDIR/fixes.yaml $TMPDIR/fixed/
    for input in ${INPUTS[@]}; do
        mkdir -p $TMPDIR/orig/$(dirname $input)
        mkdir -p $TMPDIR/fixed/$(dirname $input)

        # cat to prevent accidental linking
        cat $input >$TMPDIR/orig/$input
        cat $input >$TMPDIR/fixed/$input
    done

    pushd $TMPDIR/fixed &>/dev/null
    $CLANG_APPLY .
    popd &>/dev/null

    rm $TMPDIR/fixed/fixes.yaml
    pushd $TMPDIR
    $DIFF -Naur orig/ fixed/ >>$PATCH || true
    popd &>/dev/null
fi
