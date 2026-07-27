# Audit technique — Whisper macOS

Date : 27 juillet 2026

## Synthèse

Le produit a une bonne base : peu de dépendances, une architecture lisible, une clé API dans le Trousseau et un flux push-to-talk très direct. La version 1.1 corrige le défaut le plus visible — l'envoi et le collage d'une hallucination sur un enregistrement silencieux — et renforce les points fragiles du chemin critique.

La version 1.2 industrialise le chemin critique : tests automatisés, détection
adaptative, permissions guidées, historique chiffré, mesures locales, file
d'attente, annulation, CI et préparation de la notarisation.

## Flux applicatif

1. `KeyboardService` observe uniquement la touche Fn/Globe.
2. `AudioRecorder` enregistre en AAC mono 16 kHz et mesure le niveau sonore.
3. `AppState` annule localement si aucune voix n'est détectée.
4. `TranscriptionService` envoie le fichier, la langue et le vocabulaire à `gpt-4o-mini-transcribe`.
5. La réponse vide ou égale au vocabulaire de contexte est rejetée.
6. `TextInjector` réactive l'app cible, colle le texte et restaure le presse-papiers si l'utilisateur ne l'a pas modifié.
7. `HistoryService` conserve localement les transcriptions pendant 24 heures.

## Corrections et améliorations livrées

- Détection locale du silence avant tout appel API.
- Protection secondaire contre le retour exact du vocabulaire de contexte.
- Déclenchement limité à Fn/Globe, sans faux positif sur F1 à F12.
- Choix français, anglais ou détection automatique.
- Vocabulaire technique modifiable dans les préférences.
- Température de transcription déterministe et délais réseau bornés.
- Validation de clé sans écriture temporaire d'une clé invalide.
- Conservation de tous les formats du presse-papiers et protection contre les copies concurrentes.
- Rafraîchissement réactif de l'historique dans le menu.
- Écriture atomique de l'historique.
- Retour utilisateur explicite lorsqu'aucune voix n'est détectée.
- Icône macOS complète et couleur d'accent dédiée.

## Recommandations prioritaires

### P0 — Fiabilité

- Ajouter une suite de tests unitaires pour la détection de silence, le filtrage des réponses, le multipart et la rétention de l'historique.
- Ajouter un test UI manuel automatisable couvrant : appui Fn silencieux, dictée courte, refus micro, refus accessibilité, changement de presse-papiers pendant l'injection.
- Enregistrer des métriques locales anonymes et optionnelles de durée par étape, sans audio ni texte, pour mesurer capture, upload, transcription et collage.
- Remplacer le seuil sonore fixe par une calibration du bruit ambiant ou une détection d'activité vocale adaptative.

### P1 — Expérience

- Afficher un petit HUD non activant près du curseur : écoute, transcription, succès, annulation.
- Ajouter un raccourci configurable en alternative à Fn et un mode bascule pour les dictées longues.
- Ajouter « Annuler » pendant la transcription et une file d'attente pour pouvoir redicter immédiatement.
- Exposer le choix de conserver ou non l'historique, sa durée et un bouton de copie du dernier résultat.
- Guider les permissions dans un onboarding plutôt que de demander l'accessibilité au lancement.

### P1 — Distribution et sécurité

- Configurer une équipe Apple, la signature Developer ID, le hardened runtime et la notarisation.
- Réévaluer le sandbox macOS. L'injection globale peut imposer des contraintes, mais la désactivation doit être un choix documenté.
- Ajouter une politique de confidentialité courte et explicite pour l'audio, le texte et l'historique.
- Vérifier le comportement des clés OpenAI restreintes : l'endpoint `/models` utilisé pour la validation peut être interdit alors que la transcription est autorisée.
- Chiffrer ou désactiver l'historique pour les environnements manipulant des données sensibles.

### P2 — Performance et qualité de reconnaissance

- Mesurer avant de migrer vers le streaming de transcription de fichier : le gain dépend surtout de la durée des dictées.
- Évaluer `gpt-4o-transcribe` contre `gpt-4o-mini-transcribe` sur un corpus réel avant d'offrir un mode « précision maximale ».
- Exploiter les log-probabilités disponibles pour signaler les transcriptions incertaines, après calibration sur des exemples réels.
- Pour les longues dictées, écrire le multipart en flux plutôt que de charger deux copies du fichier en mémoire.
- Ajouter des profils de vocabulaire par contexte (développement, noms de clients, médical, juridique) sans envoyer plus de contexte que nécessaire.

## Recommandations intégrées en version 1.2

- 8 tests unitaires et une matrice de validation manuelle.
- VAD énergétique adaptatif au bruit de chaque dictée.
- HUD non activant, raccourcis alternatifs et mode bascule.
- Annulation et file de dictées conservant leur application cible.
- Historique AES-256-GCM optionnel et rétention configurable.
- Mesures de latence locales, anonymes et opt-in.
- Choix mini/précision, profils de vocabulaire et indicateur de faible confiance.
- Multipart audio écrit par blocs sur disque.
- Validation des clés restreintes sur l'endpoint audio, sans `/v1/models`.
- Hardened Runtime Release, CI, politique de confidentialité et script de notarisation.

## Limites connues de la version 1.2

- Le VAD adaptatif est énergétique : il réduit fortement les faux positifs mais
  ne distingue pas sémantiquement une voix d'un bruit soudain.
- Les 350 premières millisecondes sont ignorées pour ne pas classer le son de démarrage comme de la parole ; l'utilisateur doit parler après le signal.
- Le collage dépend de l'autorisation Accessibilité et d'AppleScript/System Events.
- La qualité et le seuil de faible confiance doivent être calibrés sur un corpus
  réel et plusieurs microphones.
- La notarisation finale nécessite le certificat et le compte Apple Developer du
  propriétaire ; le dépôt contient toute la préparation mais aucun secret.
- Le streaming de fichier n'est pas activé : les métriques ajoutées doivent d'abord
  démontrer un gain, conformément à la recommandation d'audit.
