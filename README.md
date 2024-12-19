# jlinkTests

This repository holds the testcode for testing the OpenJDK `jlink` 
functionality against various builds of OpenJDK. 

Current supported platforms for execution.

| Platform | Operating System            | 
|----------|-----------------------------|
| Linux | Rhel 8                      |
| Linux | Rhel 9                      |
|Linux | Fedora (current, current-1) |
| Windows | Windows 2022 |

Setting up the environment for execution:


`JLINK_RPM_INSTALL_RUNNER_LOCATION` This envionment variable needs to be
defined to run tests 301, 302, 303 or 304. This should point to a 
folder that will support uninstall and install OpenJDK off the 
host-under-test.