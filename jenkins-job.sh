#!/bin/bash

BUILD_SCRIPT_VERSION="1.0.0"
BUILD_SCRIPT_NAME=`basename ${0}`

# These are used by in following functions, declare them here so that
# they are defined even when we're only sourcing this script
BUILD_TIME_STR="TIME: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} %e %S %U %P %c %w %R %F %M %x %C"

BUILD_TIMESTAMP_START=`date -u +%s`
BUILD_TIMESTAMP_OLD=${BUILD_TIMESTAMP_START}

pushd `dirname $0` > /dev/null
BUILD_WORKSPACE=`pwd -P`
popd > /dev/null

BUILD_DIR="shr-core"
BUILD_TOPDIR="${BUILD_WORKSPACE}/${BUILD_DIR}"
BUILD_TIME_LOG=${BUILD_TOPDIR}/time.txt

function print_timestamp {
    BUILD_TIMESTAMP=`date -u +%s`
    BUILD_TIMESTAMPH=`date -u +%Y%m%dT%TZ`

    local BUILD_TIMEDIFF=`expr ${BUILD_TIMESTAMP} - ${BUILD_TIMESTAMP_OLD}`
    local BUILD_TIMEDIFF_START=`expr ${BUILD_TIMESTAMP} - ${BUILD_TIMESTAMP_START}`
    BUILD_TIMESTAMP_OLD=${BUILD_TIMESTAMP}
    printf "TIME: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} ${1}: ${BUILD_TIMESTAMP}, +${BUILD_TIMEDIFF}, +${BUILD_TIMEDIFF_START}, ${BUILD_TIMESTAMPH}\n" | tee -a ${BUILD_TIME_LOG}
}

function parse_job_name {
    case ${JOB_NAME} in
        oe_world_*)
            BUILD_VERSION="world"
            ;;
        *)
            echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Unrecognized version in JOB_NAME: '${JOB_NAME}', it should start with oe_ and 'world'"
            exit 1
            ;;
    esac

    case ${JOB_NAME} in
        *_qemuarm)
            BUILD_MACHINE="qemuarm"
            ;;
        *_qemux86)
            BUILD_MACHINE="qemux86"
            ;;
        *_qemux86-64)
            BUILD_MACHINE="qemux86-64"
            ;;
        *_workspace-*)
            # global jobs
            ;;
        *)
            echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Unrecognized machine in JOB_NAME: '${JOB_NAME}', it should end with '_qemuarm', '_qemux86', '_qemux86-64'"
            exit 1
            ;;
    esac

    case ${JOB_NAME} in
        *_workspace-cleanup)
            BUILD_TYPE="cleanup"
            ;;
        *_workspace-compare-signatures)
            BUILD_TYPE="compare-signatures"
            ;;
        *_workspace-prepare)
            BUILD_TYPE="prepare"
            ;;
        *_test-dependencies_*)
            BUILD_TYPE="test-dependencies"
            ;;
        *)
            BUILD_TYPE="build"
            ;;
    esac
}

