#!/usr/bin/env bash

# usage: migrate_volume.sh <from-cluster-api-url> <to-cluster-api-url> <namespace> <pvc-name> <namespace-override> <pvc-name-override>
# Both *-override variables are optional, and if not provided, the script will reuse the provided information
# example: ./migrate_volume.sh api.cluster-1-id.openshift.com api.cluster-2-id.a0b1.p1.openshiftapps.com:6443 my-project my-pvc
# example: ./migrate_volume.sh api.cluster-1-id.openshift.com api.cluster-2-id.a0b1.p1.openshiftapps.com:6443 my-project my-pvc new-project new-pvc

function usage {
    echo "This script is used for migrating persistent volume data from one OpenShift cluster to another."
    echo
    echo "Usage: $0 [options]"
    echo
    echo "  -h | --help           Print this help message"
    echo "  --from                The API URL for the cluster to copy from"
    echo "  --to                  The API URL for the cluster to copy to"
    echo "  --namespace           The namespace to use when looking for the"
    echo "                          persistentVolumeClaim on the 'from' cluster"
    echo "  --pvc                 The persistentVolumeClaim object name to copy"
    echo "                          data from on the 'from' cluster"
    echo "  --namespaceoverride   (Optional) Specify a different namespace to use"
    echo "                          on the 'to' cluster; Defaults to value of --namespace"
    echo "  --pvcoverride        (Optional) Specify a different persistentVolumeClaim"
    echo "                          object name to use on the 'to' cluster; Defaults to value of --pvc"
    echo
    echo "Example usage:"
    echo "  $0 --from=api.cluster-1-id.openshift.com \\"
    echo "      --to=api.cluster-2-id.a0b1.p1.openshiftapps.com:6443 \\"
    echo "      --namespace=my-project \\"
    echo "      --pvc=my-pvc \\"
    echo "      --namespaceoverride=new-project \\"
    echo "      --pvcoverride=new-pvc"
}

function die {
    echo "$*" >&2
    exit 2
}

function needs_arg {
    if [ -z "$OPTARG" ]; then
        die "Argument required for '--${OPT}' option; --${OPT}=<argument>"
    fi
}

function parse_options {
    # Option parsing; adapted from https://stackoverflow.com/a/28466267/6758654
    while getopts ":h-:" OPT; do
        if [ "${OPT}" = "-" ]; then   # long option: reformulate OPT and OPTARG
            OPT="${OPTARG%%=*}"       # extract long option name
            OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
            OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
        fi
        case "${OPT}" in
            h | help )              usage; exit 0 ;;
            from )                  needs_arg; FROMCLUSTER="${OPTARG}" ;;
            to )                    needs_arg; TOCLUSTER="${OPTARG}" ;;
            namespace )             needs_arg; NAMESPACE="${OPTARG}" ;;
            pvc )                   needs_arg; PVC="${OPTARG}" ;;
            namespaceoverride )     needs_arg; NAMESPACEOVERRIDE="${OPTARG}" ;;
            pvcoverride )          needs_arg; PVCOVERRIDE="${OPTARG}" ;;
            ??*)                    die "Invalid option '--${OPT}'. Use --help for a help menu." ;;
            ? )                     die "Invalid option. Use --help for a help menu." ;;
        esac
    done
    shift $((OPTIND-1)) # remove parsed options and args from $@ list

    if [ -z "$NAMESPACEOVERRIDE" ] ; then
        NAMESPACEOVERRIDE=$NAMESPACE
    fi

    if [ -z "$PVCOVERRIDE" ] ; then
        PVCOVERRIDE=$PVC
    fi

    if [ -z "$FROMCLUSTER" ]; then die "Missing required option: --from"; fi
    if [ -z "$TOCLUSTER" ]; then die "Missing required option: --to"; fi
    if [ -z "$NAMESPACE" ]; then die "Missing required option: --namespace"; fi
    if [ -z "$PVC" ]; then die "Missing required option: --pvc"; fi

}

