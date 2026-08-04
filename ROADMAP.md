# Roadmap Pressay

Pressay devient une barre de commande vocale locale et contrôlable pour les
développeurs et les professionnels sur macOS. La dictée universelle reste le
socle ; la différenciation vient du contexte explicite, des transformations
réversibles, du mode développeur et d’actions strictement typées.

Une capacité n’apparaît dans l’interface que si son parcours principal, ses
erreurs, ses permissions et sa politique de confidentialité sont terminés. Une
implémentation automatisée réussie ne vaut pas validation de release : la
matrice interapplications, la signature et le test sur une session macOS propre
restent des gates distincts.

## État d’implémentation au 4 août 2026

| Lot | État du code | Gate restant |
| --- | --- | --- |
| 1.0 — Dictée fiable | Livré dans le socle existant | Gates de distribution 1.0 documentés dans `AUDIT.md` |
| 1.1 — Fondation | Machine d’état, coordinateur injectable, capture AX, validation de cible, annulation, session unique, HUD audio, double pression, enregistreur de raccourcis et canal Sparkle bêta codés | Matrice manuelle et validation matérielle |
| 1.2 — Modes et transformation | Schéma v2 migrable, 12 modes natifs, modes personnalisés, profils opt-in, consentement cloud interactif, sélection AX/fallback transactionnel, aperçu, replay mémoire, HUD configurable, correction vocale, Inbox chiffrée et politiques de livraison par app codés ; stable 1.2.4 (12103) avec restauration du presse-papiers et compatibilité Codex, 120 tests Swift actifs | Sept jours de dogfood sans P0/P1, matrice Tier A/B, Intel réel et mise à jour Sparkle interactive 1.2.3 → 1.2.4 |
| 1.3 — Local/hybride | Routeurs, catalogue signé/SHA-256, SpeechAnalyzer, installation des assets système, Foundation Models et sélection des fournisseurs par mode codés derrière les gardes SDK/compiler | Chaîne Xcode 26 dédiée, tests audio réels FR/EN, benchmark M2, fournisseurs téléchargés FluidAudio/whisper.cpp/llama.cpp, interface Modèles complète et corpus |
| 1.4 à 2.1 | Contrats de domaine préparés pour les actions, l’historique et les capacités | Implémentation produit et gates propres à chaque lot |

La suite automatisée contient actuellement **120 tests Swift et 5 tests Python actifs**.
Elle complète, sans remplacer, la matrice interapplications et matérielle.

## 1.0.0 — Identité et dictée fiable

- identité Pressay et migration des deux anciens bundle IDs ;
- dictée Fn/Globe, raccourcis actuels et mode maintenir/bascule ;
- détection locale du silence et validation anti-hallucination ;
- session de transcription unique, cible d’insertion conservée et annulation ;
- historique local AES-256-GCM ;
- Sparkle, DMG Developer ID notarialisé, GitHub Releases et portfolio.

## 1.1.0 — Fondation du moteur

- extraire `SessionCoordinator`, `VoiceSession` et la machine d’état ;
- injecter les protocoles de capture, transcription, traitement, contexte,
  livraison, aperçu, historique, modèle et action ;
- router séparément dictée, transformation et commande ;
- gérer double pression mains libres, Échap, conflits et refus explicite des
  invocations concurrentes ;
- mémoriser l’élément AX initial et refuser les champs sécurisés ;
- valider application, élément et sélection avant chaque remplacement ;
- fournir un HUD interactif et une annulation locale de la dernière insertion ;
- ajouter un canal Sparkle bêta distinct du stable.

## 1.2.0 — Modes contextuels et transformation

- modes Fidèle, Propre, Message, Email, Prompt IA, Note, Compte rendu, Ticket,
  Commit, Traduction, Résumé et Tâches ;
- modèle de données commun aux modes natifs et personnalisés, schéma v2,
  migration v1 et sauvegarde conservée deux lancements ;
- résolution déterministe : raccourci, mode explicite, application, manuel,
  défaut ;
- profils d’application suggérés uniquement pour les apps installées et activés
  explicitement ;
- transformation vocale d’une sélection via AX puis fallback `Cmd+C` avec
  restauration sérialisée du presse-papiers ;
- aperçu Original/Proposition éditable avant remplacement ;
- limites de contexte par mode, consentement selon la politique et manifeste
  exact des sources envoyées au cloud ;
- replay audio éphémère en mémoire, copie, retranscription et annulation
  vérifiée de l’insertion ;
- profils initiaux Mail, messagerie, notes, outils IA, tickets, IDE et terminal.

## 1.3.0 — Local, hybride et cloud

