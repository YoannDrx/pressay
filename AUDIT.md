# Audit technique — socle Pressay 1.0.0

Date : 27 juillet 2026

## État du socle

Pressay 1.0.0 est le nouveau point de départ public de l’application macOS
anciennement distribuée en développement sous le nom Whisper. Le produit cible
macOS 14+, Apple Silicon et Intel, avec un bundle public
`fr.yodev.pressay`.

Le cœur de la version publique 1.0 est volontairement limité :

1. maintenir Fn/Globe — ou un modificateur droit configurable — pour enregistrer ;
2. relâcher pour terminer ;
3. rejeter localement le silence et les pics trop courts ;
4. transcrire avec la clé OpenAI personnelle de l’utilisateur ;
5. valider la réponse contre les échos de prompt connus ;
6. restituer le texte dans l’application initialement ciblée ;
7. conserver facultativement un historique local chiffré.

La branche de développement ajoute désormais la fondation 1.1 et la première
tranche 1.2 : coordinateur de sessions, capture AX sûre, modes contextuels et
transformation de sélection avec aperçu. Les commandes, moteurs locaux, comptes
Pro, intégrations et réunions appartiennent toujours à la roadmap. Aucun bouton
ne doit les présenter comme disponibles avant leur livraison de bout en bout.

## Risque corrigé : transcription fantôme

Un enregistrement silencieux pouvait auparavant renvoyer le prompt de vocabulaire
technique comme transcription. Pressay cumule désormais deux barrières :

- un VAD énergétique adaptatif exécuté avant tout appel réseau ;
- une validation de sortie rejetant une réponse vide ou égale au vocabulaire ou
  au prompt normalisé.

La suite couvre le silence, les enregistrements trop courts, les pics sonores,
la voix au-dessus du bruit ambiant ainsi que les échos de prompt français et
anglais.

## Identité et migration

La migration reconnaît, dans cet ordre :

1. les données Pressay déjà présentes ;
2. `fr.yodev.whisper` ;
3. `com.hyrak.whisper`.

Elle migre les préférences connues, la clé API, la clé d’historique et
`Application Support/Whisper`. Une ancienne entrée Keychain n’est supprimée
qu’après écriture et relecture réussies sous `fr.yodev.pressay`. Le marqueur
Pressay est indépendant des migrations historiques et l’opération peut être
rejouée après une interruption.

Le changement de bundle oblige les installations de développement existantes à
réaccorder Microphone et Accessibilité. Les nouveaux utilisateurs ne sont pas
concernés.

## Distribution

La configuration de release contient :

- Sparkle 2.9.2 épinglé par Swift Package Manager ;
- une clé publique Ed25519 intégrée et aucun profil système envoyé ;
- un workflow de tag `v*` isolé dans l’environnement GitHub `release` ;
- un certificat Developer ID importé dans un Keychain CI temporaire ;
- la fabrication d’un DMG universel, sa signature, sa notarisation et son
  agrafage ;
- les contrôles `codesign`, `lipo`, `stapler`, `spctl`, montage du DMG, SHA-256
  et appcast à URL immuable.

Le certificat local disponible est :
`Developer ID Application: Yoann ANDRIEUX (G9WFV7HNV6)`.

La release ne doit pas être taguée tant que les modifications Pressay ne sont pas
relues, poussées et que le test d’installation sur une session propre n’est pas
prêt. Aucun ancien tag ou DMG Whisper ne doit être publié.

## Vérifications de la baseline 1.0 effectuées

- 19 tests Xcode réussis ;
- `xcodebuild analyze` en Release réussi ;
- archive Release non signée réussie avec `arm64 + x86_64` ;
- validation `v1.0.0`, build `1`, bundle `fr.yodev.pressay` réussie ;
- `pnpm lint` et `pnpm build` réussis sur le portfolio ;
- secrets GitHub `release`, règle de tag `v*` et approbateur vérifiés sans
  exposer leurs valeurs.

La branche 1.1/1.2 porte la suite automatisée à 54 tests Swift et 2 tests
Python. L’archive Release build 12001 signée Developer ID a été validée en
`arm64 + x86_64`, Hardened Runtime est actif, et la fixture AX est elle aussi
universelle. Le feed GitHub Pages est actif et les anciens feeds du portfolio
redirigent vers lui. La notarisation du DMG et surtout la matrice
interapplications restent des gates séparés documentés dans `TESTING.md`.

## Gates encore externes

- recherche formelle de marque INPI/EUIPO ;
- création/vérification de l’App ID explicite Apple ;
- première exécution réelle du workflow de notarisation Pressay ;
- installation du DMG et dictée sur session macOS propre ;
- mise à jour Sparkle entre deux builds signés ;
- capture réelle de l’interface Pressay pour le portfolio ;
- activation du CTA uniquement après disponibilité effective de `v1.2.0`.
