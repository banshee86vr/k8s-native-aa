# Kubernetes native authentication & authorization test

Utilizzando il metodo di autenticazione nativo di K8s tramite i certificati TLS ho implementato lo script sh `create_user_certs.sh` che ti permette di creare un utente e associare i gruppi che vuoi all’interno del certificato stesso. Successivamente con lo script `bind_roles.sh` vengono eseguite delle associazioni di permessi sia sui gruppi che su utenti singoli sfruttando i campi `CN` e `O` dei certificati creati in precedenza per i vari utenti.

Nello specifico nella demo ho seguito questi passi:

* Creazione utente **admin** appartenente al gruppo **admins**
* Creazione utente **dev** e **superdev** appartenenti al gruppo **developers**
* Creato e associato pieni permessi al gruppo admins su tutti i namespace tramite ClusterRole
* Creato e associato permessi di sola visualizzazione al gruppo developers su tutti i namespace tramite ClusterRole
* Creato e associato pieni permessi all’utente superdev solo sul namespace **test** tramite Role

Gli script creano un kubeconfig per ogni utente e tutti i certificati usati in una cartella certs. I test li ho fatti usando proprio i kubeconfig creati, e confermo che i permessi vengono correttamente associati agli utenti o ai gruppi specificati.

Se volete diamo un’occhiata insieme ma potrebbe essere un giro valido anche per Krateo e impostare poi, come discusso, i permessi sulle varie CRD.

## Check usser acctoun expiration

Ho fatto un po’ di prove e confermo che per verificare la scadenza delle utenze è possibile automatizzare il controllo del campo End Date del certificato ottenuto nella CSR creata ad hoc per l’utenza.

Le CSR usate per la creazione delle utenze contengono i certificati creati nel campo .status.certificate. Da qui secondo me abbiamo tutto per poter monitorare le utenze,i gruppi (tramite i campi CN e O dei certificati) e i relativi ClusterRoleBinding e RoleBinding associati.

Per la verifica della scadenza vi riporto uno script fatto per verificare tutte le scadenze dei certificati a fronte di un threshold:

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

Con il comando `openssl x509 -noout -checkend $THRESHOLD` è possibile sapere se quel certificato scadrà tra N giorni:

* RC == 0: *non scadrà* tra N giorni
* RC ==1: *scadrà* tra N giorni

In questo modo, ad esempio, si può pensare di notificare all’utente che la sua utenza sta per scadere tramite:
E-mail: eventualmente inserendo il campo `email` nel parametro `subj` della CSR e sfruttandolo per l’invio della e-mail
Notifica UI Krateo: post login

Nel campo della CSR è possibile inserire un parametro `expirationSeconds` con il quale impostare la validità del certificato creato con quella CSR (int32, minimo=10min, default=365gg). Per la rotazione del certificato invece c’è una dipendenza rispetto alle configurazioni del cluster k8s (<https://kubernetes.io/docs/reference/access-authn-authz/kubelet-tls-bootstrapping/#certificate-rotation>), nello specifico del parametro `RotateKubeletClientCertificate`.

Qui le vie sono due:

* `RotateKubeletClientCertificate == TRUE`: notificare il nuovo kubenconfig con il nuovo certificato creato in automatico
* `RotateKubeletClientCertificate == FALSE`: creare una nuova CSR e quindi un nuovo kubeconfig con nuovo certificato

Nulla vieta di rendersi agnostici rispetto alla configurazione del cluster e decidere di gestire la rotazione con un controller fatto da noi, facendo sostanzialmente i controlli dello script sopra e poi rendere disponibile il nuovo kubeconfig.
