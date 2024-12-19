#!/bin/bash
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

source "$SCRIPT_DIR/testlib.bash"

function getLibName() {
  if isWindows; then
    echo "$1.dll"
  else
    echo "lib$1.so"
  fi
}

function getLibAwtFilename() {
  echo $(getLibName awt)
}

parseArguments "$@"
processArguments
setup

  # for fun, try to diff the individual jlink images - there really are native awt bits in swing one, and modules files differs a lot 
  diffImages  "$OUTPUT_JLINK" "$OUTPUT_SWINGLINK" 2>&1| tee "$REPORT_FILE"
  cat  "$REPORT_FILE" | grep Only | grep "$OUTPUT_SWINGLINK" | grep jawt.h
  cat  "$REPORT_FILE" | grep Only | grep "$OUTPUT_SWINGLINK" | grep `getLibAwtFilename`
  #                                                                   tab!!
  sHello=`cat  $REPORT_FILE | grep -v -e "Binary" | grep -v  -e "+"  |  grep $OUTPUT_JLINK/lib/modules      | sed "s/\t.*//" `
  sSwing=`cat  $REPORT_FILE | grep -v -e "Binary" | grep -v  -e "+"  |  grep $OUTPUT_SWINGLINK/lib/modules  | sed "s/\t.*//" `
  test $sHello -lt $sSwing

