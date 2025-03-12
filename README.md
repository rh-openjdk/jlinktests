# jlinkTests

This repository holds the testcode for testing the OpenJDK `jlink` 
functionality against various builds of OpenJDK. 

Current supported platforms for execution.

| Platform | Operating System            | 
|----------|-----------------------------|
| Linux | Rhel 7                      |
| Linux | Rhel 8                     |
| Linux | Rhel 9                      |
| Linux | Rhel 10                     |
|Linux | Fedora (current, current-1) |
| Windows | Windows 2022 |

Setting up the environment for execution:


`JLINK_RPM_INSTALL_RUNNER_LOCATION` This envionment variable needs to be
defined to run tests 301, 302, 303 or 304. This should point to a 
folder that will support uninstall and install OpenJDK off the 
host-under-test.

To pull down the whole codebase including the submodule 
test runner issue the following command.

`git clone --recurse-submodules https://github.com/rh-openjdk/jlinktests.git`

To run the testsuite, use the runner in the runner folder.
`bash runner/run_jlink_tests.sh`

### WARNING from run-folder-as-tests
#### PREP_SCRIPT
By default, the scripting is trying to execute `PREP_SCRIPT`, to allow you custom preparation of system/jdk before testsuite is run.
For legacy reasons, this defaults to `/mnt/shared/TckScripts/jenkins/benchmarks/cleanAndInstallRpms.sh`, which you most likely do not have.
If you have it, and want to use it, it will remove all you java rpms and /usr/lib/jvm, and install/unpack JDKs in `/mnt/workspace/rpms`
If you do not have it, or point `PREP_SCRIPT` to some script of yours, you should  be safe.

#### Custom JDK
The correct way how to use any installed java, is **optional parameter**, which should point to any `JAVA_HOME`. If used, then `PREP_SCRIPT` is not even called
```
bash runner/run_jlink_tests.sh /usr/lib/jvm/java-xyz-openjdk
```
Should then do the job.
