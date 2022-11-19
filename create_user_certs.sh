#!/bin/bash

if [[ -n "${CLEAR_ALL}" ]]; then
    rm -rf ./certs
    minikube delete
    minikube start --driver=docker
fi

if [ "$#" -ne 2 ]; then
    echo "Illegal number of parameters. Usage: create_user.sh <usern_name> <group1,group2,...>"
    exit 1
fi

mkdir certs
cd certs

USER=$1
IFS=',' read -r -a array <<< "$2"
for group in "${array[@]}"
do
    USER_GROUPS=${USER_GROUPS}/O=$group
done

openssl genrsa -out ${USER}.key 2048
openssl req -new -key ${USER}.key -out ${USER}.csr -subj "/CN=${USER}${USER_GROUPS}"


# https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/#create-certificatesigningrequest
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USER}
spec:
  groups:
  - system:authenticated
  request: $(cat ${USER}.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 600
  usages:
  - client auth
EOF

kubectl certificate approve ${USER}

until [[ -s "${USER}.crt" ]]
do
  kubectl get csr ${USER} -o jsonpath='{.status.certificate}' | base64 --decode > ${USER}.crt
done

# Create the kubeconfig file
CONTEXT=$(kubectl config current-context)
CLUSTER=$(kubectl config view -o jsonpath="{.contexts[?(@.name == \"$CONTEXT\"})].context.cluster}")
SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name == \"${CLUSTER}\"})].cluster.server}")
CA=$(kubectl config view --flatten -o jsonpath="{.clusters[?(@.name == \"${CLUSTER}\"})].cluster.certificate-authority-data}")


cat > ${USER}.kubeconfig <<EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: $CA
    server: ${SERVER}
  name: ${CLUSTER}
contexts:
- context:
    cluster: ${CLUSTER}
    user: ${USER}
  name: ${USER}
current-context: ${USER}
kind: Config
preferences: {}
users:
- name: ${USER}
  user:
    client-certificate-data: $(cat ${USER}.crt | base64 | tr -d '\n')
    client-key-data: $(cat ${USER}.key | base64 | tr -d '\n')
EOF

