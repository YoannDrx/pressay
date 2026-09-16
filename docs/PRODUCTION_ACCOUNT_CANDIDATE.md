# Candidat compte production — 16 septembre 2026

Ce candidat 2.0.0-rc.1 utilise explicitement `production-direct` et l’API `https://api.press-say.app`. Les versions beta.3/beta.4 publiées utilisent le serveur de test ; leurs appareils ne figurent donc pas dans l’espace de production du site.

```sh
bun install --frozen-lockfile
bun run build:production-candidate
```

Le script compile l’application Apple Silicon/macOS 14+ avec les fonctions de mise à jour, sans `commercial-entitlements` et sans `storekit-purchases`. Il ne publie aucun manifeste de mise à jour ni tag. L’override désactive seulement la génération des archives de mise à jour de ce candidat local ; les artefacts publics restent produits par le workflow de release signé et notarié.

Au changement de serveur géré par Pressay, les anciens identifiants compte/appareil sont retirés du cache local ; l’identifiant d’installation reste stable. La prochaine connexion réenregistre le Mac dans la base de production. Aucune ligne de test n’est copiée dans la production, aucune dictée ou clé de fournisseur n’est modifiée. Une reconnexion peut être nécessaire si l’ancien jeton appartient au serveur de test.

Ce candidat repose sur la branche de préparation `codex/production-readiness-audit` (PR 94), incluant la liaison explicite entre serveur et clé publique des droits. Il ne certifie pas la recette commerciale complète et n’ouvre aucun paiement. Sa préparation ne fusionne pas automatiquement la PR 94 dans main.

À vérifier sur le binaire : signature et intégrité ; connexion avec le même compte que sur le site ; apparition d’un seul Mac sur `/account/devices` ; actualisation ; relance sans doublon ; accès local inchangé. La configuration de l’application déjà installée n’est pas éditée à la main pour simuler cet enregistrement.

## Résultat de compilation locale

Le 16 septembre 2026, `build:production-candidate` a produit une application arm64, macOS 14 minimum, signée Developer ID Application (équipe G9WFV7HNV6) avec hardened runtime. `codesign --verify --deep --strict` réussit. La sortie de compilation confirme `PRESSAY_RESOLVED_CLOUD_API_URL=https://api.press-say.app`. Le binaire et ses symboles partagent l’UUID `85B98777-CF6D-3C68-8EAD-3E6F0C89230F`.

La notarisation n’a pas eu lieu : aucun identifiant de notarisation n’est configuré dans l’environnement local. `stapler validate` confirme l’absence de ticket et `spctl` retourne `Unnotarized Developer ID`. Ce candidat n’est donc pas prêt à distribuer. Il n’a pas remplacé la bêta installée. Aucun contournement de Gatekeeper ni changement des réglages de sécurité macOS n’a été effectué.

Le bundle et les symboles sont conservés hors dépôt dans `pressay-builds/2.0.0-rc.1-production`. SHA-256 de l’exécutable signé : `c5a23f7844521ec3981537416363cf098dd50a66f8173b3833c3995fc79b1de8`. Aucun artefact binaire n’est ajouté au dépôt.

## Vérifications du code

- Compilation frontend TypeScript/Vite, lint, traductions et format du dépôt : réussis.
- 15 tests unitaires Bun : réussis.
- 334 tests Rust de bibliothèque en release, avec `production-direct` et `updater` : réussis, dont les deux contrôles de migration d’environnement.
- Clippy release `--all-targets --features updater -- -D warnings` : réussi. Cargo signale séparément une incompatibilité avec une future version de Rust dans la dépendance existante `block 0.1.6`.
- Les essais réels d’OAuth, d’enregistrement du Mac dans la liste web et de relance restent ouverts ; les tests unitaires ne les remplacent pas.

## Candidat notarié par GitHub Actions

Le workflow manuel `Production account candidate` utilise les accès Apple déjà configurés dans GitHub Actions. Il accepte uniquement le commit courant de `main`, sélectionne explicitement `production-direct` sans fonctions commerciales, puis réutilise la compilation signée. L’étape finale notarise aussi le DMG, vérifie les tickets, Gatekeeper et la signature de l’application montée. Elle conserve le DMG vérifié avec son SHA-256 et le commit source dans un artefact de trente jours. Elle ne crée ni release publique ni manifeste de mise à jour.

Après fusion : lancer ce workflow sur `main`, attendre le succès de `verify-and-retain`, télécharger `pressay-production-candidate-verified`, vérifier le SHA-256 puis installer l’application du DMG après vérification de Gatekeeper.
