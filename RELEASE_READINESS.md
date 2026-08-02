# Pressay — préparation de publication

État de référence : 2 août 2026

Ce document distingue ce qui est automatisable dans le dépôt des actions qui
nécessitent App Store Connect, des certificats, un Mac de test ou une décision
commerciale. La publication ne doit pas mélanger les deux éditions.

## Décision de lancement

Publier d'abord Pressay comme produit **gratuit et BYOK**, sans compte requis :

- la distribution directe reste l'édition principale, avec dictée universelle,
  insertion sûre, raccourcis globaux et mises à jour Sparkle ;
- le Mac App Store distribue Pressay Companion dans App Sandbox, avec copie dans
  le presse-papiers et Voice Inbox, sans Accessibilité ni Sparkle ;
- OpenAI couvre la transcription temps réel et la transformation ; WhisperKit
  couvre la transcription locale hors ligne ;
- le compte, le cloud géré et les achats restent invisibles ou inactifs tant que
  leur environnement de production et leurs parcours de suppression ne sont pas
  terminés.

Cette première publication mesure l'activation et la rétention sans ajouter le
risque StoreKit, les coûts d'inférence de Pressay ou une dépendance au backend.

## État des deux canaux

| Gate | Direct 1.2.2 (12101) | Mac App Store 1.2.0 (12005) |
| --- | --- | --- |
| Bundle | `fr.yodev.pressay` | `fr.yodev.pressay` |
| Architectures | `arm64 + x86_64` | `arm64 + x86_64` |
| Sécurité | Hardened Runtime, Developer ID | App Sandbox, Hardened Runtime |
| Mise à jour | Sparkle signé | Mac App Store uniquement |
| Confidentialité | manifeste inclus | manifeste inclus |
| Automatisation | DMG, notarisation, checksum, appcast | archive et export App Store |
| État externe | 1.2.2 reste à taguer après QA | 12001 est en TestFlight interne ; 12002 à 12004 sont obsolètes ; 12005 doit être archivé et téléversé |

La gate locale complète est :

```sh
scripts/release-readiness.sh
```

Elle valide les plists et entitlements, exécute les tests Swift, construit les
deux éditions en Release universelle, contrôle la séparation Sparkle/App Store,
vérifie les captures et métadonnées, puis teste les scripts d'appcast.

## Actions externes restantes — Mac App Store

1. Consolider et relire les changements depuis un commit identifié, puis créer
   une nouvelle archive signée 12005. Les anciens paquets ne correspondent plus
   au moteur de transcription livré.
2. Téléverser 12005 avec Xcode Organizer ou Transporter. Ne jamais
   réutiliser les builds 12001 à 12004.
3. Installer 12005 depuis TestFlight sur un compte macOS propre et tester :
   microphone refusé/accordé, réseau hors ligne, clé invalide, OpenAI,
   WhisperKit, historique désactivé et suppression de la Voice Inbox.
4. Refaire les trois captures 1440 × 900 si l'écran Fournisseurs visible a
   changé depuis les images actuelles.
5. Publier les réponses App Privacy : Audio Data et Other User Content,
   fonctionnalité uniquement, sans tracking, potentiellement liés au compte du
   fournisseur via sa clé API.
6. Compléter classification d'âge, disponibilité, copyright, URL d'assistance,
   URL de confidentialité, conformité export et coordonnées App Review.
7. Donner à App Review une clé OpenAI temporaire, isolée dans un projet
   à budget faible, puis la révoquer après décision.
8. Associer le build, choisir une publication manuelle, ajouter la version à la
   revue, puis soumettre seulement après validation TestFlight.

## Actions externes restantes — distribution directe

1. Terminer la matrice Tier A/B de `RELEASE_1_2_CHECKLIST.md`, avec au moins un
   Mac Apple Silicon et un Mac Intel.
2. Tester stable vers bêta, bêta vers stable et stable vers stable avec deux
   versions réellement signées.
3. Vérifier qu'aucun P0/P1 n'est observé pendant sept jours auprès d'au moins
   cinq testeurs.
4. Relire et pousser les changements, puis créer le tag `v1.2.2`. Le workflow
   GitHub fabrique le DMG Developer ID, le notarise avec `notarytool`, agrafe le
   ticket, génère le SHA-256 et l'appcast signé, et publie la release.
5. Retélécharger le DMG public et contrôler indépendamment Gatekeeper,
   architectures, version, checksum, signature Sparkle et mise à jour depuis la
   version précédente.

La machine possède une identité Developer ID Application valide et les
certificats Mac App Store nécessaires, mais aucun profil `notarytool` local
nommé `pressay-notary`. La notarisation automatisée du workflow GitHub reste
donc le chemin de publication directe le plus sûr.

