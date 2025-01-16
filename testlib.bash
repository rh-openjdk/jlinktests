#!/bin/bash
set -ex
set -o pipefail

## resolve folder of this script, following all symlinks,
## http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  LIBJLINK_SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" && pwd )"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$LIBJLINK_SCRIPT_DIR/$SCRIPT_SOURCE"
done
readonly LIBJLINK_SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" && pwd )"

SKIPPED="!skipped!, because os of build is newer then os of run. !skipped!"
SKIPPED_ON_WIN="!skipped!, because is not relevant on windows. !skipped!"
SKIPPED_ON_AARCH64="!skipped!, because it fails mysteriously on aarch64 !skipped!"
SKIPPED_ON_HEADLESS_CONTAINER="!skipped!, because this is a headless container. !skipped!"
SKIPPED_ON_HEADLESS="!skipped! because this is headless system and we require X.  !skipped!"
SKIPPED_NO_RPM_INSTALL="!skipped! because a rpm install/uninstall process must be defined.  !skipped!"

function parseArguments() {
  for a in "$@"
  do
    case $a in
      --jdk=*)
        ARG_JDK="${a#*=}"
      ;;
      --report-dir=*)
        ARG_REPORT_DIR="${a#*=}"
      ;;
      *)
        echo "Unrecognized argument: '$a'" >&2
        exit 1
      ;;
    esac
  done
}

function processArguments() {
  if [[ -z $ARG_JDK ]] ; then
    echo "JDK was not specified" >&2
    exit 1
  elif ! readlink -e "$ARG_JDK" >/dev/null
  then
    echo "JDK was not found" >&2
    exit 1
  else
    readonly JAVA_DIR="$( readlink -e "$ARG_JDK" )"
  fi

  if [[ -z $ARG_REPORT_DIR ]] ; then
    echo "Report dir was not specified" >&2
    exit 1
  else
    readonly REPORT_DIR="$( readlink -m "$ARG_REPORT_DIR" )"
    mkdir -p "$REPORT_DIR"
  fi

  readonly REPORT_FILE="$REPORT_DIR/report.txt"
}

function setup() {
  if [[ ! `uname -s` == *NT* ]] ; then
    if [ "x$DISPLAY" == "x" ]; then
      # probably not working on wayland
      export DISPLAY=`(cd /tmp/.X11-unix && for x in X*; do echo ":${x#X}"; done) | head -n 1`
    else 
      echo "Using pre-set DISPLAY=$DISPLAY"
    fi
  fi
  setupModuleSources
  OUTPUT=mods
  OUTPUT_PACKS=mods-packs
  OUTPUT_JMODS=mods-jmods
  OUTPUT_JLINK=hell
  OUTPUT_JLINKS=hell-test
  OUTPUT_LAUNCH=hell-launch
  OUTPUT_SWINGLINK=hell-swing
}

function setupModuleSources() {
  if isWindows; then
    MODULE_SOURCES=$(cygpath -pm "$LIBJLINK_SCRIPT_DIR/src")
  else
    MODULE_SOURCES=$LIBJLINK_SCRIPT_DIR/src
  fi  
}

# Checks for Windows execution
function isWindows() {
  if [[ $( uname ) == *"NT"* ]]; then
    return 0
  else
    return 1
  fi
}

function clean() {
  rm -rf  $OUTPUT $OUTPUT_PACKS $OUTPUT_JMODS $OUTPUT_JLINK $OUTPUT_JLINKS $OUTPUT_LAUNCH $OUTPUT_SWINGLINK
}

function compileModules() {
  $JAVA_DIR/bin/javac -d $OUTPUT --module-source-path $MODULE_SOURCES $(find $MODULE_SOURCES -name "*.java")
}


function runModule() {
 $JAVA_DIR/bin/java --module-path $OUTPUT  --module $1
}

