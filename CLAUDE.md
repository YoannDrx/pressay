# Whisper

## Recherche de Code

Ce projet utilise **grepai** pour la recherche sémantique de code.

### Commandes

```bash
# Recherche sémantique
~/.local/bin/grepai search "ta question en langage naturel"

# Tracer les appels
~/.local/bin/grepai trace callers "nomFonction"
~/.local/bin/grepai trace callees "nomFonction"

# Status de l'index
~/.local/bin/grepai status
```

### Exemples de recherches

```bash
~/.local/bin/grepai search "Comment fonctionne la transcription audio ?"
~/.local/bin/grepai search "Où est configuré le modèle Whisper ?"
~/.local/bin/grepai search "Comment sont traités les fichiers audio ?"
```
