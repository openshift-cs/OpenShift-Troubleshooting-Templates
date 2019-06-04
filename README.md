# OpenShift Troubleshooting Templates

A collection of various templates that can be used for troubleshooting different issues for OpenShift clusters


## Network Troubleshooting with netcat

If you need to test network connectivity to an endpoint device, `nc` (or netcat) is a handy
troubleshooting tool. It's included in the default `busybox` image, and provides quick and clear
output if a connection can be made

```bash
# Create a throw-away pod with busybox; cleans up after itself
$ oc run netcat-test --image=busybox -i -t --restart=Never --rm -- /bin/sh

# Successful connection
/ nc -zvv 192.168.1.1 8080
10.181.3.180 (10.181.3.180:8080) open
sent 0, rcvd 0

# Failed connection
/ nc -zvv 192.168.1.2 8080
nc: 10.181.3.180 (10.181.3.180:8081): Connection refused
sent 0, rcvd 0

# Exit the container, which will automatically delete the pod
/ exit
```

## Gather unique Google OAuth IDs

Access directly at https://google-oauth-userid-lookup.6923.rh-us-east-1.openshiftapps.com/

[More details](google-oauth-userid/README.md).
