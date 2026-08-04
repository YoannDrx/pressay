# Audit fonctionnel et technique — Pressay 1.2.3

État de référence : 4 août 2026
Commit de départ : `8c325d9`
Canal public au début de l'audit : `1.2.2` (`12101`)

## Règles de lecture

Une fonctionnalité n'est marquée **fonctionnelle et validée** que si son chemin
nominal, ses erreurs, ses permissions, sa suppression de données et ses tests
automatisés et manuels sont terminés. Une compilation ou un test unitaire seul
ne prouve pas le fonctionnement dans les applications tierces.

| État | Définition |
| --- | --- |
| Fonctionnelle et validée | Automatisation et validation manuelle représentative terminées |
| Fonctionnelle, non validée manuellement | Code et tests actifs verts, gate matériel ou inter-apps ouverte |
| Partielle | Parcours utile présent, mais erreurs, UX, plateforme ou tests incomplets |
| Désactivée | Ancien code ou tests conservés hors compilation/runtime |
| Préparée seulement | Contrats, schéma ou backend présents sans parcours utilisateur complet |
| Absente | Aucun parcours livrable dans le code actuel |

## Matrice exhaustive

| Domaine | Parcours utilisateur | Direct | App Store | Preuves actives | Gate restant |
| --- | --- | --- | --- | --- | --- |
| Dictée Fidèle OpenAI | Maintenir, parler, relâcher, insérer | Fonctionnelle, non validée manuellement | Partielle : capture depuis l'interface et copie | `SessionCoordinator`, 114 tests Swift actifs | Matrice Tier A/B, réseau réel, Intel |
| Dictée WhisperKit | Télécharger puis dicter hors ligne | Partielle | Partielle | Service épinglé, états de téléchargement, builds universels | Corpus FR/EN, mémoire/énergie, Apple Silicon réel |
| Raccourcis globaux | Fn, modificateur droit, combinaison, bascule | Fonctionnelle, non validée manuellement | Non applicable par sandbox | Tests de conflits et transitions | Claviers physiques, dispositions FR/EN |
| Mains libres | Double pression puis arrêt explicite | Fonctionnelle, non validée manuellement | Absente | Routeur de raccourcis et HUD | Tests UI et session longue |
| Silence et hallucinations | Ne rien livrer sans parole | Fonctionnelle, non validée manuellement | Fonctionnelle, non validée manuellement | VAD adaptatif et validation de réponse testés | Micros interne/AirPods/USB et bruit réel |
| Cible AX sûre | Revenir au champ initial | Fonctionnelle, non validée manuellement | Non applicable | Identité, fenêtre, rôle, sélection et hash testés | TextEdit à Word, web et Electron |
| Insertion native | Remplacer via Accessibilité | Fonctionnelle, non validée manuellement | Non applicable | Tests UTF-16, sélection et rôles AX | Fixture AX réelle et apps Tier A/B |
| Collage web/Electron | Coller dans navigateur, Slack, Cursor | Fonctionnelle, non validée manuellement | Non applicable | Politique navigateur/Electron testée | Google Docs, Notion, Cursor, Slack réels |
| Restauration du presse-papiers | Retrouver le contenu copié avant Fn | Fonctionnelle, non validée manuellement | Non applicable : copy-only | Snapshot multiformat et politique de concurrence testés | Collage réel, images, gestionnaires de presse-papiers |
| Copie de secours | Récupérer le résultat si la cible échoue | Fonctionnelle, non validée manuellement | Fonctionnelle, non validée manuellement | Raisons d'échec et fallback testés | Notifications et erreurs réelles |
| Annulation | Échap pendant capture ou traitement | Fonctionnelle, non validée manuellement | Partielle | Transitions et nettoyage audio testés | API lente, aperçu et raccourci réel |
| File de dictées | Démarrer une seconde dictée pendant le traitement | Absente dans le runtime actuel | Absente | Un test actif vérifie désormais le refus de la seconde capture | Décider entre refus explicite et vraie file |
| Douze modes natifs | Choisir le format de sortie | Fonctionnelle, non validée manuellement | Fonctionnelle, non validée manuellement | Catalogue et résolution testés | Qualité linguistique par mode |
| Modes personnalisés | Créer prompt, format et exemples | Fonctionnelle, non validée manuellement | Fonctionnelle, non validée manuellement | Persistance atomique et migration v2 testées | UX, erreurs OpenAI, FR/EN |
| Profils par application | Mode et livraison par bundle | Fonctionnelle, non validée manuellement | Non applicable | Priorités et politiques testées | Matrice apps et migration utilisateur |
| Transformation de sélection | Parler pour modifier une sélection | Fonctionnelle, non validée manuellement | Non applicable | Capture AX/fallback, aperçu et revalidation testés | Sélections web/Office et changements concurrents |
| Contexte contrôlé | Choisir les sources envoyées | Fonctionnelle, non validée manuellement | Partielle | Restriction, manifeste et 50 injections passives testés | Inspection réseau et VoiceOver |
| Consentement cloud | Voir et autoriser le payload exact | Fonctionnelle, non validée manuellement | Fonctionnelle, non validée manuellement | Refus, brut et invalidation de signature testés | Expiration réelle et parcours complet |
| Historique chiffré | Chercher, taguer, exporter, retraiter | Fonctionnelle, non validée manuellement | Fonctionnelle, non validée manuellement | Rétention, enrichissement et export testés | Migration SQLite future, gros volumes |
| Voice Inbox | Structurer et archiver les idées | Fonctionnelle, non validée manuellement | Fonctionnelle, non validée manuellement | Opt-in, extraction locale et chiffrement testés | UX complète, suppression et exports réels |
| Actions sûres | Préparer note, rappel ou événement | Partielle | Partielle | Risque, idempotence et journal local testés | Exécuteurs système et validations bout en bout |
| OpenAI | Transcription et transformation BYOK | Fonctionnelle, non validée manuellement | Fonctionnelle, non validée manuellement | Multipart, Responses `store:false`, erreurs principales | Matrice HTTP complète et clés restreintes réelles |
| Groq, Deepgram, Anthropic | Choisir un fournisseur alternatif | Désactivée | Désactivée | Tests historiques sous `#if false` | Contrats v2, UI, benchmarks et consentement |
| Onboarding | Première valeur en moins de deux minutes | Partielle | Partielle | Fenêtres et permissions compilées | Chemin WhisperKit sans clé OpenAI, test UI |
| Lancement au démarrage | Activer Pressay avec macOS | Fonctionnelle, non validée manuellement | Fonctionnelle, non validée manuellement | `SMAppService` et état UI | Redémarrage réel et refus système |
| HUD et correction | Suivre, corriger, copier, annuler | Fonctionnelle, non validée manuellement | Partielle | États, actions et politiques testés indirectement | Tests UI, VoiceOver, réduction des animations |
| Migrations Whisper → Pressay | Conserver préférences, clés et fichiers | Fonctionnelle, non validée manuellement | Non applicable | Priorité, idempotence et reprise Keychain testées | Installation d'anciennes builds réelles |
| Sparkle | Détecter et installer une mise à jour | Partielle | Non applicable | Configuration et appcast signés ; feed 1.2.2 restauré le 3 août | Mise à jour stable → stable signée |
| DMG Developer ID | Télécharger et installer sans alerte | Partielle | Non applicable | Workflow, notarisation historique et scripts | Rejouer 1.2.3, session propre, Intel |
| Pressay Companion | Installer depuis le Mac App Store | Partielle | Partielle | Build 12005 sandbox universel validé | Nouvelle archive, TestFlight et App Review |
| Compte Pressay | Se connecter par navigateur | Préparée seulement | Préparée seulement | Backend OIDC local ; tests client historiques désactivés | Client PKCE actif, Clerk et suppression de compte |
| Entitlements Free/Pro | Déverrouiller les fonctions achetées | Préparée seulement | Préparée seulement | Endpoint complet et snapshot Ed25519 backend ; client absent | Validation client, feature gates et grâce hors ligne |
| Stripe Direct | Acheter mensuel, annuel ou lifetime | Partielle | Non applicable | Catalogues test/live créés, Checkout TTC et essai sans carte durcis, Portal, webhooks et réconciliation, 16 tests backend actifs | Clerk, API/Neon production, webhook live, immatriculation fiscale et paiement E2E |
| StoreKit 2 | Acheter dans l'édition App Store | Absente | Absente | Schéma serveur seulement | StoreKit, notifications Apple et restauration |
| Landing `press-say.app` | Découvrir, comparer et acheter | Partielle | Partielle | Domaine canonique et Next.js 16 FR/EN déployés, trois CTA tarifaires, 8 tests Playwright | Clerk, API live, DNS `api`, paiement et portail E2E |
| Portfolio | Découvrir et télécharger la stable | Fonctionnelle et validée pour 1.2.2 | Non concerné | Build Next.js et redirection publique vérifiés | Mise à jour 1.2.3 après publication |
| Localisation FR/EN de l'app | Utiliser toute l'interface en anglais | Partielle | Partielle | Quelques libellés et modes | Catalogue de chaînes et QA complète |
| Métriques privées | Voir des durées sans contenu | Fonctionnelle, non validée manuellement | Fonctionnelle, non validée manuellement | Agrégats et export allowlisté testés | Vérification des écrans et gros volumes |

