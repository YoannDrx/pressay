# Procédure de construction et de soumission Mac App Store

## Préconditions

1. Le diff a été relu et approuvé par un humain, puis intégré à `main` ; ses
   contrôles GitHub requis sont réussis.
2. Apple a validé le chiffrement et délivré son code. L'environnement GitHub
   `app-store-production` contient ce code dans `MAS_EXPORT_COMPLIANCE_CODE`.
   Ne jamais utiliser une valeur de test ni retirer la déclaration de chiffrement.
3. Relever dans App Store Connect le plus grand numéro de build macOS, y compris
   les versions publiques précédentes. Le compteur GitHub n'est pas cette valeur.
4. Choisir un nouveau numéro supérieur à cette valeur et à l'archive réservée
   `2.0.4`. Au dernier état vérifié, `2.0.3` avait été traité et `2.0.4` avait été
   refusé ; revérifier Apple avant d'utiliser ces valeurs.

Le 15 septembre, les noms des huit secrets de signature/API requis sont présents
dans l'environnement GitHub, autorisé uniquement pour la branche `main`.
Leur présence ne valide ni leur contenu ni leur date d'expiration. La variable de
conformité n'est pas configurée. Aucun secret n'est copié dans ce document.

## Construction GitHub Actions

Ouvrir le workflow **Pressay Mac App Store Archive**, choisir `main`, puis renseigner :

- `build_number` : nouveau numéro à utiliser pour cet envoi ;
- `previous_build_number` : plus grand numéro effectivement observé dans Apple ;
- `upload=false` pour construire et inspecter le paquet, ou `upload=true` pour
  construire, valider et téléverser le candidat.

Le contrôle local équivalent est :

```bash
bun scripts/check-app-store-build.ts 2.0.5 2.0.3
```

Ces nombres illustrent le passage après les archives connues. Le validateur ne
consulte pas Apple : la fraîcheur du second paramètre doit être vérifiée dans
App Store Connect avant chaque envoi, sans téléversement concurrent via Xcode.

Après un envoi réussi ou incertain, vérifier si Apple a reçu le build avant de
relancer. Une nouvelle construction destinée à Apple utilise un nouveau numéro
et un nouveau lancement du workflow. Une relance aveugle avec le même numéro
n'est pas une stratégie de récupération.

Le workflow construit la variante `storekit-purchases`, vérifie les chemins de
distribution, signe puis conserve le paquet, sa somme SHA-256 et ses dSYM avant
l'étape d'envoi. Les artefacts ont une rétention de 30 jours : archiver la version
retenue et ses preuves dans le dossier de candidats avant expiration. La présence
d'un artefact prouve une construction, pas une acceptation par Apple.

## Chemin Xcode avec signatures locales

Le script `scripts/package-macos-store.py` reste disponible pour préparer une
archive Organizer depuis une application déjà signée et ses symboles correspondants.
Il exige désormais deux arguments supplémentaires :

- `--export-compliance-code` : valeur réellement approuvée, qui doit déjà être
  présente dans l'Info.plist signé ;
- `--previous-build-number` : plus grand numéro relevé dans Apple.

Il refuse le code absent/différent, les anciennes archives, un profil expiré, une
signature incompatible, les droits de débogage et des symboles non correspondants.
Ne pas modifier l'Info.plist après signature : toute modification exige une
nouvelle signature avant ce contrôle.

Conserver `package-evidence.json`, `SHA256SUMS`, la signature et l'archive.
`uploaded: false` décrit la préparation locale ; consigner séparément la preuve
d'envoi et l'identifiant du build traité par Apple.

## Après traitement Apple

1. Installer le nouveau build via TestFlight.
2. Exécuter la [matrice native](native-release-matrix.fr.md) et corriger les échecs.
3. Finaliser les [notes App Review](review-notes.md), la vidéo, les captures,
   les déclarations de confidentialité et les métadonnées FR/EN.
4. Vérifier les dossiers Apple, l'adresse DSA à Franconville et les conditions de
   vente avant la soumission. Sélectionner le nouveau build avec les abonnements
   nécessaires, puis soumettre.
5. Après acceptation et publication, constater le téléchargement depuis le Store,
   contrôler les parcours publics et aligner le site. Garder la vente fermée tant
   que les conditions du [plan de déploiement](deployment-plan.fr.md) ne sont pas remplies.

## Sources

- [Numéro de build macOS](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion)
- [Documentation de chiffrement et code Apple](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation)
