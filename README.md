# OpenShift Troubleshooting Templates

A collection of various templates that can be used for troubleshooting different issues for OpenShift clusters


## Network Troubleshooting with Telnet

+ `oc new-project telnet-troubleshooting-openshift`
+ `oc create -f https://raw.githubusercontent.com/openshift-cs/OpenShift-Troubleshooting-Templates/master/busybox-telnet.yaml`
+ `oc rsh busybox-telnet`
    > / $ telnet \<HOST\> \<PORT\>
+ `oc delete project telnet-troubleshooting-openshift`
