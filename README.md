# Whisper

Une app macOS ultra simple pour transcrire ta voix en texte, directement depuis ta barre de menu.

Maintiens la touche **Fn** enfoncée, parle, relâche, et le texte apparaît là où se trouve ton curseur. C'est tout.

## Comment ça marche ?

1. L'app vit dans ta barre de menu (en haut à droite de ton écran)
2. Tu maintiens la touche **Fn** enfoncée
3. Tu parles
4. Tu relâches **Fn**
5. Le texte transcrit est automatiquement collé là où tu étais en train d'écrire

L'app utilise l'endpoint de transcription audio OpenAI avec `gpt-4o-mini-transcribe`. C'est rapide, précis, et le vocabulaire technique est personnalisable.

## Installation

### Prérequis

- macOS 14 (Sonoma) ou plus récent
- Une clé API OpenAI ([créer un compte ici](https://platform.openai.com/api-keys))
- Xcode (pour compiler l'app)

### Étapes

1. **Clone le repo**
   ```bash
   git clone https://github.com/YoannDrx/whisper.git
   cd whisper
   ```

2. **Ouvre le projet dans Xcode**
   ```bash
   open Whisper.xcodeproj
   ```

3. **Compile et lance** (Cmd + R)

4. **Configure ta clé API**
   - Clique sur l'icône Whisper dans la barre de menu
   - Va dans les réglages
   - Entre ta clé API OpenAI (commence par `sk-...`)

5. **Accorde les permissions**
   - **Microphone** : pour enregistrer ta voix
   - **Accessibilité** : pour coller le texte automatiquement

## Lancer Whisper au démarrage du Mac

Pour que Whisper se lance automatiquement quand tu allumes ton Mac :

1. Ouvre **Réglages Système**
2. Va dans **Général** > **Ouverture**
3. Clique sur le **+** en bas de la liste
4. Cherche et sélectionne **Whisper** dans tes Applications
5. C'est bon !

Maintenant Whisper sera toujours prêt à t'écouter dès que tu démarres ton Mac.

## Fonctionnalités

### Transcription instantanée
Maintiens **Fn**, parle, relâche. Le texte apparaît. Simple.

### Historique (24h)
L'app garde un historique de tes transcriptions des dernières **24 heures**. Pratique pour retrouver un truc que t'as dicté plus tôt.

- Clique sur l'icône dans la barre de menu
- Sélectionne "Historique"
- Clique sur une transcription pour la copier

L'historique se nettoie automatiquement après 24h pour ne pas encombrer ton Mac.

### Feedback audio
Un petit son te confirme quand l'enregistrement commence et quand la transcription est prête.

### Protection contre les transcriptions fantômes
L'app mesure le niveau audio localement. Si aucune parole n'est détectée, le fichier n'est pas envoyé à l'API et aucun texte n'est collé.

### Reconnaissance personnalisable
Dans les préférences, tu peux choisir le français, l'anglais ou la détection automatique, puis ajouter les noms propres et acronymes que tu utilises souvent.

## Permissions requises

L'app a besoin de ces permissions pour fonctionner :

| Permission | Pourquoi ? |
|------------|-----------|
| **Microphone** | Pour enregistrer ta voix |
| **Accessibilité** | Pour coller le texte automatiquement dans n'importe quelle app |

## Clé API OpenAI

Tu as besoin d'une clé API OpenAI pour utiliser Whisper :

1. Va sur [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
2. Crée un compte ou connecte-toi
3. Crée une nouvelle clé API
4. Copie la clé (elle commence par `sk-...`)
5. Colle-la dans les réglages de Whisper

**Note** : L'utilisation de l'API est payante. Consulte les [tarifs OpenAI](https://openai.com/api/pricing/) pour les prix actuels.

Ta clé API est stockée de façon sécurisée dans le Keychain de macOS (le même endroit où sont stockés tes mots de passe).

## Comment ça fonctionne techniquement ?

1. Quand tu appuies sur **Fn**, l'app commence à enregistrer ton micro
2. L'audio est enregistré en format M4A (16 kHz, mono) et analysé localement pour détecter la voix
3. Si tu n'as pas parlé, l'opération est annulée sans appel réseau
4. Sinon, l'audio est envoyé à l'endpoint de transcription OpenAI avec la langue et ton vocabulaire
5. Le texte validé est collé à l'emplacement initial du curseur
6. Le presse-papiers précédent est restauré, sauf si tu as copié autre chose entre-temps

## Confidentialité

- **Audio** : Envoyé à OpenAI uniquement lorsqu'une voix est détectée, puis supprimé localement
- **Clé API** : Stockée dans le Keychain macOS (chiffré)
- **Historique** : Stocké localement, supprimé après 24h
- **Aucune télémétrie** : L'app n'envoie aucune donnée ailleurs qu'à OpenAI pour la transcription et la validation de clé

## Contribuer

Les PRs sont les bienvenues ! Si tu trouves un bug ou tu as une idée de feature, ouvre une issue.

## Licence

MIT - Fais-en ce que tu veux !
