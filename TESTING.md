# Plan de test

## Automatisé

```bash
xcodebuild test \
  -project Whisper.xcodeproj \
  -scheme Whisper \
  -configuration Debug \
  -destination 'platform=macOS'
```

La cible `WhisperTests` couvre :

- silence et enregistrement trop court ;
- voix au-dessus d'un bruit ambiant adaptatif ;
- réponse vide ou égale au vocabulaire de contexte ;
- assemblage multipart et délimiteur final ;
- expiration de l'historique.

## Matrice manuelle avant une release

| Scénario | Résultat attendu |
| --- | --- |
| Appuyer sur Fn sans parler puis relâcher | Aucun appel utile, aucun collage, message « Aucune parole détectée » |
| Dictée courte après le signal | Texte inséré dans l'application initialement active |
| Démarrer une seconde dictée pendant la transcription | Seconde dictée mise en file, sans écraser la première cible |
| Annuler pendant l'appel API | Fichier temporaire supprimé, aucun collage |
| Refuser le microphone | Aucun prompt au lancement, explication dans les réglages |
| Refuser l'accessibilité | Résultat copié dans le presse-papiers, aucun texte perdu |
| Autoriser l'accessibilité puis relancer | Collage natif Cmd+V sans permission Automatisation |
| Copier autre chose pendant l'insertion | Le nouveau presse-papiers utilisateur n'est pas écrasé |
| Mode bascule | Premier appui démarre, second appui envoie |
| Historique désactivé | Fichier local supprimé et aucune nouvelle entrée |
| Clé API restreinte à la transcription | Validation acceptée sans accès à `/v1/models` |

Les tests de qualité acoustique doivent être répétés avec le micro interne, des
AirPods et un micro USB, dans une pièce calme puis avec ventilation/bruit de fond.
Les mesures locales optionnelles permettent de comparer les modèles sur un corpus
réel sans enregistrer son contenu.
