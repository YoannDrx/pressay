# Préparation commerciale — 10 septembre 2026

Pressay n’est pas encore publié sur le Mac App Store. Le build 2.0.0 (2.0.3)
a été construit, signé, validé et envoyé à Apple, qui a terminé son traitement.
Il est associé à la version 2.0.0. La tentative « Ajouter pour vérification »
est refusée : « Les attestations pour l’exportation de ce build sont manquantes. »
Le document déposé le 23 août est toujours « Vérification », sans valeur de clé.

## Corrections livrées

### Abonnements et serveur

La PR https://github.com/YoannDrx/pressay-cloud/pull/40 est fusionnée.
La production sert le commit `bc31eb1814c47d0887e7cb0d2508f65b40ccada7`,
déploiement `dpl_HYJuaJpeEqmhe4QUiDDvd6x7WqQY`.

Un défaut PostgreSQL empêchait la finalisation de certains événements Apple et
Stripe : l’UPDATE d’un événement inséré dans un CTE voisin ne voyait pas cette
nouvelle ligne. Les droits n’étaient donc pas recalculés. La finalisation est
maintenant atomique, effectuée par une fonction SQL avec des commandes successives.
Les tests utilisent aussi un vrai PostgreSQL et couvrent activation, doublons et
révocation après remboursement.

La production vérifie désormais les transactions Sandbox utilisées par App Review,
avec les certificats Apple, le bundle, le compte et l’API Apple correspondant à
l’environnement. Les transactions Sandbox sont séparées des achats réels,
ne les écrasent pas et n’obtiennent pas leur délai commercial hors ligne de 72 h.
Les deux URL de notification Apple pointent vers le serveur de production,
conformément au nouveau build. Le compte utilisé dans un test reste un compte de test.

La migration `0016_app_review_sandbox.sql` a été testée sur un clone Neon puis
appliquée en production. Une branche sans calcul `pre-0016-production-20260910`
(`br-bold-flower-b2magctw`) conserve l’état antérieur. Les contrats de schéma passent.
Hono, Vitest et js-yaml ont été corrigés ; l’audit des dépendances retourne zéro avis.

### Site et support

La PR https://github.com/YoannDrx/pressay-web/pull/23 est fusionnée.
Le commit `c5fdaa62cb0a0a9a29ce38a3699ef6d23650df53` a été déployé puis promu
sur https://press-say.app, déploiement `dpl_8N3y1ExANpE4899AisKfBJR5cwkF`.

- L’échec ou le ralentissement de l’API GitHub ne casse plus le téléchargement :
  délai maximal de 2,5 s, cache de 60 s et repli sur la bêta 3 déjà vérifiée.
- Les tests suivent la version effectivement publiée (actuellement bêta 4).
- Les contacts publics utilisent `yoann.andrieux@gmail.com`, avec un objet
  `[Pressay] Support`, `[Pressay] Rétractation` ou `[Pressay] Secure Input`.
- Le filtre Gmail existant a été modifié et relu après sauvegarde :
  `{to:(@press-say.app) subject:Pressay}` applique `Apps/Pressay`, sans archivage,
  lecture automatique, suppression ou contournement du filtre antispam.
- Les pages françaises et anglaises distinguent les achats Apple des achats
  directs Stripe et mentionnent la connexion Apple.
- Aucun alias `hello@pressay.fr` ni redirection non vérifiée n’est annoncé.
  Aucun email de test ni message à un tiers n’a été envoyé.

Le numéro fourni par le propriétaire est enregistré dans le contact App Review.
Les liens de contact ont été vérifiés ; une réception de nouveau courrier depuis
un expéditeur externe n’a pas été simulée.

### Candidat natif et review

Archive conservée dans
`/Users/yoannandrieux/Projets/Pressay-release-candidates/2.0.0-2.0.3/packaged/Pressay.xcarchive`.
Le build utilise `production-mac-app-store`, `storekit-purchases`, le service de
production et les mises à jour Apple. Il a été envoyé via le canal App Store Connect,
pas « TestFlight Internal Only ». Son identifiant Apple est
`92cac7fa-ca9f-4895-ba23-c2daef7f42b4`.

Les notes de review sauvegardées expliquent le téléchargement initial du modèle,
le parcours local sans compte, la connexion Apple, l’achat et la restauration.
La fiche conserve une publication manuelle tant que les derniers contrôles ne sont
pas terminés. Les produits mensuel et annuel restent à soumettre avec l’application.

## Vérifications effectuées

- Serveur : 119 tests dans 25 fichiers, dont cinq scénarios avec PostgreSQL réel ;
  types, lint, format, secrets et audit des dépendances réussis.