function run_build {
    declare -i RESULT=0

    make update 2>&1
    cd ${BUILD_TOPDIR}
    . ./setup-env
    export MACHINE=${BUILD_MACHINE}
    LOGDIR=log.world.`date "+%Y%m%d_%H%M%S"`.log
    mkdir ${LOGDIR}
    rm -rf tmp-glibc/*;
    mkdir tmp-glibc || echo "tmp-glibc already exists"
    mount | grep "${BUILD_TOPDIR}/tmp-glibc type tmpfs" && echo "Some tmp-glibc already has tmpfs mounted, skipping mount" || mount tmp-glibc
    #for T in gcc core-image-sato qt4-x11-free qt4-embedded webkit-gtk webkit-efl shr-image-all world world-image; do
    for T in world; do
        time bitbake -k ${T}  2>&1 | tee -a ${LOGDIR}/bitbake.${T}.log || break;
        RESULT+=${PIPESTATUS[0]}
    done  2>&1 | tee ${LOGDIR}/bitbake.log;
    cat tmp-glibc/qa.log >> ${LOGDIR}/qa.log || echo "No QA issues";

    cp conf/world* ${LOGDIR}
    rsync -avir ${LOGDIR} jenkins@logs.nslu2-linux.org:htdocs/buildlogs/oe/world
    cat ${LOGDIR}/qa.log && true

    cat << EOF > sstate-sysroot-cruft-whitelist.txt
[^/]*/home/builder
[^/]*/usr/src/kernel/patches
[^/]*/usr/src/kernel/scripts/.*
[^/]*/usr/lib/gdk-pixbuf-2.0/.*/loaders.cache
[^/]*/etc/sgml/sgml-docbook.cat
[^/]*/usr/src/kernel/patches
[^/]*/etc/sgml/sgml-docbook.cat
[^/]*/usr/lib/python3.3/__pycache__
[^/]*/usr/lib/python3.3/[^/]*/__pycache__
[^/]*/usr/lib/python3.3/[^/]*/[^/]*/__pycache__
[^/]*/usr/share/dbus
[^/]*/usr/share/dbus/dbus-bus-introspect.xml
[^/]*/usr/share/dbus/session.conf
[^/]*/usr/bin/crossscripts/guile-config
[^/]*/usr/lib/python2.7/config/libpython2.7.so
[^/]*/var
[^/]*/usr/bin/i586-oe-linux-g77
[^/]*/usr/bin/x86_64-oe-linux-g77
[^/]*/usr/bin/arm-oe-linux-gnueabi-g77
[^/]*/usr/lib/php/\.channels.*
[^/]*/usr/lib/php/\.registry.*
[^/]*/usr/lib/php/\.depdb.*
[^/]*/usr/lib/php/\.filemap
[^/]*/usr/lib/php/\.lock
[^/]*/usr/lib/gdk-pixbuf-2.0/.*/loaders.cache
[^/]*/usr/include/ruby-1.9.1/i386-linux
[^/]*/usr/include/ruby-1.9.1/i386-linux/ruby
[^/]*/usr/include/ruby-1.9.1/i386-linux/ruby/config.h
[^/]*/usr/include/ruby-1.9.1/ruby/win32.h
[^/]*/usr/lib/ruby/i386-linux
[^/]*/usr/lib/ruby/i386-linux/fake.rb
[^/]*/usr/lib/ruby/i386-linux/libruby.so.1.9.1
[^/]*/usr/lib/ruby/i386-linux/libruby-static.a
[^/]*/usr/lib/ruby/i386-linux/rbconfig.rb
[^/]*/usr/lib/qt4/plugins
[^/]*/usr/lib/qt4/plugins/webkit
[^/]*/usr/lib/qt5/plugins/webkit
EOF

    mkdir ${LOGDIR}/sysroot-cruft/
    openembedded-core/scripts/sstate-sysroot-cruft.sh --tmpdir=tmp-glibc --whitelist=sstate-sysroot-cruft-whitelist.txt 2>&1 | tee ${LOGDIR}/sysroot-cruft/sstate-sysroot-cruft.log
    RESULT+=${PIPESTATUS[0]}

    OUTPUT2=`grep "INFO: Output written in: " ${LOGDIR}/sysroot-cruft/sstate-sysroot-cruft.log | sed 's/INFO: Output written in: //g'`
    ls   ${OUTPUT2}/diff* ${OUTPUT2}/used.whitelist.txt ${OUTPUT2}/duplicates.txt >/dev/null 2>/dev/null && \
      cp ${OUTPUT2}/diff* ${OUTPUT2}/used.whitelist.txt ${OUTPUT2}/duplicates.txt ${LOGDIR}/sysroot-cruft/

    # wait for pseudo
    sleep 180
    umount tmp-glibc || echo "Umounting tmp-glibc failed"
    rm -rf tmp-glibc/*;

    exit ${RESULT}
}

function run_cleanup {
    if [ -d ${BUILD_TOPDIR} ] ; then
        cd ${BUILD_TOPDIR};
        du -hs sstate-cache
        openembedded-core/scripts/sstate-cache-management.sh --extra-archs=core2-64,i586,armv5te,qemuarm,qemux86,qemux86_64 -L --cache-dir=sstate-cache -d -y || true
        du -hs sstate-cache
        mkdir old || true
        umount tmp-glibc || true
        mv -f cache/bb_codeparser.dat* bitbake.lock pseudodone tmp-glibc* old || true
        rm -rf old
    fi
    echo "Cleanup finished"
}

function run_compare-signatures {
    declare -i RESULT=0

    cd ${BUILD_TOPDIR}
    . ./setup-env

    LOGDIR=log.signatures.`date "+%Y%m%d_%H%M%S"`.log
    mkdir ${LOGDIR}
    rm -rf tmp-glibc/*;
    mount | grep "tmp-glibc type tmpfs" && echo "Some tmp-glibc already has tmpfs mounted, skipping mount" || mount tmp-glibc

    openembedded-core/scripts/sstate-diff-machines.sh --machines="qemux86copy qemux86 qemuarm" --targets=world --tmpdir=tmp-glibc/ --analyze 2>&1 | tee ${LOGDIR}/signatures.log
    RESULT+=${PIPESTATUS[0]}

    OUTPUT=`grep "INFO: Output written in: " ${LOGDIR}/signatures.log | sed 's/INFO: Output written in: //g'`
    ls ${OUTPUT}/signatures.*.*.log >/dev/null 2>/dev/null && cp ${OUTPUT}/signatures.*.*.log ${LOGDIR}/

    rsync -avir ${LOGDIR} jenkins@logs.nslu2-linux.org:htdocs/buildlogs/oe/world

    [ -d sstate-diff ] || mkdir sstate-diff
    mv tmp-glibc/sstate-diff/* sstate-diff

    umount tmp-glibc || echo "Umounting tmp-glibc failed"
    rm -rf tmp-glibc/*;

    exit ${RESULT}
}

function run_prepare {
    [ -f Makefile ] && echo "Makefile exists (ok)" || wget http://shr.bearstech.com/Makefile
    sed -i 's#BRANCH_COMMON = .*#BRANCH_COMMON = jansa/master-all#g' Makefile

    make update-common

    echo "UPDATE_CONFFILES_ENABLED = 1" > config.mk
    echo "RESET_ENABLED = 1" >> config.mk
    [ -d ${BUILD_TOPDIR} ] && echo "${BUILD_DIR} already checked out (ok)" || make setup-shr-core 2>&1
    make update-conffiles 2>&1

    cp common/conf/local.conf ${BUILD_TOPDIR}/conf/local.conf
    sed -i 's/#PARALLEL_MAKE.*/PARALLEL_MAKE = "-j 8"/'          ${BUILD_TOPDIR}/conf/local.conf
    sed -i 's/#BB_NUMBER_THREADS.*/BB_NUMBER_THREADS = "5"/'     ${BUILD_TOPDIR}/conf/local.conf
    sed -i 's/# INHERIT += "rm_work"/INHERIT += "rm_work"/'      ${BUILD_TOPDIR}/conf/local.conf

    # Reminder to change it later when we have public instance
    sed -i 's/PRSERV_HOST = "localhost:0"/PRSERV_HOST = "localhost:0"/' ${BUILD_TOPDIR}/conf/local.conf

    echo 'BB_GENERATE_MIRROR_TARBALLS = "1"'                  >> ${BUILD_TOPDIR}/conf/local.conf
    if [ ! -d ${BUILD_TOPDIR}/buildhistory/ ] ; then
        cd ${BUILD_TOPDIR}/
        git clone git@github.com:shr-project/jenkins-buildhistory.git
        cd buildhistory;
        git checkout -b oe-world origin/oe-world || git checkout -b oe-world
        cd ../..
    fi

    echo 'BUILDHISTORY_DIR = "${TOPDIR}/buildhistory"'                           >> ${BUILD_TOPDIR}/conf/local.conf
    echo 'BUILDHISTORY_COMMIT ?= "1"'                                            >> ${BUILD_TOPDIR}/conf/local.conf
    echo 'BUILDHISTORY_COMMIT_AUTHOR ?= "Martin Jansa <Martin.Jansa@gmail.com>"' >> ${BUILD_TOPDIR}/conf/local.conf
    echo 'BUILDHISTORY_PUSH_REPO ?= "origin oe-world"'          >> ${BUILD_TOPDIR}/conf/local.conf
    sed 's/^DISTRO/#DISTRO/g' -i ${BUILD_TOPDIR}/setup-local

    echo 'require world_fixes.inc' >> ${BUILD_TOPDIR}/conf/local.conf
    cat > ${BUILD_TOPDIR}/conf/world_fixes.inc << EOF
PREFERRED_PROVIDER_udev = "systemd"

PREFERRED_VERSION_chromium = "37.%"

#PREFERRED_VERSION_gupnp = "0.19.3"
#PREFERRED_VERSION_gssdp = "0.13.2"
#PREFERRED_VERSION_gupnp-av = "0.11.6"

#mplayer2 needs this
# PREFERRED_VERSION_libav = "9.13"
# PREFERRED_VERSION_libpostproc = "0.0.0+git%"
# PREFERRED_PROVIDER_libpostproc = "libpostproc"
PNBLACKLIST[mplayer2] = ""

# use gold
DISTRO_FEATURES_append = " ld-is-gold"

# use systemd
DISTRO_FEATURES_append = " systemd"
DISTRO_FEATURES_BACKFILL_CONSIDERED = "sysvinit"
VIRTUAL-RUNTIME_init_manager = "systemd"
VIRTUAL-RUNTIME_initscripts = ""

# use opengl
DISTRO_FEATURES_append = " opengl"

# use wayland to fix building weston and qtwayland
DISTRO_FEATURES_append = " wayland"

PREFERRED_PROVIDER_jpeg = "libjpeg-turbo"
PREFERRED_PROVIDER_jpeg-native = "libjpeg-turbo-native"
PREFERRED_PROVIDER_gpsd = "gpsd"
PREFERRED_PROVIDER_e-wm-sysactions = "e-wm"
ESYSACTIONS = "e-wm-sysactions"

# don't pull libhybris unless explicitly asked for
PREFERRED_PROVIDER_virtual/libgl ?= "mesa"
PREFERRED_PROVIDER_virtual/libgles1 ?= "mesa"
PREFERRED_PROVIDER_virtual/libgles2 ?= "mesa"
PREFERRED_PROVIDER_virtual/egl ?= "mesa"

# to fix fsoaudiod, alsa-state conflict in shr-image-all
VIRTUAL-RUNTIME_alsa-state = "fsoaudiod"
# to fix apm, fso-apm conflict in shr-image-all
VIRTUAL-RUNTIME_apm = "fso-apm"

require conf/distro/include/qt5-versions.inc

# for qtwebkit etc
# see https://bugzilla.yoctoproject.org/show_bug.cgi?id=5013
# DEPENDS_append_pn-qtbase = " mesa"
PACKAGECONFIG_append_pn-qtbase = " icu gl accessibility"

# for webkit-efl
PACKAGECONFIG_append_pn-harfbuzz = " icu"

inherit blacklist
# PNBLACKLIST[samsung-rfs-mgr] = "needs newer libsamsung-ipc with negative D_P: Requested 'samsung-ipc-1.0 >= 0.2' but version of libsamsung-ipc is 0.1.0"
PNBLACKLIST[android-system] = "depends on lxc from meta-virtualiazation which isn't included in my world builds"
PNBLACKLIST[bigbuckbunny-1080p] = "big and doesn't really need to be tested so much"
PNBLACKLIST[bigbuckbunny-480p] = "big and doesn't really need to be tested so much"
PNBLACKLIST[bigbuckbunny-720p] = "big and doesn't really need to be tested so much"
PNBLACKLIST[bigbuckbunny-720p] = "big and doesn't really need to be tested so much"
PNBLACKLIST[tearsofsteel-1080p] = "big and doesn't really need to be tested so much"

# enable reporting
# needs http://patchwork.openembedded.org/patch/68735/
ERR_REPORT_SERVER = "errors.yoctoproject.org"
ERR_REPORT_PORT = "80"
ERR_REPORT_USERNAME = "Martin Jansa"
ERR_REPORT_EMAIL = "Martin.Jansa@gmail.com"
ERR_REPORT_UPLOAD_FAILURES = "1"
INHERIT += "report-error"

# needs patch with buildstats-summary.bbclass
INHERIT += "buildstats buildstats-summary"
EOF
}

