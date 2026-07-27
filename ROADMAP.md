# Roadmap Pressay

Pressay suit une règle simple : une capacité n’apparaît dans l’interface que si
son parcours principal, ses erreurs, ses permissions, ses tests, ses textes
français/anglais et sa politique de confidentialité sont réellement terminés.

## 1.0.0 — Identité et dictée fiable

- identité Pressay et migration des deux anciens bundle IDs ;
- dictée Fn/Globe, raccourcis actuels et mode maintenir/bascule ;
- détection locale du silence et validation anti-hallucination ;
- file de transcription, cible d’insertion conservée et annulation ;
- historique local AES-256-GCM ;
- Sparkle, DMG Developer ID notarialisé, GitHub Releases et portfolio.

## 1.1.0 — Interaction complète

- machine d’état explicite de `idle` à `completed`, `cancelled` ou `failed` ;
- raccourcis configurables dictée, transformation et commande ;
- double pression mains libres, Échap et nouvelle dictée concurrente ;
- HUD enrichi et actions Annuler, Retranscrire, Copier, Brut/Final ;
- détection des champs simples, riches, Markdown, code et sécurisés.

## 1.2.0 — Modes et transformation

- modes fidèle, propre, message, email, prompt, note, compte rendu, ticket,
  commit, traduction, résumé et tâches ;
- profils automatiques par application ;
- transformation fidèle d’une sélection avec restauration du presse-papiers ;
- limites de contexte visibles et traitement hiérarchique explicite.

## 1.3.0 — Local, hybride et cloud

- `whisper.cpp` et gestion vérifiée de modèles ;
- OpenAI rapide/précision et politique par mode ;
- Foundation Models sur les appareils compatibles ;
- GGUF optionnel et fallback déterministe hors connexion.

## 1.4.0 — Voice Inbox et historique

- inbox automatique sans champ modifiable ;
- extraction de titre, projet, tags, tâches et dates ;
- destinations locales Apple Notes, Obsidian, Rappels et Calendrier ;
- historique recherchable, réapplicable, exportable et à rétention séparée.

## 1.5.0 — Vocabulaire, mémoire et style

- dictionnaire personnel global ou projet ;
- suggestions de corrections, jamais apprises silencieusement ;
- mémoire projet minimale et contextuelle ;
- identités rédactionnelles et résumé de style.

## 1.6.0 — Mode développeur

- projets explicitement autorisés par security-scoped bookmarks ;
- contexte Git et éditeur exactement prévisualisé avant envoi ;
- prompts, branches, commits, PR, tickets, bugs et logs ;
- commandes terminal uniquement copiables avant confirmation.

## 1.7.0 — Actions locales

- `ActionProposal` strictement typé ;
- niveau de risque fixé par une politique déterministe ;
- aperçu, confirmation, idempotence, journal local et annulation réelle ;
- suppressions de fichiers uniquement via la Corbeille.

## 1.8.0 — Compte et Pressay Pro

- authentification web PKCE, appareils et révocation ;
- synchronisation chiffrée des préférences non sensibles ;
- Stripe Checkout/Portal, droits et quota géré ;
- repli systématique local ou clé personnelle.

## 1.9.0 — Intégrations

- GitHub, Linear, Notion, Obsidian, Notes, EventKit et outils développeur ;
- OAuth à permissions minimales et tokens distants explicitement non E2EE ;
- extensions Safari/Chromium sans historique de navigation.

## 2.0.0 — Réunions

- capture consentie du microphone et de l’audio système ;
- transcription, intervenants, résumé, décisions et actions ;
- reprise après interruption et export Markdown, PDF ou email ;
- diarisation cloud, transcription locale et limites clairement annoncées.

## 2.1.0 — App Intents et finition

- intents Inbox, fichier, mode, historique, action et réunion ;
- même moteur de confirmation pour l’app, Raccourcis et Siri ;
- interface complète, statistiques locales, onboarding progressif ;
- français/anglais, clavier, VoiceOver et diagnostics sans contenu.

## Gate commun

Avant chaque tag : tests, analyse statique, archive universelle, signatures,
notarisation, Gatekeeper, checksum, appcast, mise à jour depuis la version
précédente, portfolio et approbation de l’environnement GitHub `release`.