function createModlueJar() {
  mkdir -p $OUTPUT_PACKS || true
  $JAVA_DIR/bin/jar --create --file $OUTPUT_PACKS/"$1"module.jar --main-class $2 --module-version 1.0 -C $OUTPUT/$1 .
}

function runModularJar() {
  $JAVA_DIR/bin/java --module-path $OUTPUT_PACKS --module $1
}

function createJmod() {
  mkdir $OUTPUT_JMODS || true
  $JAVA_DIR/bin/jmod create --class-path $OUTPUT/$1 --module-path $OUTPUT --main-class  $2 --module-version 1.0 $OUTPUT_JMODS/"$1"mod.jmod
}

function createJlink() {
  local modules="--add-modules java.base"
  local i=0
  for var in "$@" ;do
    let i=i+1
    if [ $i -eq $# ] ; then
      modules+=" --output $var"
    else
      modules+=" --add-modules $var"
    fi
  done

  if isWindows; then
    $JAVA_DIR/bin/jlink --module-path $OUTPUT_JMODS $modules $include_launcher    
  else
    $JAVA_DIR/bin/jlink --module-path $JAVA_DIR/jmods:$OUTPUT_JMODS $modules $include_launcher
  fi    
}

function runJlinkedImage() {
  $PWD/$1/bin/java -m $2
}

function diffImages() {
  diff -r $PWD/$1 $PWD/$2 || true
  du $PWD/$1/lib/modules $PWD/$2/lib/modules 
}

# without cleaned images, the image cache canbe reused, and then the "hello world" is not printed out
function cleanRuntimeImages() {
  set +e
   podman image rm `podman images --format "table  {{.Repository}} {{.ID}}"  | grep "<none>" | sed "s/.* //"`
  set -e
}

# warning when podman copy dir, only its content is copied
function runImageInPodman() {
  cleanRuntimeImages
  local podmanfile=Dockerfile
  local os=$2
  local jlinkimage=$1
  local module=$3
  local DEPS=" libXext libXrender libXtst freetype util-linux"
  # on some containers you are root but do not have sudo
  # on some you are different user, but have sudo
  # only seldom you are root with sudo
  # rm on .locks is fixing strange issues on rhel7 after 1.1.2020, where suddenly useradd tester was failing
    cat <<EOF > $podmanfile
FROM $os
RUN  whoami
EOF
if [ "$os" == "quay.io/centos/centos:7" ] ; then
    cat <<EOF >> $podmanfile
RUN  sed -i -e 's!mirrorlist!#mirrorlist!g' /etc/yum.repos.d/CentOS-Base.repo
RUN  if \[ "$(uname -m)" = "aarch64" \]; then \\  
     echo "Running on arm64 architecture"; \\  
     sed -i 's|#baseurl=http://mirror.centos.org/altarch/\$releasever/|baseurl=http://vault.centos.org/altarch/7.9.2009/|' /etc/yum.repos.d/CentOS-Base.repo; \\  
   elif \[ "$(uname -m)" = "ppc64le" \]; then \\  
     echo "Running on ppc64le architecture"; \\  
     sed -i 's|#baseurl=http://mirror.centos.org/altarch/\$releasever/|baseurl=http://vault.centos.org/altarch/7.9.2009/|' /etc/yum.repos.d/CentOS-Base.repo; \\  
   else \\  
     # Default To x64; \\  
     echo "Running on another architecture"; \\  
     sed -i -e 's!#baseurl=http://mirror.centos.org/centos/\$releasever!baseurl=https://vault.centos.org/7.9.2009/!g' /etc/yum.repos.d/CentOS-Base.repo; \\  
   fi
EOF
fi
    cat <<EOF >> $podmanfile
RUN  if dnf install -y sudo ; then echo "dnf did"; elif yum install -y sudo ; then echo "yum did"; else echo "both yum and dnf failed"; fi || true
RUN  if sudo dnf install -y /usr/bin/ps ; then echo "dnf did"; elif sudo yum install -y /usr/bin/ps ; then echo "yum did"; else echo "both yum and dnf failed"; fi  || true
RUN  if sudo dnf install -y $DEPS ; then echo "dnf did"; elif sudo yum install -y $DEPS ; then echo "yum did"; else echo "both yum and dnf failed"; fi
RUN  mkdir /$jlinkimage
COPY $jlinkimage /$jlinkimage/
RUN  ps -A | head -n 10
RUN  sudo cat     /etc/passwd.lock  /etc/shadow.lock /etc/group.lock /etc/gshadow.lock "/etc/passwd.*"  "/etc/shadow.*" "/etc/group.*" "/etc/gshadow.*"|| true
RUN  sudo rm -rvf /etc/passwd.lock  /etc/shadow.lock /etc/group.lock /etc/gshadow.lock "/etc/passwd.*"  "/etc/shadow.*" "/etc/group.*" "/etc/gshadow.*"|| true
RUN  ps -A | head -n 10
RUN  a=0; sudo useradd tester || a=\$? ; if [ \$a -eq 0 ] ; then echo "as tester" && su tester -c "DISPLAY=:0 /$jlinkimage/bin/java -m $module" ; else echo "as \$(whoami)" && bash -c "DISPLAY=:0 /$jlinkimage/bin/java -m $module" ; fi
EOF
    podman build --network host -f $podmanfile
}


#this method is now shared to individual tests
function prepareImages() {
  clean
  compileModules
  runModule helloworld/org.jlink.demo.HelloWorldHidden
  runModule test/org.test.TestApp
  set +e
    runModule  helloworld
    r=$?
  set -e
  test $r -gt 0 #expected failure, pure classes
  createModlueJar helloworld  org.jlink.demo.HelloWorldApp
  createModlueJar test        org.test.TestApp
  runModularJar helloworld/org.jlink.demo.HelloWorldHidden
  runModularJar helloworld
  runModularJar test/org.test.TestApp
  runModularJar test
  createJmod helloworld org.jlink.demo.HelloWorldApp
  createJmod test org.test.TestApp

  # sudo dnf install java-11-openjdk-jmods
  createJlink java.base helloworld $OUTPUT_JLINK
  # we had main class embedded above, but dont ask me how it get here
  runJlinkedImage $OUTPUT_JLINK helloworld
  runJlinkedImage $OUTPUT_JLINK helloworld/org.jlink.demo.HelloWorldHidden
  set +e
    runJlinkedImage $OUTPUT_JLINK test/org.test.TestApp
    r=$?
  set -e
  test $r -gt 0 #expected failure, test not included

  createJlink test java.base helloworld $OUTPUT_JLINKS
  runJlinkedImage $OUTPUT_JLINKS helloworld
  runJlinkedImage $OUTPUT_JLINKS helloworld/org.jlink.demo.HelloWorldHidden
  runJlinkedImage $OUTPUT_JLINKS test/org.test.TestApp
  runJlinkedImage $OUTPUT_JLINKS test

  # check the jlinked image with launcher, moreover for curiosity
  include_launcher="--launcher mystart=helloworld/org.jlink.demo.HelloWorldHidden"
  createJlink  test java.base helloworld $OUTPUT_LAUNCH  
  unset include_launcher
  $OUTPUT_LAUNCH/bin/mystart	

  # we are all good on headless, and even have swing compiled, now run it
  runModule swinghello/org.jlink.swingdemo.SwingHello
  createModlueJar swinghello org.jlink.swingdemo.SwingHello
  runModularJar swinghello
  createJmod swinghello org.jlink.swingdemo.SwingHello
  #note no swing, as we are already requiring that
  createJlink swinghello java.base $OUTPUT_SWINGLINK
  runJlinkedImage $OUTPUT_SWINGLINK swinghello
  # no need to try launcher, it is bash launcher anyway
  # for fun, try to diff the individual jlink images - there really are native awt bits in swing one, and modules files differs a lot
}

## TODO: Remove this
## TODO: This method will be removed with the next maintenance update of this code.
function runLocalTestOfLib() {
  setup
  generate_images=true
  if [ $generate_images = true ] ; then
    prepareImages
  fi
  diffImages  $OUTPUT_JLINK $OUTPUT_SWINGLINK
  # test portability of those images. especially the swing one. containers are fastest
  # podman search centos ;  podman search fedora
  # podman pull --all-tags centos/fedora
  # podman ps -a
  # podman container rm $hashes
  # podman image rm $hashes
  #  rm -rfv ~/.local/share/containers/
  #centos:centos8 centos:centos7 centos:centos6 fedora:29 fedora:30 fedora:31 
  for os in fedora:31 ; do
    for image in $OUTPUT_JLINK ; do
    #for image in $OUTPUT_SWINGLINK ; do
      runImageInPodman $image $os  helloworld
    #  runImageInPodman $image $os  swinghello
    done
  done
}

## TODO: Remove this
# to test this as whole library
#parseArguments "$@"
#processArguments
#runLocalTestOfLib


##########################################################
# support methods to test on proper docker images        #
# idea is:                                               # 
# if isFromRpm, then test it on image of itself, and up  #
#            including fedoras as always newer then rhel #
# if isPortable, then we assume (intel only)             #
#                that we build on rhel6,                 #
#                 thus testing whole scale               #
#         rhel6,7,8 fedora rawhide, latest and latest-1) #
##########################################################
function getOsMajor() {
  cat /etc/redhat-release   | sed "s/\..*//g" | sed "s/[^0-9]\+//g"
}

function getOsMinor() {
  cat /etc/redhat-release   | sed "s/\./06090/g" | sed "s/[^0-9]\+//g" | sed "s/06090/./g"
}

function getOsName() {
  if cat /etc/redhat-release | grep -iq Fedora ; then
    echo "fedora"
  else
    echo "centos"
  fi
}

## TODO: Remove this
function pullAllImagesOf() {
   # centos/fedora
   podman pull --all-tags $1
}

function pullSelectedImage() {
   # centos/fedora:version
   podman pull $1:$2
}

function listFedoras() {
 # After checking with Fedora leads on Slack, moving to this new source of truth for the latest release version.
 curl -s -L https://fedorapeople.org/groups/qa/metadata/release.json | jq '.fedora.stable[]'
}

## Define the FDN for the container images to be used.
export CENTOS_IMAGE_FQN="quay.io/centos/centos"
export FEDORA_IMAGE_FQN="quay.io/fedora/fedora"

function pullAllImages() {
  for x in 7 8 ; do 
    pullSelectedImage "$CENTOS_IMAGE_FQN" $x
  done
 for x in  `listFedoras` ; do 
    pullSelectedImage "$FEDORA_IMAGE_FQN" $x
  done
}

function isFromRpm() {
  local java=`readlink -f $JAVA_DIR/bin/java`
  if rpm -qf $java > /dev/null ; then
    echo yes
  else
    echo no
  fi
}

function runOnRhelLimited() {
  if [ `isFromRpm` == "yes" -a `getOsName` == "centos" -a `getOsMajor` -le "$2"  ] ; then
    runImageInPodman $1 "$CENTOS_IMAGE_FQN":"$2"  "$3"
  elif [ `isFromRpm` == "no" ] ; then
    runImageInPodman $1 "$CENTOS_IMAGE_FQN":"$2"  "$3"
  else
    echo "$SKIPPED"
  fi
}

##TODO: To be remove in the next maintenance update.
function runOnRhel6() {
  runOnRhelLimited $1 6 $2
}
function runOnRhel7() {
  runOnRhelLimited $1 7 $2
}
function runOnRhel8() {
  runOnRhelLimited $1 8 $2
}


function runOnFedora() {
  if [ `isFromRpm` == "yes" -a `getOsName` == "centos"  ] ; then
    runImageInPodman $1 "$FEDORA_IMAGE_FQN":"$2"  "$3"
  elif [ `isFromRpm` == "yes" -a `getOsName` == "fedora" -a `getOsMajor` -le $2 ] ; then
    runImageInPodman $1 "$FEDORA_IMAGE_FQN":"$2"  "$3"
  elif [ `isFromRpm` == "no" ] ; then
    runImageInPodman $1 "$FEDORA_IMAGE_FQN":"$2"  "$3"
  else
    echo "$SKIPPED"
  fi
}

function runOnFedoraRawhide() {
  if [ `isFromRpm` == "yes" -a `getOsName` == "centos"  ] ; then
    runImageInPodman $1 fedora:rawhide  "$2"
  elif [ `isFromRpm` == "yes" -a `getOsName` == "fedora" ] ; then
    runImageInPodman $1 fedora:rawhide  "$2"
  elif [ `isFromRpm` == "no" ] ; then
    runImageInPodman $1 fedora:rawhide  "$2"
  else
    echo "$SKIPPED"
  fi
}

function getFedoras() {
  podman images --format "table  {{.Repository}} {{.Tag}}" | grep fedora | sed "s/.* //g" | grep "^[0-9]\+$" | sort
}

function getFedoraIdN() {
  getFedoras | tail -n $1 | head -n 1
}

function runOnFedoraN() {
  runOnFedora $1 `getFedoraIdN 1` $2
}

function runOnFedoraN1() {
  runOnFedora $1 `getFedoraIdN 2` $2
}

function runOnFedoraN2() {
  runOnFedora $1 `getFedoraIdN 3` $2
}

function runOnFedoraN3() {
  runOnFedora $1 `getFedoraIdN 4` $2
}


function assertsInReportFile() {
  #custom condition or skipped marker
  assertsWithoutIgnoreInReportFile "$@" -e "$SKIPPED"
}

function assertsWithoutIgnoreInReportFile() {
  #custom condition or skipped marker
  cat $REPORT_FILE | grep "$@"
}

function assertNoExceptionInReportFile() {
  set +e
    assertsWithoutIgnoreInReportFile -e Exception
    local r=$?
  set -e
  test $r -gt 0 #we do n to wont to found them
}

function assertSwingHello() {
  assertsInReportFile -e "X98 set visible "
  assertsInReportFile -e "X98 disposed"
}

function assertHelloWorld() {
  assertsInReportFile -e "X90 Hello World"
}
function assertHelloWorldHidden() {
  assertsInReportFile -e "X95 Hidden Hell War"
}

function assertTestDepndence() {
  assertsInReportFile -e "X94 From depndence: "
  assertHelloWorld
}

function exitOnWindows() {
  if [[ `uname -s` == *NT* ]]; then
      echo "$SKIPPED_ON_WIN"
    exit 0
  fi
}

function exitOnAarch64() {
  if [[ `uname -m` == aarch64 ]]; then
      echo "$SKIPPED_ON_AARCH64"
    exit 0
  fi
}

function exitSwingAppOnHeadleassContainer() {
	  echo "$SKIPPED_ON_HEADLESS_CONTAINER"
	  exit 0
}

function skipOnHeadless() {
  if [[ ! `uname -s` == *NT* ]]; then
    if [ "x$DISPLAY" == "x" ]; then
	  echo "$SKIPPED_ON_HEADLESS"
	  exit 0
    fi
  fi
}

function skipNoRpmInstall() {
    if [ "x${JLINK_RPM_INSTALL_RUNNER_LOCATION}" == x  ] ; then
        echo "$SKIPPED_NO_RPM_INSTALL"
        exit 0
    fi
}

function removeJVM() {
    skipNoRpmInstall
    sudo bash $JLINK_RPM_INSTALL_RUNNER_LOCATION/uninstallRpms.sh
}

function installJVMSilently() {
    skipNoRpmInstall
    sudo bash $JLINK_RPM_INSTALL_RUNNER_LOCATION/cleanAndInstallRpms.sh 1>/dev/null 2>&1 || echo "installJVMSilently failed"
}
