# Determine your Google OAuth ID

## Creating a Google OAuth Client

https://developers.google.com/identity/protocols/OAuth2WebServer#creatingcred

## Using a hosted solution

This project has already been deployed to https://google-oauth-userid-lookup.6923.rh-us-east-1.openshiftapps.com/
for your convenience. This application does not store any data or information.

## Deploying this project to OpenShift

### Deploying from a local git repo

    oc new-app . --image-stream=python:latest --name=google-oauth-userid
    oc env dc/google-oauth-userid GOOGLE_CLIENT_ID=<google_client_id>
    oc env dc/google-oauth-userid GOOGLE_CLIENT_SECRET=<google_client_secret>
    oc start-build google-oauth-userid --from-repo=.
    oc create route edge --service=google-oauth-userid --insecure-policy=Redirect

### Deploy from an existing git repo

    oc new-app https://github.com/openshift-cs/OpenShift-Troubleshooting-Templates --image-stream=python:latest --context-dir=google-oauth-userid --name=google-oauth-userid
    oc env dc/google-oauth-userid GOOGLE_CLIENT_ID=<google_client_id>
    oc env dc/google-oauth-userid GOOGLE_CLIENT_SECRET=<google_client_secret>
    oc start-build google-oauth-userid
    oc create route edge --service=google-oauth-userid --insecure-policy=Redirect

### Next steps

You will need to update your Credentials with the proper **authorized redirect URI**.
You can determine the **redirect URI** by running

    oc get route google-oauth-userid --template='{{ .spec.host }}'

Take the input from above as <openshift_route> and your **redirect URI** will be

    https://<openshift_route>/login/google/authorized

Now, visiting https://<openshift_route> will ask you to login to your Google Account,
and output your Google OAuth ID.