## Monétisation recommandée

Ne pas lancer immédiatement trois abonnements. Le meilleur ordre est :

1. **Free BYOK** au lancement : dictée fidèle, protections, trois modes,
   historique court. Aucun compte obligatoire.
2. **Pro BYOK** après mesure de la rétention : 7,99 €/mois ou 69 €/an, avec tous
   les modes, profils par app, historique enrichi, mémoire et retraitement.
3. **Lifetime BYOK** à 149 € pour les founding users, limitée dans le temps et
   excluant clairement le cloud futur.
4. **Pro Cloud** seulement lorsque proxy, quotas, rate limit, suppression de
   compte, observabilité sans contenu et marge sont prouvés : 12,99 €/mois ou
   109 €/an.
5. **Teams** après preuve de demande B2C : politiques, vocabulaire partagé,
   facturation et gestion des appareils, cible 18 €/siège/mois.

Sur la distribution directe, Stripe peut vendre les droits numériques. Sur le
Mac App Store, toute fonctionnalité numérique payante doit disposer d'un achat
StoreKit équivalent ; le bouton Stripe reste donc absent de cette édition. Les
abonnements ne doivent être soumis qu'après StoreKit 2, restauration des achats,
webhook App Store, réconciliation, grâce hors ligne et tests Sandbox complets.

## Features à implémenter ensuite

### P0 — activation et fiabilité, 2 à 3 semaines

- onboarding guidé jusqu'à une première dictée récupérable en moins de deux
  minutes ; permissions demandées au premier usage ;
- réglages redimensionnables avec navigation Général, Fournisseurs, Modes,
  Raccourcis, Données, Abonnement et À propos ;
- lancement au démarrage via `SMAppService` ;
- erreurs providers normalisées, choix de modèle allowlisté et un fallback
  explicite sur panne transitoire uniquement ;
- trace locale sans contenu indiquant provider, modèle, latence et fallback ;
- matrice de tests interapplications et parcours TestFlight propre.

### P1 — rétention et valeur Pro, 3 à 6 semaines

Implémenté dans le build local du 2 août 2026 : historique enrichi/recherchable,
favoris, tags, exports, retraitement avec consentement, Voice Inbox structurée
et premières propositions d’actions chiffrées. SQLite, mémoire explicite et
benchmark de corpus restent ouverts.

- historique SQLite local avec recherche, favoris, filtres, export et
  retraitement dans un autre mode ;
- mémoire explicite de vocabulaire/corrections, toujours confirmée et
  supprimable ;
- Voice Inbox structurée avec projets, tags, tâches et export Markdown/Obsidian ;
- modes développeur Bug, Commit, PR, Ticket et Rubber Duck, en sortie éditable
  ou copiable uniquement ;
- benchmark FR/EN OpenAI/WhisperKit et sélection claire latence/qualité.

### P2 — revenu récurrent, 4 à 8 semaines après P1

- fournisseur OIDC production et suppression de compte de bout en bout ;
- branche Neon production protégée et migration contrôlée ;
- déploiement API Vercel, rate limiting, logs structurés et tests Postgres ;
- entitlements signés, grâce hors ligne et migration Founding User ;
- StoreKit 2 + App Store Server Notifications, puis Stripe direct ;
- cloud géré avec quotas et coût atomique, sans persistance audio/texte.

### P3 — différenciation

Le build du 2 août 2026 privilégie volontairement OpenAI + WhisperKit. Les
autres moteurs ne seront réévalués qu’après mesure de ce chemin simple.

- préchargement WhisperKit mesuré et optionnel ;
- moteurs locaux Apple/Parakeet/whisper.cpp après benchmark qualité ;
- intégrations Obsidian, Rappels, Calendrier, GitHub, Linear puis Notion ;
- actions typées avec aperçu, confirmation et idempotence ; jamais d'exécution
  directe d'une sortie de modèle.

## Base de données

Conserver Neon. C'est un Postgres standard, la région UE et les branches de base
conviennent très bien à Pressay. Le besoin immédiat n'est pas de changer de
base, mais de terminer l'identité, les migrations de production, les sauvegardes,
les tests d'intégration et les procédures de suppression. L'app macOS ne doit
jamais recevoir la chaîne de connexion Neon ; seule l'API y accède.

## Go / no-go

Une release est **Go** uniquement si la gate automatisée est verte, la matrice
manuelle est signée, une installation propre fonctionne, les métadonnées
décrivent exactement l'édition testée et aucune clé de production n'est incluse
dans le bundle. En cas de rejet App Review, conserver la version directe active,
corriger le build App Store avec un nouveau numéro et ne jamais contourner le
sandbox pour restaurer l'insertion universelle.