- `TranscriptionRouter`, `ProcessingRouter` et gestionnaire de modèles ;
- Parakeet/FluidAudio sur Apple Silicon et `whisper.cpp` sur Intel ;
- `SpeechAnalyzer` et Foundation Models sur les Mac compatibles ;
- GGUF optionnel pour les transformations locales sur macOS 14/15 ;
- politiques `localOnly`, `preferLocal`, `askBeforeCloud` et `cloudAllowed` ;
- téléchargement repris, SHA-256, licence, suppression et fallback sans boucle ;
- corpus FR/EN et gate qualité/latence avant tout changement de moteur par défaut.

## 1.4.0 — Wedge développeur

- projets autorisés par security-scoped bookmarks ;
- contexte projet minimal et visible : dépôt, branche, Git synthétique, langage
  et fichier actif ;
- modes Prompt de code, Bug structuré, Rubber Duck, Branche, Commit, PR, Ticket,
  Logs et Commande terminal ;
- export Markdown avant toute intégration distante ;
- commandes et scripts uniquement éditables et copiables, jamais exécutés.

## 1.5.0 — Voice Inbox et historique enrichi

- inbox automatique en l’absence de champ éditable ;
- extraction structurée du titre, projet, tags, tâches et dates ;
- migration vérifiée de `history.enc` vers un `HistoryRepository` enrichi ;
- recherche locale, filtres, brut/final, retraitement, export et suppression ;
- audio optionnel, chiffré et à rétention indépendante ;
- destinations Markdown, Obsidian autorisé, Rappels et Calendrier ;
- presse-papiers intelligent limité aux productions de Pressay.

## 1.6.0 — Mémoire et personnalité

- entrées typées : mot, prononciation, remplacement, projet, langue et priorité ;
- mémoire projet minimale et règles rédactionnelles explicites ;
- suggestion de règle après correction, jamais d’apprentissage silencieux ;
- identités Personnel, Professionnel, Client, Technique, Commercial, Concis,
  Chaleureux et Formel ;
- profil dérivé d’échantillons volontaires, supprimés par défaut après validation ;
- règles versionnées, explicables, exportables et supprimables.

## 1.7.0 — Barre de commande et moteur d’actions

- palette non activante avec raccourci configurable ;
- `ActionProposal` validée par schéma, risque déterministe et préconditions ;
- exécuteurs locaux limités : ouvrir, copier, préparer un rappel/événement,
  écrire dans un fichier autorisé et préparer un Shortcut ;
- aperçu, confirmation, idempotence, journal local et résultat explicite ;
- même politique dans l’interface, Siri, App Intents et Raccourcis ;
- aucune sortie de modèle reliée directement à un exécuteur.

## 1.8.0 — Intégrations

- GitHub, Linear et Notion via OAuth à permissions minimales ;
- Obsidian, Rappels, Calendrier et Shortcuts comme intégrations locales ;
- tokens Keychain, scopes visibles, révocation et dernier usage ;
- retry contrôlé, clé d’idempotence et détection de doublons ;
- CLI et MCP locaux limités à l’historique, aux modes, aux propositions et à
  l’Inbox, sans action sensible hors confirmation dans l’app.

## 1.9.0 — Pressay Pro optionnel

- cœur utilisable sans compte ;
- authentification web Authorization Code + PKCE, appareils et révocation ;
- synchronisation E2EE des modes, vocabulaire, mémoire et préférences admises ;
- audio, historique et tokens exclus par défaut ;
- Stripe Checkout/Portal et cloud géré optionnel ;
- repli systématique vers local ou BYOK en cas de panne ou déconnexion.

## 2.0.0 — Réunions

- session et stockage séparés des dictées courtes ;
- capture consentie du microphone et de l’audio système via ScreenCaptureKit ;
- indicateur persistant et manifeste récupérable après crash ;
- transcription locale, diarisation compatible et piste micro identifiée ;
- résumé, décisions, questions, actions, responsables et échéances ;
- export Markdown, PDF et email, sans envoi automatique.

## 2.1.0 — Finition et généralisation

- navigation Historique, Inbox, Modes, Mémoire, Projets, Intégrations, Modèles,
  Confidentialité et Raccourcis ;
- résultat post-insertion : Annuler, Retranscrire, Copier et Brut/Final ;
- App Intents finalisés avec la même politique d’action ;
- français/anglais, clavier, VoiceOver, contraste et réduction des animations ;
- statistiques et diagnostics locaux sans contenu ;
- onboarding demandant chaque permission au premier usage réel.

## Gate commun

Avant chaque tag : tests unitaires et d’intégration, analyse statique, benchmark,
archive universelle, signature, notarisation, Gatekeeper, checksum, appcast,
installation propre, mise à jour depuis la stable précédente et revue des
permissions, scopes, licences et suppressions de données.
