# Préparation commerciale — 10 septembre 2026

Pressay n’est pas encore publié sur le Mac App Store. Le candidat actuel est
**2.0.0 (2.0.4)** : compilé, signé et empaqueté, mais son envoi Xcode a été refusé
avec « Invalid Export Compliance Code » (identifiant Apple de l’erreur :
`078d88f1-e0e8-42dd-9842-f8b9376504da`). Il conserve la déclaration correcte
`ITSAppUsesNonExemptEncryption=true`. Le document déposé le 23 août est toujours
« Vérification », sans valeur de clé disponible.

Le build précédent 2.0.3 avait été traité et associé à la version ; sa tentative
« Ajouter pour vérification » était déjà refusée pour attestations manquantes.
Il est désormais dépassé par le code du candidat 2.0.4. Il a été détaché de la
version App Store en préparation et la fiche a été sauvegardée sans build associé.

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

Archive actuelle conservée dans
`/Users/yoannandrieux/Projets/Pressay-release-candidates/2.0.0-2.0.4/packaged/Pressay.xcarchive`.
Le build utilise `production-mac-app-store`, `storekit-purchases`, le service de
production et les mises à jour Apple. Il intègre le main `f5d06c6` : relais OAuth
Apple dans le navigateur, annulation de session, état du compte et diagnostics
expurgés, plus les corrections de l’audit. Le commit source de construction est
`6d2fd4f`. Les changements ultérieurs concernent les tests, la CI et la documentation.

Le paquet signé a pour SHA-256
`1e639d98c623cc064d624d9e1937cf3cd26acf05cd1f1681c076c7f4fc87491b` ;
son dSYM correspond à l’exécutable (`38A3A387-0F8C-3916-9ED1-2C0A98D49EAE`).
L’envoi via App Store Connect a été tenté et refusé pour conformité chiffrement.
Il n’existe donc pas de build 2.0.4 traité à sélectionner dans App Store Connect.
L’identifiant `92cac7fa-ca9f-4895-ba23-c2daef7f42b4` appartient au précédent 2.0.3.

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
- Tests Rust : **334 réussis** en release avec `storekit-purchases` et
  `production-mac-app-store`, le 10 septembre. Un test auparavant lié au staging
  a été corrigé pour vérifier les migrations dans les deux environnements et
  leur idempotence. **Clippy release, toutes cibles, avertissements refusés : réussi**.
  CI macOS du commit `bf37b6f` : Clippy et 334 tests réussis pour chacune des
  configurations `updater`, `mas` et `storekit-purchases`. Le build Apple Silicon
  complet de GitHub est également réussi.
- Détection de secrets : trois faux positifs d’empreintes SHA-256 de fichier
  sont exclus par leur fingerprint exact ; les autres contrôles restent actifs.
- CI Rust Linux : 328 tests réussis, un test supposait encore une bêta même pour
  une version stable. Son attente a été corrigée et le cas de régression passe
  localement en build stable direct, sans changer le code de production. La suite
  directe complète repasse avec **334 tests réussis**, et Clippy avec `-D warnings`
  réussit également. Le push de cette correction de test relance la CI ; le
  résultat Linux précédent n’est pas présenté comme vert.
- Nix : le téléchargement API d’une crate renvoyait HTTP 403. Le téléchargement
  utilise maintenant le CDN officiel avec les checksums inchangés de Cargo.lock ;
  l’archive concernée a été vérifiée contre son checksum. **Le build Nix complet
  du commit `bf37b6f` a réussi** (run `34471665315`). Linux reste un contrôle
  de compatibilité, pas une cible de distribution.

Le moteur du build 2.0.3 a été mesuré avec un extrait anglais synthétique
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
4. **Adresse confirmée ; correction DSA à valider.** Le propriétaire confirme
   7 allée des Jonquilles, 95130 Franconville. Le site et le compte professionnel
   Apple indiquent cette adresse. Le formulaire DSA distinct reprenait néanmoins
   Paris ; il a été rempli avec Franconville, Gmail et le numéro autorisés. Apple
   demande un justificatif d’adresse (PDF/JPEG/PNG, 10 Mo maximum) avant de
   finaliser cette correction. Aucun document ni changement DSA n’a été soumis.
   La recherche publique du SIREN 803272590 ne fournit pas de justificatif
   utilisable : les données sont non diffusibles et la commune du siège renvoyée
   reste Paris. Cette donnée administrative ne remplace pas l’adresse actuelle
   confirmée par le propriétaire ; son document permettra de vérifier la cohérence.
   Le dossier Developer Support `20000144124147` de changement vers Paris reste
   obsolète : ne pas lui transmettre de justificatif pour cet ancien changement.
5. **Revue du code natif.** L’AGENTS.md du dépôt exige une revue et une approbation
   humaines avant fusion. La préparation, les tests et le build n’y substituent pas
   une approbation. Ne pas fusionner automatiquement la PR native.

La vente directe et les promesses de fonctionnalités Cloud doivent rester alignées
avec les capacités réellement activées et testées. Le site ne prétend pas que
l’application est déjà disponible sur le Mac App Store. Une fois les gates levés,
soumettre l’app et les deux abonnements ensemble, attendre la décision d’Apple,
puis publier et remplacer le lien de téléchargement par le lien Store effectif.

## Sources et suite prête à utiliser

- Apple DSA et justificatifs : https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/
- Registre public consulté : https://recherche-entreprises.api.gouv.fr/search?q=803272590&per_page=1
- Apple Sandbox : https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox
- Remboursement Apple : https://support.apple.com/118223
- Obligations de médiation : https://www.economie.gouv.fr/mediation-conso/vous-etes-un-professionnel/vos-principales-obligations-0
- Tarif CM2C : https://www.cm2c.net/tarifs.php
- Notes de review : `docs/app-store/review-notes.md`
- Recette TestFlight : `docs/app-store/testflight.fr-FR.md`
- Relance Apple prête à relire : `docs/app-store/export-compliance-follow-up.fr.md`