# Function definitions
function login_cluster {
    # Login to the cluster, attempting to reuse previous context to prevent multiple prompts
    STOREDCONFIG=$(cat ${HOME}/.kube/$1 2> /dev/null)
    if [ -z "$STOREDCONFIG" ] ; then
        # Get Token URL endpoint
        # Use fake username/password to force a token URL
        TOKENURL=$(oc login $1 -u 'none' -p 'none' 2>&1)

        # Failure typically occurs if API URL is incorrect
        if $(printf "$TOKENURL" | grep "error") ; then
            echo "Unable to find to cluster '$1'"
            exit
        fi

        TOKENURL=$(printf "$TOKENURL" | grep -o "https://.*")

        # If the token URL doesn't exist in the output, then attempt to construct it
        if [ -z "$TOKENURL" ] ; then
            if $(printf "$1" | grep -E "https?://") ; then
                BASEURL=$(printf "$1" | cut -d: -f2 | cut -d. -f2-)
            else
                BASEURL=$(printf "$1" | cut -d: -f1 | cut -d. -f2-)
            fi
            TOKENURL="https://oauth-openshift.apps.$BASEURL/oauth/token/request"
        fi

        # Securely prompt for Login Token
        stty -echo
        echo "Please visit $TOKENURL to retrieve your login token"
        printf "Token: "
        read LOGINTOKEN
        stty echo
        echo

        # Attempt to login with Token
        oc login $1 --token=$LOGINTOKEN > /dev/null 2>&1

        # Failure may occur if token is copied incorrectly
        if [ "$?" -ne 0 ] ; then
            echo "Unauthorized token used to access cluster '$1'. Try again"
            exit
        fi

        unset LOGINTOKEN
        CONTEXT_EXISTS=0
    else
        # Switch to previously configured context
        oc adm config use-context $STOREDCONFIG > /dev/null 2>&1
        CONTEXT_EXISTS=$?
    fi

    # Validate that login is successful
    oc whoami > /dev/null 2>&1
    LOGGED_IN_SUCCESSFULLY=$?
    if [ "$CONTEXT_EXISTS" -ne 0 ] || [ "$LOGGED_IN_SUCCESSFULLY" -ne 0 ] ; then
        # If login or context failed, reattempt login flow
        # Failure may occur if the context has been deleted, renamed, or if the user
        # has explicitly ran `oc logout`
        rm ${HOME}/.kube/$1
        login_cluster $1
    fi

    # Specifically save context to enable authentication reuse
    oc adm config current-context > ${HOME}/.kube/$1
}

function wait_for_deployment {
    # Get the latest deployment version
    LATEST_DEPLOYMENT=$(oc get deploymentconfig $1 -o jsonpath='{.status.latestVersion}')

    echo "Checking if helper deployment is ready..."

    # Wait for latest pod to be ready
    DEPLOYMENT_POD=$(oc get pods -l deployment=$1-$LATEST_DEPLOYMENT -o go-template='{{range .items}}{{$metadata := .metadata}}{{range .status.conditions}}{{if and (eq .type "Ready") (eq .status "True")}}{{$metadata.name}}{{end}}{{end}}{{end}}')
    while [ -z "$DEPLOYMENT_POD" ] ; do
        echo "...Not ready yet"
        sleep 10
        DEPLOYMENT_POD=$(oc get pods -l deployment=$1-$LATEST_DEPLOYMENT -o go-template='{{range .items}}{{$metadata := .metadata}}{{range .status.conditions}}{{if and (eq .type "Ready") (eq .status "True")}}{{$metadata.name}}{{end}}{{end}}{{end}}')
    done

    echo "...Ready"
}

function wait_for_pvc_attachment {
    POD=$(oc describe pvc $1 | grep -E "(Mounted|Used) By" | grep -v '<none>$')

    echo "Waiting for PVC to attach..."

    while [ -z "$POD" ] ; do
        echo "...Not attached yet"
        sleep 3
        POD=$(oc describe pvc $1 | grep -E "(Mounted|Used) By" | grep -v '<none>$')
    done

    echo "...Attached"
}

