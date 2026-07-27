# Distribution macOS

Pressay est distribué en DMG universel `arm64 + x86_64`, compatible macOS 14+.
La configuration Release active le Hardened Runtime. Le sandbox reste désactivé :
l'application doit observer un raccourci global, réactiver l'application cible et
publier un événement clavier pour y coller le texte.

Le bundle public est `fr.yodev.pressay`. La version visible et le numéro de build
proviennent uniquement de `MARKETING_VERSION` et `CURRENT_PROJECT_VERSION` dans
le projet Xcode. La prochaine série publique est `1.2.0` : builds `12001–12089`
pour les bêtas, `12090–12098` pour les RC et `12099` pour la stable.

## Préparer la signature Apple

La publication exige un abonnement Apple Developer actif et un certificat
`Developer ID Application`. Sur un compte individuel, Gatekeeper affiche le nom
légal du titulaire, même si l'application est présentée « par Yodev ».

Le Mac ou le runner doit disposer des valeurs suivantes :

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Yoann Andrieux (TEAMID)"
export APPLE_TEAM_ID="TEAMID"
export APPLE_ID="adresse@example.com"
export APPLE_APP_SPECIFIC_PASSWORD="mot-de-passe-spécifique-à-l-app"
export SPARKLE_PRIVATE_KEY="clé-privée-exportée-par-generate_keys"
export SPARKLE_GENERATE_APPCAST="/chemin/vers/Sparkle/bin/generate_appcast"
export RELEASE_TAG="v1.2.0-beta.1"
```

La clé privée Sparkle ne doit jamais être ajoutée au dépôt. La clé publique
Ed25519 intégrée à l'application est distincte du certificat Apple.

## Fabriquer une release locale

```bash
./scripts/validate-release.sh
./scripts/notarize.sh
```

Le script :

1. vérifie le tag, la version, le build numérique et le bundle ID ;
2. archive et exporte l'app avec Developer ID, Hardened Runtime et timestamp ;
3. contrôle l'app, Sparkle, les entitlements et les architectures ;
4. crée un DMG UDZO avec `Pressay.app` et un lien vers `/Applications` ;
5. signe puis soumet directement le DMG à `notarytool` ;
6. agrafe le ticket et évalue le DMG et l'app montée avec Gatekeeper ;
7. génère `Pressay.dmg.sha256` et un appcast signé EdDSA.

Les trois assets publiables sont écrits dans `build/release/` :

- `Pressay.dmg`
- `Pressay.dmg.sha256`
- `appcast.xml`

En cas d'échec Apple, `notary-result.json` et, si possible,
`notary-log.json` sont conservés dans le même dossier.

## GitHub Actions

Le workflow `.github/workflows/release.yml` s'exécute uniquement lors du push
d'un tag `v*`. Le premier job teste, analyse et valide la version sans accéder
aux secrets. Le job de publication utilise l'environnement GitHub `release`,
importe le certificat dans un Keychain temporaire, fabrique les assets et crée
la GitHub Release.

Configurer l'environnement `release` pour n'autoriser que les tags protégés et
exiger une approbation. Y ajouter :

### Secrets

- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `SPARKLE_PRIVATE_KEY`

### Variable

- `DEVELOPER_ID_APPLICATION`

Exemple d'encodage du certificat :

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Les secrets ne sont jamais disponibles dans le workflow de pull request. Le job
final est le seul à recevoir `contents: write`, et le verrou de concurrence
interdit deux publications simultanées.

## URLs et appcast

Chaque appcast référence l'asset immuable du tag, par exemple :

```text
https://github.com/YoannDrx/pressay/releases/download/v1.2.0-beta.1/Pressay.dmg
```

L’app utilise le feed canonique GitHub Pages :

```text
https://yoanndrx.github.io/pressay/appcast.xml
```

Le portfolio doit conserver deux redirections stables :

```text
https://www.yoann-andrieux.fr/download/pressay
https://www.yoann-andrieux.fr/download/pressay/appcast.xml
```

La première pointe vers le dernier `Pressay.dmg`, la seconde vers le feed Pages
canonique. L'appcast est utilisé pour découvrir une version stable ; le DMG
d'une version reste toujours téléchargé depuis l'URL de son tag.

## Validation avant activation du CTA

Sur une session macOS propre :

1. télécharger depuis le portfolio et vérifier la somme SHA-256 ;
2. ouvrir le DMG sans contournement Gatekeeper ;
3. glisser Pressay dans Applications ;
4. accorder Microphone et Accessibilité ;
5. configurer une clé API et effectuer une dictée ;
6. redémarrer l'app et contrôler réglages et historique ;
7. tester une mise à jour Sparkle entre deux builds signés.

Le CTA du portfolio doit rester désactivé jusqu'à la publication effective de
`v1.2.0`.