function run_test-dependencies {
    declare -i RESULT=0

    make update 2>&1
    cd ${BUILD_TOPDIR}
    . ./setup-env

    export MACHINE=${BUILD_MACHINE}
    LOGDIR=log.dependencies.`date "+%Y%m%d_%H%M%S"`.log
    mkdir ${LOGDIR}

    rm -rf tmp-glibc/*;
    [ -d tmp-glibc ] || mkdir tmp-glibc
    mount | grep "${BUILD_TOPDIR}/tmp-glibc type tmpfs" && echo "Some tmp-glibc already has tmpfs mounted, skipping mount" || mount tmp-glibc

    [ -f failed-recipes.log ] || ls -d buildhistory/packages/*/* | xargs -n 1 basename | sort -u > failed-recipes.log
    [ -f failed-recipes.log ] && RECIPES="--recipes=failed-recipes.log"

    # backup full buildhistory and replace it with link to tmpfs
    mv buildhistory buildhistory-all
    mkdir tmp-glibc/buildhistory
    ln -s tmp-glibc/buildhistory .

    rm -f tmp-glibc/qa.log

    time openembedded-core/scripts/test-dependencies.sh --tmpdir=tmp-glibc $RECIPES 2>&1 | tee -a ${LOGDIR}/test-dependencies.log
    RESULT+=${PIPESTATUS[0]}

    # restore full buildhistory
    rm -rf buildhistory
    mv buildhistory-all buildhistory

    cat tmp-glibc/qa.log >> ${LOGDIR}/qa.log 2>/dev/null || echo "No QA issues";

    OUTPUT=`grep "INFO: Output written in: " ${LOGDIR}/test-dependencies.log | sed 's/INFO: Output written in: //g'`

    # we want to preserve only partial artifacts
    [ -d ${LOGDIR}/1_all ] || mkdir -p ${LOGDIR}/1_all
    [ -d ${LOGDIR}/2_max/failed ] || mkdir -p ${LOGDIR}/2_max/failed
    [ -d ${LOGDIR}/3_min/failed ] || mkdir -p ${LOGDIR}/3_min/failed

    for f in dependency-changes.error.log dependency-changes.warn.log \
             failed-recipes.log 1_all/complete.log \
             1_all/failed-tasks.log 1_all/failed-recipes.log \
             2_max/failed-tasks.log 2_max/failed-recipes.log \
             3_min/failed-tasks.log 3_min/failed-recipes.log; do
        [ -f ${OUTPUT}/${f} ] && cp -l ${OUTPUT}/${f} ${LOGDIR}/${f}
    done

    ls ${OUTPUT}/2_max/failed/*.log >/dev/null 2>/dev/null && cp -l ${OUTPUT}/2_max/failed/*.log ${LOGDIR}/2_max/failed
    ls ${OUTPUT}/3_min/failed/*.log >/dev/null 2>/dev/null && cp -l ${OUTPUT}/3_min/failed/*.log ${LOGDIR}/3_min/failed

    cp conf/world* ${LOGDIR}
    rsync -avir ${LOGDIR} jenkins@logs.nslu2-linux.org:htdocs/buildlogs/oe/world
    [ -s ${LOGDIR}/qa.log ] && cat ${LOGDIR}/qa.log

    # wait for pseudo
    sleep 180
    umount tmp-glibc || echo "Umounting tmp-glibc failed"
    rm -rf tmp-glibc/*;

    exit ${RESULT}
}

print_timestamp start
parse_job_name

echo "INFO: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Running: '${BUILD_TYPE}', machine: '${BUILD_MACHINE}', version: '${BUILD_VERSION}'"

case ${BUILD_TYPE} in
    cleanup)
        run_cleanup
        ;;
    compare-signatures)
        run_compare-signatures
        ;;
    prepare)
        run_prepare
        ;;
    test-dependencies)
        run_test-dependencies
        ;;
    build)
        run_build
        ;;
    *)
        echo "ERROR: ${BUILD_SCRIPT_NAME}-${BUILD_SCRIPT_VERSION} Unrecognized build type: '${BUILD_TYPE}', script doesn't know how to execute such job"
        exit 1
        ;;
esac
