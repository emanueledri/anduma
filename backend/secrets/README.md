# secrets/ — credenziali locali (NON versionate)

Questa cartella è ignorata da git (vedi `.gitignore`): **non committare mai**
chiavi o segreti qui dentro. Il repo è pubblico.

## Service account Firebase (M4)

Salva qui il JSON della service account scaricato dalla console Firebase
(Impostazioni progetto → Account di servizio → Genera nuova chiave privata):

```
backend/secrets/firebase-admin.json
```

Il backend lo carica via variabile d'ambiente (default già puntato a questo path):

```bash
export TT_FCM_CREDENTIALS_FILE=secrets/firebase-admin.json
```

Solo questo `README.md` è tracciato; il `.json` resta locale.
