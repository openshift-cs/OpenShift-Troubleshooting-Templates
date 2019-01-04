# OpenShift Dedicated PV migration/resize

This will describe how to migrate persistent data from one OpenShift PV to another. This may commonly
be necessary for performing PV backups or in order to resize a PV.

**IMPORTANT: As PVs cannot be mounted to multiple pods, this process does cause minimal downtime.**

## Gathering Facts

There are primarily four data points that will be referenced throughout this description:

- `$DEPLOYMENT`: This is the name of the deploymentconfig that contains your PV
- `$PVCCLAIMNAME`: The name of the PVC that references your desired PV (ignore the starting `pvc/`)
- `$DEPLOYMENTVOLUMENAME`: The name of the volume as defined in your $DEPLOYMENT
- `$PVCSIZE`: The desired size of the new PVC (append with `Gi` for gigabytes or `Mi` for megabytes)

## The Process

- First capture the $PVCCLAIMNAME and $DEPLOYMENTVOLUMENAME from your current deployment.

      oc set volume deploymentconfig $DEPLOYMENT

   Output example:

   ```sh
   deploymentconfigs/mysql
     pvc/ mysql <-- $PVCCLAIMNAME (allocated 1GiB) as mysql-data <-- $DEPLOYMENTVOLUMENAME
       mounted at /var/lib/mysql/data
   ```

- Shutdown your current deployment to prevent data corruption during migration

      oc scale deploymentconfig $DEPLOYMENT --replicas=0

- Create an intermediary deployment that will perform the migration

      oc run pv-migration --image=registry.redhat.io/rhel7/rhel-tools --replicas=0 -- tail -f /dev/null

- Mount the original PVC to the migration deployment

      oc set volume deploymentconfig pv-migration --add -t pvc --name=old-pv --claim-name=$PVCCLAIMNAME --mount-path=/old-pv-path

- Create and mount the new PVC

      oc set volume deploymentconfig pv-migration --add -t pvc --name=new-pv --claim-name=${PVCCLAIMNAME}2 --mount-path=/new-pv-path --claim-mode=ReadWriteOnce --claim-size=$PVCSIZE

- **Create and wait for `pv-migration` pod to be ready**

      oc scale deploymentconfig pv-migration --replicas=1

- Migrate data to the new PV

      oc exec $(oc get pods -l deploymentconfig=pv-migration -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | cut -d " " -f 1) -- rsync -avxHAX --no-t --progress /old-pv-path/ /new-pv-path/

- Remove the intermediary deployment

      oc delete deploymentconfig pv-migration --grace-period=0 --force

- Update the original deployment to use the new PV (optional; used for PV resize)

      oc set volume deploymentconfig $DEPLOYMENT --add --name=$DEPLOYMENTVOLUMENAME --claim-name=${PVCCLAIMNAME}2 --overwrite

- Scale your deployment back up

      oc scale deploymentconfig $DEPLOYMENT --replicas=1

- You can now delete the original PVC (**THIS IS IRREVERSIBLE**)

      oc delete pvc $PVCCLAIMNAME

## Script

The below is a condensed version of the above instructions to make this easily scriptable and reduce the amount of downtime required. Depending on the amount of data being migrated, this typically results in only about 1 minute of downtime

```bash
#!/usr/bin/env bash

# usage: script.sh <deploymentconfig-name> <pvc-claim-name> <volume-name-on-deployment> <desired-pvc-size>
# example: script.sh postgresql postgresql postgresql-data 5Gi

set -e

DEPLOYMENT="$1"
PVCCLAIMNAME="$2"
DEPLOYMENTVOLUMENAME="$3"
PVCSIZE="$4"

RANDOM_ID=$(uuidgen | awk -F- '{ print tolower($2) }')

oc run pv-migration --image=registry.redhat.io/rhel7/rhel-tools --replicas=0 -- tail -f /dev/null
oc set volume deploymentconfig pv-migration --add -t pvc --name=old-pv --claim-name=$PVCCLAIMNAME --mount-path=/old-pv-path
oc set volume deploymentconfig pv-migration --add -t pvc --name=new-pv --claim-name=${PVCCLAIMNAME}${RANDOM_ID} --mount-path=/new-pv-path --claim-mode=ReadWriteOnce --claim-size=$PVCSIZE
oc scale deploymentconfig $DEPLOYMENT --replicas=0
oc scale deploymentconfig pv-migration --replicas=1

# Wait for pod
while [[ -z $(oc get pods -l deploymentconfig=pv-migration -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | cut -d " " -f 1) ]]
do
    echo Waiting for "pv-migration" pod
    sleep 1
done

oc exec $(oc get pods -l deploymentconfig=pv-migration -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | cut -d " " -f 1) -- rsync -avxHAX --no-t --progress /old-pv-path/ /new-pv-path/
oc delete deploymentconfig pv-migration --grace-period=0 --force
oc set volume deploymentconfig $DEPLOYMENT --add --name=$DEPLOYMENTVOLUMENAME --claim-name=${PVCCLAIMNAME}${RANDOM_ID} --overwrite
oc scale deploymentconfig $DEPLOYMENT --replicas=1

echo Done
```