## Complétude par domaine

Les pourcentages sont des indicateurs de pilotage fondés sur les gates terminés,
pas une mesure de couverture de lignes.

| Domaine | Complétude | Motif principal |
| --- | ---: | --- |
| Dictée et protections | 78 % | Automatisation forte, matrice réelle encore ouverte |
| Modes, contexte et transformation | 72 % | Parcours codés, qualité/UX inter-apps à prouver |
| Données locales et récupération | 74 % | Historique/Inbox riches, migration SQLite ouverte |
| Providers et local | 48 % | OpenAI solide, WhisperKit non benchmarké, autres désactivés |
| Distribution Direct | 62 % | Chaîne présente, 1.2.3 et mise à jour signée à rejouer |
| Mac App Store | 55 % | Binaire conforme, nouveau TestFlight et revue absents |
| Comptes et monétisation | 55 % | Catalogue Stripe live prêt et backend durci ; identité, API et entitlement client restent à activer |
| Landing et acquisition | 78 % | Site et domaine public en ligne ; les CTA commerciaux attendent Clerk et l'API live |

## Écarts prioritaires

### P0 — bloque une release

- terminer la validation manuelle du presse-papiers après le correctif ;
- vérifier une mise à jour Sparkle signée `1.2.2 → 1.2.3` ;
- rejouer la matrice Tier A/B sur Apple Silicon et Intel ;
- conserver l'appcast public en `200` et faire échouer la release sinon.

