# Exécution du plan Mac App Store — 15 septembre 2026

## Corrections et préparation réalisées

- Le workflow de publication n'utilise plus le compteur GitHub comme numéro de
  build. Deux entrées explicites portent le nouveau numéro et le plus grand build
  relevé dans Apple. Le contrôle compare les composantes numériques, réserve les
  archives jusqu'à 2.0.4 et refuse les numéros anciens, dupliqués ou invalides.
  Le contrôle connecté a retrouvé **12001** dans la version 1.2.0 : ce maximum
  historique est désormais un plancher obligatoire. Le prochain candidat est
  **12002**, sous réserve d'une nouvelle lecture Apple au moment de construire.
  Les numéros à cinq chiffres sont acceptés conformément à la documentation Apple
  actuelle ; la comparaison entière évite tout arrondi JavaScript.
- Le script local de création d'archive exige le code de conformité approuvé,
  vérifie sa correspondance dans le binaire et conserve la déclaration de
  chiffrement non exempté. Il applique le même contrôle de numéro que le workflow.
- Les tests des contrôles de publication sont intégrés à la CI. Le workflow
  conserve le paquet signé et les dSYM avant l'envoi pour préserver les preuves
  même si Apple refuse le paquet. Les noms d'artefacts distinguent les relances.
- Une [procédure exécutable](app-store/release-runbook.fr.md) couvre GitHub Actions,
  Xcode, la récupération après un envoi incertain et la sélection du bon candidat.
- La [matrice native](app-store/native-release-matrix.fr.md) contient 37 cas avec
  résultats attendus et un protocole de performance, ainsi que 40 phrases de
  référence FR/EN non confidentielles. Aucun cas n'est marqué réussi sans exécution
  sur le candidat distribué par Apple.
- Le brouillon de confidentialité distingue le contenu des modes synchronisé
  sous chiffrement des journaux et diagnostics qui doivent exclure ce contenu.
  Il précise Apple pour la connexion native et les fournisseurs configurés pour
  le web. Les déclarations finales restent à confronter à la recette réelle.
- La nouvelle CI a identifié **RUSTSEC-2026-0285**, publiée le 14 septembre :
  rustls 0.23.36 est remplacé par 0.23.45 et rustls-webpki 0.103.13 par 0.103.15.
  Seules ces deux entrées du lockfile changent. La variante Store utilise rustls
  via `ureq` et `hf-hub`. Aucun nouvel avis de sécurité n'est ignoré. Le workflow
  construit désormais avec `--locked --no-default-features`, comme son contrôle
  du graphe de dépendances, pour utiliser le lockfile corrigé.

## Vérifications exécutées

| Contrôle                                                                                          | Résultat                                                        | Limite                                                                                                                        |
| ------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `bun run test:unit`                                                                               | 15 tests, 49 assertions réussis                                 | Inclut cinq nouveaux tests de numérotation ; aucune transaction Apple réelle                                                  |
| `python3 -m unittest discover -s scripts -p 'test_package_macos_store.py'`                        | 3 tests réussis                                                 | Reproduit les configurations de chiffrement manquantes/incorrectes ; ne valide pas un code auprès d'Apple                     |
| `bun run lint` et `bun run build`                                                                 | Réussis                                                         | Frontend compilé ; pas d'installation TestFlight                                                                              |
| `bun run check:translations`                                                                      | 803 clés cohérentes, anglais et 23 autres langues               | Cohérence des clés, pas une relecture linguistique exhaustive                                                                 |
| `bun run storekit:validate`                                                                       | Réussi                                                          | Catalogue local mensuel/annuel, pas validation des produits dans Apple                                                        |
| `bun run format:check`                                                                            | Réussi après ajout du chemin Rust installé au PATH du processus | Prettier et Rustfmt ; aucun changement de configuration système                                                               |
| Clippy release, `production-mac-app-store`, `storekit-purchases`, tous les targets, `-D warnings` | Réussi                                                          | Aucun code métier Rust modifié dans ce lot ; avertissement existant de compatibilité future de `block 0.1.6`                  |
| YAML des deux workflows modifiés et `git diff --check`                                            | Réussis                                                         | Analyse YAML locale ; exécution GitHub à vérifier sur la nouvelle révision                                                    |
| Site public, `PLAYWRIGHT_BASE_URL=https://press-say.app pnpm test:e2e`                            | 32 réussis, 10 ignorés car réservés au serveur local            | Deux profils mobile/desktop ; Node local 24.9.0 avec avertissement du projet demandant Node 22 ; aucune modification du site  |
| API publique, `validate:staging` avec URL de production et fournisseur Apple attendu              | 8 contrôles réussis                                             | Santé, base, auth/PKCE, clé publique des droits et accès protégés ; pas de paiement ni de mutation des comptes                |
| `bun run voice-os:probe-models`                                                                   | 6 contrôles réussis                                             | HEAD/taille attendue sur route principale et secours de chaque modèle ; pas de téléchargement intégral ni mesure de précision |