- Production API : huit contrôles réussis après déploiement ; santé, schéma 0016,
  connexion Apple, OAuth PKCE, clé de droits et authentification obligatoire.
- Site local : 40 tests Playwright réussis, deux réservés à un environnement distant
  ignorés ; cinq tests unitaires de téléchargement ; TypeScript, lint et build réussis.
- Site public après promotion : 32 tests Playwright réussis, dix scénarios propres
  à la configuration locale ignorés. Contrôle visuel du support et du lien mailto.
- Application : build de production, signature, profil, dSYM et paquet validés ;
  lint et cohérence des 24 langues (anglais inclus) réussis le 10 septembre.
- Application frontend : 16 scénarios Playwright réussis le 10 septembre, avec
  captures synthétiques des écrans Compte et Historique ; Prettier et Rustfmt réussis.
- Tests Rust/Clippy : résultats du 7 septembre conservés dans les preuves précédentes ;
  pas présentés comme une nouvelle exécution le 10 septembre. Les modifications natives de cette journée
  concernent la version stable et la construction de distribution.

Le moteur du binaire de release a été mesuré avec un extrait anglais synthétique
de 7,707 s, trois passages par modèle, sur le Mac M2 16 Go sous macOS 26.3.1.
Médianes : Fast 288 ms, Polyglot 499 ms, Precise 3 570 ms, backend Metal MTL0.
Le processus a été isolé en mode portable avec des copies des modèles installés.
Cette mesure exclut microphone, VAD, collage, exactitude linguistique et latence de
bout en bout. Trois passages ne constituent pas un percentile de performance.
Le premier essai sans modèle installé dans le nouveau répertoire a échoué ; aucun
problème d’inférence n’a subsisté après fourniture des modèles au répertoire de test.

## Blocages et recette restant à terminer

1. **Exportation/chiffrement Apple.** Attendre ou faire traiter le dossier déjà
   déposé. L’ANSSI a accusé réception le 22 août ; le message retrouvé ne constitue
   pas l’attestation finale. Aucune exemption n’a été inventée pour contourner Apple.
2. **Recette Apple réelle.** Après déblocage : installer via TestFlight, tester la
   connexion, achat mensuel/annuel, annulation, achat interrompu, restauration,
   renouvellement, expiration, remboursement, puis le parcours micro → texte.
   Tester la synchronisation sur deux Mac et documenter les combinaisons de
   versions macOS/permissions. La vidéo de review reste à réaliser sur ce parcours.
3. **Médiateur de la consommation.** Aucun contrat existant n’a été confirmé par
   le propriétaire. Les conditions publiques maintiennent l’ouverture payante
   bloquée. Une option à examiner est CM2C : 48 € pour trois ans jusqu’à dix personnes,
   puis 36 € par médiation à distance, selon leur tarif public. L’éligibilité de
   l’activité et la convention doivent être confirmées avant signature/paiement
   et avant de publier ses coordonnées comme médiateur de YoDev.
4. **Adresse professionnelle.** Apple affiche encore Franconville. Le dossier
   Developer Support `20000144124147` demande un justificatif pour le changement
   vers Paris. Les contrats sont actifs ; aucun blocage automatique supplémentaire
   lié à l’adresse n’est affiché. L’adresse finale et le justificatif restent à
   confirmer. Aucune donnée juridique incertaine n’a été remplacée.
5. **Revue du code natif.** L’AGENTS.md du dépôt exige une revue et une approbation
   humaines avant fusion. La préparation, les tests et le build n’y substituent pas
   une approbation. Ne pas fusionner automatiquement la PR native.

La vente directe et les promesses de fonctionnalités Cloud doivent rester alignées
avec les capacités réellement activées et testées. Le site ne prétend pas que
l’application est déjà disponible sur le Mac App Store. Une fois les gates levés,
soumettre l’app et les deux abonnements ensemble, attendre la décision d’Apple,
puis publier et remplacer le lien de téléchargement par le lien Store effectif.

## Sources et suite prête à utiliser

- Apple Sandbox : https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox
- Remboursement Apple : https://support.apple.com/118223
- Obligations de médiation : https://www.economie.gouv.fr/mediation-conso/vous-etes-un-professionnel/vos-principales-obligations-0
- Tarif CM2C : https://www.cm2c.net/tarifs.php
- Notes de review : `docs/app-store/review-notes.md`
- Recette TestFlight : `docs/app-store/testflight.fr-FR.md`
- Relance Apple prête à relire : `docs/app-store/export-compliance-follow-up.fr.md`
