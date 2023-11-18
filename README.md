# Kubernetes Native Authentication & Authorization Test

Using the native authentication method of K8s through TLS certificates, I have implemented the shell script `create_user_certs.sh`. This script allows you to create a user and associate the desired groups within the certificate itself. Subsequently, the `bind_roles.sh` script executes permission associations on both groups and individual users, leveraging the `CN` and `O` fields of the previously created certificates for various users.

Specifically, in the demo, I followed these steps:

- Created the user **admin** belonging to the **admins** group.
- Created the users **dev** and **superdev** belonging to the **developers** group.
- Created and associated full permissions to the admins group across all namespaces using ClusterRole.
- Created and associated view-only permissions to the developers group across all namespaces using ClusterRole.
- Created and associated full permissions to the superdev user only in the **test** namespace using Role.

The scripts generate a kubeconfig for each user, and all certificates used are stored in a folder named `certs`. I conducted tests using the created kubeconfigs, confirming that permissions are correctly associated with the specified users or groups.

If you are interested, we can take a look together. This approach could also be valuable for Krateo, setting permissions on various CRDs as discussed.

## Check User Account Expiration

I conducted some experiments and can confirm that to check the expiration of accounts, it is possible to automate the verification of the End Date field of the certificate obtained in the CSR created specifically for the user.

The CSRs used for creating the users contain the certificates created in the .status.certificate field. From here, we have everything we need to monitor users, groups (through the CN and O fields of the certificates), and the related ClusterRoleBinding and RoleBinding.

For expiration verification, here's a script to check all certificate expirations against a given threshold:

```bash
#!/bin/bash

DAYS=364
SECONDSPERDAY=86400
THRESHOLD=$(( DAYS * SECONDSPERDAY ))
echo "Checking expiration date with threshold $DAYS day(s)"

CSR_LIST=$(kubectl get csr | awk '{print $1}' | tail -n +2)

CSR_ARRAY=()
while read -r csr; do
   CSR_ARRAY+=("$csr")
done <<< "$CSR_LIST"

for csr in "${CSR_ARRAY[@]}"
do
    CSR_CERT=$(kubectl get csr $csr -o jsonpath='{.status.certificate}')
    CERT_END_DATE=$(echo $CSR_CERT | base64 --decode | openssl x509 -noout -enddate | awk -F '=' '{print $NF}')
    echo $CSR_CERT | base64 --decode | openssl x509 -noout -checkend $THRESHOLD

    echo "$csr ---> $CERT_END_DATE ---> $?"
done
```

Using the command `openssl x509 -noout -checkend $THRESHOLD`, it is possible to determine if a certificate will expire in N days:

- RC == 0: *will not expire* in N days
- RC == 1: *will expire* in N days

This way, for example, you can consider notifying the user that their account is about to expire via:
- Email: possibly by including the `email` field in the CSR `subj` parameter and using it for email notification.
- UI Notification in Krateo: post login

In the CSR field, you can insert an `expirationSeconds` parameter to set the validity of the certificate created with that CSR (int32, minimum=10min, default=365 days). For certificate rotation, there is a dependency on the k8s cluster configurations (<https://kubernetes.io/docs/reference/access-authn-authz/kubelet-tls-bootstrapping/#certificate-rotation>), specifically the `RotateKubeletClientCertificate` parameter.

There are two possible approaches here:

- `RotateKubeletClientCertificate == TRUE`: Notify the user of the new kubeconfig with the new certificate created automatically.
- `RotateKubeletClientCertificate == FALSE`: Create a new CSR and hence a new kubeconfig with a new certificate.

Nothing prevents us from being agnostic regarding the cluster configuration and deciding to manage rotation with a controller of our own, essentially performing the checks from the script above and then making the new kubeconfig available.