function wait_for_ready_pod {
    READYPOD=$(oc describe pod $1 | grep -E 'Ready:?\s*True' | wc -l)

    echo "Waiting for pod '$POD' to become 'Ready'..."

    # The "special number" 3 represents the three places that a pod displays its readiness
    # - Pod Ready
    # - All Containers Ready
    # - Each individual pod (1 or more)
    while [ "$READYPOD" -lt 3 ] ; do
        echo "...Not ready yet"
        sleep 5
        READYPOD=$(oc describe pod $1 | grep -E 'Ready:?\s*True' | wc -l)
    done

    echo "...Ready"
}

function set_project {
    echo "Switching to project '$1'..."
    oc project $1 > /dev/null 2>&1
    if [ "$?" -ne 0 ] ; then
        echo "Namespace '$1' does not exist"
        exit
    fi
}

function  find_pod_with_pvc {
    echo "Finding pod with PVC '$1' attached..."

    # Find pod with PVC attached
    POD=$(oc describe pvc $1 2> /dev/null | grep -E "(Mounted|Used) By" | grep -v '<none>$')
}

function set_pod_params {
    # Trim pod name
    POD=$(printf "$POD" | cut -d: -f2 | tr -d '[:space:]')

    echo "PVC found attached to pod '$POD'..."

    # Get name of volume in pod
    VOLUME=$(oc get pod $POD -o jsonpath="{.spec.volumes[?(.persistentVolumeClaim.claimName==\"$1\")].name}")

    # Get mountPath and container for volume
    VOLUMEINFO=$(oc get pod $POD -o jsonpath="{range .spec.containers[*]}{.volumeMounts[?(.name==\"$VOLUME\")].mountPath}{':'}{.name}{'@'}{end}" | cut -d@ -f1)

    # Get PVC storage size
    PVCSTORAGE=$(oc get pvc $1 -o jsonpath='{.spec.resources.requests.storage}')

    # Standardize the path without a trailing slash
    MOUNTPATH=$(printf "$VOLUMEINFO" | cut -d: -f1 | sed 's|/$||')
    CONTAINER=$(printf "$VOLUMEINFO" | cut -d: -f2)
}

function create_helper_for_existing_pvc {
    # Spin up a helper deployment if PVC isn't currently in use
    echo "...PVC is not attached, creating migration helper deployment..."
    DEPLOYMENT="pvc-migration-helper-$(uuidgen | tr '[:upper:]' '[:lower:]')"
    oc create deploymentconfig $DEPLOYMENT --image=registry.redhat.io/rhel7/rhel-tools -- /bin/sh -c "while true; do sleep 10; done"

    wait_for_deployment $DEPLOYMENT

    # Once deployment is ready, attach the desired PVC and wait for new deployment to be ready
    oc set volume dc/$DEPLOYMENT --add -m /migration-data --claim-name=$1 --read-only=true

    # Wait for PVC to attach to new pod
    wait_for_pvc_attachment $1
}

function create_helper_for_new_pvc {
    # Spin up a helper deployment and new PVC if PVC doesn't exist
    oc get pvc $1 > /dev/null 2>&1
    if [ "$?" -ne 0 ] ; then
        echo "...PVC does not exist, creating migration helper deployment and PVC..."
        DEPLOYMENT="pvc-migration-helper-$(uuidgen | tr '[:upper:]' '[:lower:]')"
        oc create deploymentconfig $DEPLOYMENT --image=registry.redhat.io/rhel7/rhel-tools -- /bin/sh -c "while true; do sleep 10; done"

        wait_for_deployment $DEPLOYMENT

        # Once deployment is ready, attach the desired PVC and wait for new deployment to be ready
        oc set volume dc/$DEPLOYMENT --add -m /migration-data --claim-name=$1 --read-only=false --claim-size="$PVCSTORAGE"

        # Wait for PVC to attach to new pod
        wait_for_pvc_attachment $1
    fi
}

