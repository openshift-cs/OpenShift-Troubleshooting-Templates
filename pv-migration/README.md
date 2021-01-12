# PV Migration

Persistent Volume (PV) data can be easily migrated via the `oc rsync` utility command.
This script attempts to provide a generic method of migrating PV data between two
different OpenShift clusters. There is nothing technical that would prevent this
script from migrating PV data between two namespaces within the same cluster.

## Usage

```
$ ./migrate_volume.sh

    This script is used for migrating persistent volume data from one OpenShift cluster to another.

    Usage: ./migrate_volume.sh [options]

      -h | --help           Print this help message
      --from                The API URL for the cluster to copy from
      --to                  The API URL for the cluster to copy to
      --namespace           The namespace to use when looking for the
                              persistentVolumeClaim on the 'from' cluster
      --pvc                 The persistentVolumeClaim object name to copy
                              data from on the 'from' cluster
      --namespaceoverride   (Optional) Specify a different namespace to use
                              on the 'to' cluster; Defaults to value of --namespace
      --pvcoverride        (Optional) Specify a different persistentVolumeClaim
                              object name to use on the 'to' cluster; Defaults to value of --pvc

    Example usage:
      ./migrate_volume.sh --from=api.cluster-1-id.openshift.com \
          --to=api.cluster-2-id.a0b1.p1.openshiftapps.com:6443 \
          --namespace=my-project \
          --pvc=my-pvc \
          --namespaceoverride=new-project \
          --pvcoverride=new-pvc
```
