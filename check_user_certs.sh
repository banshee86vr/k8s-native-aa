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