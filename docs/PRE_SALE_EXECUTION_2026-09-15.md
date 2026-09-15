# Exécution du plan Mac App Store — 15 septembre 2026

## Corrections et préparation réalisées

- Le workflow de publication n'utilise plus le compteur GitHub comme numéro de
  build. Deux entrées explicites portent le nouveau numéro et le plus grand build
  relevé dans Apple. Le contrôle compare les composantes numériques, réserve les
  archives jusqu'à 2.0.4 et refuse les numéros anciens, dupliqués ou invalides.
- Le script local de création d'archive exige le code de conformité approuvé,
  vérifie sa correspondance dans le binaire et conserve la déclaration de
  chiffrement non exempté. Il applique le même contrôle de numéro que le workflow.
- Les tests des contrôles de publication sont intégrés à la CI. Le workflow
  conserve le paquet signé et les dSYM avant l'envoi pour préserver les preuves
  même si Apple refuse le paquet. Les noms d'artefacts distinguent les relances.
- Une [procédure exécutable](app-store/release-runbook.fr.md) couvre GitHub Actions,
  Xcode, la récupération après un envoi incertain et la sélection du bon candidat.
- La [matrice native](app-store/native-release-matrix.fr.md) contient 37 cas avec
  résultats attendus et un protocole de performance. Aucun n'est marqué réussi
  sans exécution sur le candidat distribué par Apple.
- Le brouillon de confidentialité distingue le contenu des modes synchronisé
  sous chiffrement des journaux et diagnostics qui doivent exclure ce contenu.
  Il précise Apple pour la connexion native et les fournisseurs configurés pour
  le web. Les déclarations finales restent à confronter à la recette réelle.

## Vérifications exécutées

| Contrôle                                                                                          | Résultat                                                        | Limite                                                                                                                        |
| ------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `bun run test:unit`                                                                               | 14 tests, 50 assertions réussis                                 | Inclut quatre nouveaux tests de numérotation ; aucune transaction Apple réelle                                                |
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
Les 334 tests Rust de la variante production avaient été validés lors du lot
précédent ; ils n'ont pas été relancés localement pour ces changements de scripts
et de documentation.

## État des accès et blocages

L'environnement GitHub `app-store-production` est limité à `main`. Les huit noms
de secrets nécessaires à la signature et à l'API Apple sont présents. Leur contenu
n'a pas été affiché. La variable `MAS_EXPORT_COMPLIANCE_CODE` est absente.

La session App Store Connect Chrome a expiré. La page de connexion a été laissée
ouverte et une reconnexion a été demandée. Aucun état du chiffrement, du DSA ou
des produits Apple postérieur au 10 septembre n'est donc affirmé. La recherche
Gmail ciblée sur les réponses Apple récentes concernant Pressay n'a donné aucun
résultat ; cela ne remplace pas la consultation du dossier Apple.

Le justificatif de **7 allée des Jonquilles, 95130 Franconville** et l'existence
d'un contrat de médiation ont été demandés. Aucune pièce d'adresse n'a été inventée
ou envoyée, aucun contrat souscrit. Le brouillon de relance Apple reste disponible.

La PR 94 nécessite toujours une revue humaine du diff final avant fusion,
conformément à AGENTS.md. L'accord sur l'exécution du plan n'est pas présenté
comme une revue de modifications qui n'existaient pas encore.

## Prochaine action dépendante

Après reconnexion : vérifier la décision Apple et, si le code est délivré, le
configurer, sélectionner un nouveau numéro supérieur aux envois réels et construire
depuis le code approuvé. Puis distribuer dans TestFlight, exécuter la matrice et
corriger ses échecs avant App Review. Finaliser le DSA dès réception du justificatif.

Aucun nouveau paquet n'a été envoyé, aucun achat réel effectué et aucune
publication Store ou ouverture des ventes n'est revendiquée dans ce rapport.
