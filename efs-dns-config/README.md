# Consume AWS EFS across VPC Peering connections

In order to consume AWS EFS across VPC Peering connections, it's necessary
to perform some DNS work since AWS will _not_ propagate the EFS DNS records
across the VPC Peering connection.

We can do this by using a combination of deploying a custom DNS server,
and then configuring OpenShift's DNS operator to forward requests to the
custom server.

Credit: The majority of this is due to the wonderful work done by
@briantward in his blog post, https://briantward.github.io/coredns-nonprivileged/

## Deploy and Configure the DNS server

The necessary configuration and manifests have been packaged up into an OpenShift
template.

### Template Variables

**NAME** _(Default: `coredns`)_: The name assigned to all of the application components defined in this template.
**DOMAIN**: The domain of the static resource, e.g., "sub.example.com" for a link.sub.example.com resource.
**RESOURCE**: The actual resource value, e.g., "link" for a link.sub.example.com resource.
**IP_ADDRESS**: The static IP address that the resource should resolve to.

### Deployment Command

This deployment is intended to deploy a single resource lookup. After deployed, you can
edit the ConfigMap by hand to add additional resource lookups as needed. Be sure
to run `oc rollout restart dc/coredns` to pull in any changes.

```bash
$ oc new-app https://raw.githubusercontent.com/openshift-cs/OpenShift-Troubleshooting-Templates/master/efs-dns-config/coredns-template.yaml \
    -p DOMAIN=sub.example.com \
    -p RESOURCE=link \
    -p IP_ADDRESS=127.0.0.1
```

## Configure OpenShift DNS Forwarding

The source of this information comes from the OpenShift documentation: https://docs.openshift.com/container-platform/latest/networking/dns-operator.html#nw-dns-forward_dns-operator

1. Get the `ClusterIP` of your new service

        $ export SERVICE_IP=$(oc get service coredns -o custom-columns=CLUSTER-IP:.spec.clusterIP --no-headers)
        $ export FORWARD_DOMAIN=sub.example.com

2. Configure the DNS operator

        $ oc patch dns.operator default --type=json --patch="[{\"op\": \"add\", \"path\": \"/spec/servers/-1\", \"value\": {\"name\": \"upstream-dns\", \"zones\": [\"$FORWARD_DOMAIN\"], \"forwardPlugin\": {\"upstreams\": [\"$SERVICE_IP\"]}}}]"