### P1 — bloque le lancement payant

- activer le client Clerk/OAuth PKCE et la suppression de compte ;
- implémenter la validation d'entitlement, le claim Founding et la grâce hors ligne côté client ;
- durcir la preuve Founding avant production : le marqueur local est unique et
  borné par version/date/appareil, mais un client Direct ne fournit pas à lui
  seul une attestation matérielle infalsifiable ;
- terminer le paiement Stripe E2E en mode test, y compris annulation,
  remboursement, paiement asynchrone et désordre ;
- ajouter les feature gates sans supprimer ni rendre inexportables les données ;
- relier la landing et les pages légales à `press-say.app` après QA staging.

### P2 — améliore rétention et différenciation

- terminer la localisation FR/EN et l'onboarding WhisperKit sans clé ;
- ajouter mémoire explicite et pack développeur ;
- benchmarker WhisperKit puis réévaluer les providers alternatifs ;
- terminer les intégrations locales avant les réunions et Teams.

## Preuves exécutées le 3 août 2026

- 114 tests Swift actifs réussis après le correctif presse-papiers et le marqueur Founding ;
- build Release App Store universel `arm64 + x86_64` validé ;
- typecheck backend et 16 tests Vitest actifs réussis ;
- migrations 0001–0004 et essai web sans appareil validés sur la branche Neon
  `preview/pressay-commercial-foundation` ;
- gate locale complète 1.2.3 : Direct/App Store universels et scripts de distribution verts ;
- lint et build Next.js du portfolio réussis ;
- lint, typecheck, build, 8 tests Playwright et Lighthouse 97/96/100/100 du site autonome réussis ;
- déploiement Vercel et domaine canonique `press-say.app` vérifiés ;
- catalogues Stripe test et live créés avec visuel, code fiscal SaaS, tarifs
  mensuel/annuel/Lifetime TTC, clés de recherche et métadonnées d'entitlement ;
- branche `gh-pages` restaurée depuis l'appcast signé de `1.2.2` ;
- `https://yoanndrx.github.io/pressay/appcast.xml` vérifié en HTTP 200.

## Gates manuels non exécutés

- Tier A/B complet et applications distantes/Citrix ;
- AirPods et micro USB dans plusieurs environnements acoustiques ;
- Mac Intel réel ;
- installation propre du futur DMG 1.2.3 ;
- mise à jour Sparkle signée 1.2.2 → 1.2.3 ;
- TestFlight 12005 sur compte propre ;
- Stripe, Clerk et suppression de compte en environnements réels ;
- bascule DNS OVH vers Vercel et validation de `press-say.app`.
