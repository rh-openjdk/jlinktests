#!/bin/bash

###############################################################################
##  run_jlink_tests.sh
##  An entry point for running the JLINK test suite against a build of OpenJDK.
##
##
###############################################################################

## For the first version of this script it will be assumed this is either running on
## RHEL or Fedora Linux. While the testcode supports execution on Windows 2022, this
## does not yet.


set -ex
set -o pipefail
## resolve folder of this script, following all symlinks,
## http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" && pwd )"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
readonly SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" && pwd )"

echo "Ensure Podman is installed."
if ! podman --version ;  then
  if dnf --version ; then
    cmd=dnf
  elif yum --version ; then
    cmd=yum
  else
    echo "Sorry, I can install podman only on dnf and yum"
    exit 1
  fi
  if [ `whoami`  ==  "root" ] ; then
    $cmd install podman -y;
  else
   sudo $cmd install podman -y;
  fi
fi
echo "Define the testsuite location."
JLINK_TEST_CODE_LOCATION=`dirname $SCRIPT_DIR`

bash ${JLINK_TEST_CODE_LOCATION}/run-folder-as-tests/run-folder-as-tests.sh $JLINK_TEST_CODE_LOCATION