function set_rsync_args {
    # Validate that the targeted container has rsync
    oc exec $POD -c $CONTAINER -- rsync --help > /dev/null 2>&1
    if [ "$?" -eq 0 ] ; then
        ARGS="--no-perms --progress --compress --strategy=rsync-daemon"
    else
        ARGS="--strategy=tar"
    fi
}

function download_pvc_data {
    # Switch to the specified namespace, fail and exit if not found
    set_project $1

    # Ensure that PVC actually exists
    oc get pvc $2 > /dev/null 2>&1
    if [ "$?" -ne 0 ] ; then
        echo "PVC '$2' does not exist"
        exit
    fi

    find_pod_with_pvc $2

    if [ -z "$POD" ] ; then
        create_helper_for_existing_pvc $2
    fi

    set_pod_params $2

    wait_for_ready_pod $POD

    set_rsync_args

    echo "Performing backup of $MOUNTPATH in '$CONTAINER' container to temporary directory $MIGRATION_DIR..."

    # Download PVC contents into temporary migration directory
    oc rsync $POD:"$MOUNTPATH/" "$MIGRATION_DIR" -c "$CONTAINER" $ARGS

    if [ "$?" -ne 0 ] ; then
        echo "Backup failed! Unable to proceed..."
        echo "This typically happens if the 'rsync' or 'tar' binaries are not available in the pod."
        echo "Scaling down the pod with the PVC attached will allow this script to access it better."

        # Clean up helper deployment if used
        if [ ! -z $DEPLOYMENT ] ; then
            echo "Deleting migration helper deployment..."
            oc delete dc/$DEPLOYMENT --force --grace-period=0 > /dev/null 2>&1
        fi

        exit
    fi

    # Clean up helper deployment if used
    if [ ! -z "$DEPLOYMENT" ] ; then
        echo "Deleting migration helper deployment..."
        oc delete dc/$DEPLOYMENT --force --grace-period=0 2>/dev/null
    fi
}

function upload_pvc_data {
    # Clean up shared variables
    unset POD MOUNTPATH CONTAINER ARGS DEPLOYMENT

    # Switch to the specified namespace, fail and exit if not found
    set_project $1

    find_pod_with_pvc $2

    if [ -z "$POD" ] ; then
        create_helper_for_new_pvc $2
    fi

    set_pod_params $2

    wait_for_ready_pod $POD

    set_rsync_args

    echo "Performing restore to $MOUNTPATH in '$CONTAINER' container from temporary directory $MIGRATION_DIR..."

    # Download PVC contents into temporary migration directory
    oc rsync "$MIGRATION_DIR/" $POD:"$MOUNTPATH/" -c "$CONTAINER" $ARGS

    if [ "$?" -ne 0 ] ; then
        echo "Restore failed!"
        echo "This typically happens if the 'rsync' or 'tar' binaries are not available in the pod."
        echo "Scaling down the pod with the PVC attached will allow this script to access it better."

        # Clean up helper deployment if used
        if [ ! -z $DEPLOYMENT ] ; then
            echo "Deleting migration helper deployment..."
            oc delete dc/$DEPLOYMENT --force --grace-period=0 > /dev/null 2>&1
        fi

        exit
    fi

    # Clean up helper deployment if used
    if [ ! -z "$DEPLOYMENT" ] ; then
        echo "Deleting migration helper deployment..."
        oc delete dc/$DEPLOYMENT --force --grace-period=0 2>/dev/null
    fi
}

parse_options "$@"

echo "===>  Starting backup process  <==="

# Create temporary directory for storing migration data
MIGRATION_DIR=$(mktemp -d)

login_cluster $FROMCLUSTER

download_pvc_data $NAMESPACE $PVC

echo "===>  Starting migration process  <==="

login_cluster $TOCLUSTER

upload_pvc_data $NAMESPACEOVERRIDE $PVCOVERRIDE

echo "===>  Cleaning up local migration data  <==="

rm -r "$MIGRATION_DIR/"

echo "...DONE..."

exit 0