Les 12 contrôles GitHub de la révision précédente
`1fa94587cb8abb5fdc79d9591602143227f2cd15` ont été vérifiés réussis le 15 septembre.
Ils incluent les tests Linux précédemment en échec. Les résultats de cette ancienne
révision ne sont pas présentés comme ceux des nouvelles modifications du workflow.
Après la correction rustls, les **334 tests Rust release** passent à nouveau
localement avec `production-mac-app-store` et `storekit-purchases`, ainsi que
Clippy. Le journal est `/tmp/pressay-mas-tests-20260915.log`. Les changements
ultérieurs concernent les scripts de publication, leurs tests et la documentation ;
la suite Rust n'est pas présentée comme une recette native TestFlight.
`cargo-audit` n'étant pas installé localement, sa validation est confiée au job
GitHub dédié, avec la même exception préexistante pour l'option rkyv non activée.

Sur la révision corrigée `69ea74b57a32a20ea47fecf8f3a690107680eb54`,
[l'audit de sécurité passe](https://github.com/YoannDrx/pressay/actions/runs/34961891500)
et [les trois variantes macOS passent chacune 334 tests](https://github.com/YoannDrx/pressay/actions/runs/34961891488),
avec Clippy. Les tests Linux, la qualité du code, Playwright et les scans de secrets
passent aussi. La compilation locale release et les constructions intégrales
GitHub sont suivies séparément jusqu'à leur conclusion.

Source du correctif : [avis officiel rustls](https://github.com/rustls/rustls/security/advisories/GHSA-2mjx-qc3c-rqvc).

## État des accès et blocages

L'environnement GitHub `app-store-production` est limité à `main`. Les huit noms
de secrets nécessaires à la signature et à l'API Apple sont présents. Leur contenu
n'a pas été affiché. La variable `MAS_EXPORT_COMPLIANCE_CODE` est absente.

La session Chrome initialement expirée est ensuite redevenue accessible. Le
**15 septembre**, les contrôles connectés ont confirmé :

- Chiffrement : document du 23 août toujours en « Vérification », valeur de clé « - ».
- Business : adresse de Franconville correcte ; contrats gratuits/payants, banque,
  formulaires fiscaux, DSA et DAC7 affichés actifs.
- Le formulaire DSA séparé contient encore l'ancienne adresse parisienne. La
  correction vers Franconville et les coordonnées sont préparées ; l'étape
  « Pièce justificative d'adresse » interdit de continuer sans document.
  La nouvelle adresse n'est donc pas encore soumise/validée dans ce formulaire.
- TestFlight : 2.0.3 est le dernier build traité de 2.0.0, avec informations
  manquantes. L'ancienne version 1.2.0 contient le build **12001**, prêt à soumettre.
  Aucun groupe de test ni installation de recette n'est constaté.
- Gmail : le filtre `{to:(@press-say.app) subject:Pressay}` applique uniquement
  `Apps/Pressay`, sans suppression, archivage ou marquage comme lu.

La relance est remplie dans le formulaire Apple Developer « Configuration d'app >
Chiffrement », avec le statut du 15 septembre ; elle n'est pas envoyée et attend
l'accord explicite demandé. Aucun justificatif d'identité ou d'adresse n'y est joint.

Le justificatif de **7 allée des Jonquilles, 95130 Franconville** et l'existence
d'un contrat de médiation ont été demandés. Aucune pièce d'adresse n'a été inventée
ou envoyée, aucun contrat souscrit. Le brouillon de relance Apple reste disponible.

La PR 94 nécessite toujours une revue humaine du diff final avant fusion,
conformément à AGENTS.md. L'accord sur l'exécution du plan n'est pas présenté
comme une revue de modifications qui n'existaient pas encore.

## Prochaine action dépendante

Après décision Apple : si le code est délivré, le
configurer, sélectionner un nouveau numéro supérieur aux envois réels et construire
depuis le code approuvé. Puis distribuer dans TestFlight, exécuter la matrice et
corriger ses échecs avant App Review. Finaliser le DSA dès réception du justificatif.

Aucun nouveau paquet n'a été envoyé, aucun achat réel effectué et aucune
publication Store ou ouverture des ventes n'est revendiquée dans ce rapport.
