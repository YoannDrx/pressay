# Plan de lancement de Pressay pour Windows

Date : 29 octobre 2026. S'appuie sur la lecture du code des trois dépôts et sur une recherche web sourcée (liens en annexe).
Ce plan ne modifie rien par lui-même : chaque lot deviendra une PR qui suit le modèle de PR du dépôt.

---

## 0. Résumé

- **Faisable, et moins cher qu'un portage de zéro.** Le code Windows hérité de Handy est toujours là : raccourcis par hook bas niveau, collage fiable, overlay, tray, accès au micro, étapes de CI Windows. Il est simplement endormi depuis le 17/08/2026, retiré de la CI et de la configuration de release.
- **Le vrai travail porte sur ce que Pressay a ajouté après le fork.** Tout cela est réservé à macOS et renvoie une erreur ailleurs : stockage des secrets, historique chiffré, session cloud, synchro, profils par app, correction vocale, StoreKit.
- **Estimation pour une V1 vendable** (dictée, compte, Pro par Stripe, x64 et ARM64) : **33 à 51 jours-homme**. Détail : app 28 à 44, cloud 2 à 3, site 3 à 4. Avec un seul développeur, compter **9 à 12 semaines calendaires**.
- **Chemin critique : la signature de code**, jusqu'à 20 jours ouvrés de validation chez Microsoft. Elle exige une **société** : un particulier français n'est pas éligible, et pour une micro-entreprise ce n'est pas clair. À lancer la première semaine, en parallèle du code.
- **Cible :** Windows 11 et Windows 10 22H2, en x64 et ARM64 (Snapdragon X). Wispr Flow ne fonctionne pas sur ARM, ce qui fait un argument de plus.
- **Dès cette semaine, sans attendre l'app :** ajouter sur le site un bouton « Windows : être prévenu » (lot W0). Il mesure la demande et constitue la liste des bêta-testeurs.

---

## 1. Décisions à prendre avant de coder

| #   | Décision                      | Recommandation                                                                                                                                             | Pourquoi                                                                                                                                                                                                              |
| --- | ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1  | Structure juridique qui signe | **SASU ou EURL** si elle existe, sinon tenter la micro-entreprise avec SIREN, n° de TVA et e-mail `@press-say.app`                                         | Azure Artifact Signing n'accepte que les organisations de l'UE. Le nom affiché par Windows sera la dénomination légale                                                                                                |
| D2  | Méthode de signature          | **Azure Artifact Signing** (environ 10 $ par mois). En secours, **Certum Code Signing in the Cloud** (à partir de 189 €)                                   | Un certificat EV ne contourne plus SmartScreen depuis 2024 : inutile de payer plus                                                                                                                                    |
| D3  | Architectures                 | **x64 et ARM64 dans la même release**                                                                                                                      | Les PC Snapdragon X se vendent en volume, et Wispr Flow ne les prend pas en charge                                                                                                                                    |
| D4  | Versions de Windows           | Windows 11, et Windows 10 22H2 en « meilleur effort »                                                                                                      | Windows 10 n'est plus maintenu par Microsoft hors programme ESU                                                                                                                                                       |
| D5  | Raccourci par défaut          | **Maintenir Ctrl+Win**. Alternatives proposées à l'onboarding : Ctrl+Espace, Verr. Maj, bouton de souris 4 ou 5                                            | La touche `fn` est invisible pour Windows. Ctrl+Espace entre en conflit avec VS Code, JetBrains, Excel et les méthodes de saisie asiatiques. **Alt droit est exclu**, car c'est AltGr sur un clavier AZERTY (@, #, €) |
| D6  | Moteur par défaut             | **Parakeet V3 sur CPU**, et Whisper sur GPU Vulkan en option (x64) avec retour automatique au CPU                                                          | Le CPU marche partout, ARM compris. Les pilotes Vulkan sont la première cause de plantage chez Handy sous Windows                                                                                                     |
| D7  | Offre Pro sur Windows         | **Même prix, même compte, mêmes 3 appareils partagés entre Mac et PC**. Page de tarifs avec une matrice des fonctions par système                          | Apple Intelligence n'existe pas sur Windows ; la correction vocale arrive au lot A6                                                                                                                                   |
| D8  | Canal de vente                | **Stripe par le site** ; Microsoft Store en phase 2, en gardant Stripe (0 % de commission, autorisé pour les apps non-jeux)                                | Aucun travail de facturation spécifique à Windows                                                                                                                                                                     |
| D9  | Format d'installation         | **NSIS seul, installé pour l'utilisateur courant** (pas de demande administrateur). Pas de MSI                                                             | Mises à jour silencieuses et sans UAC. Le MSI ne servira que si un client entreprise le demande                                                                                                                       |
| D10 | Nom des fichiers              | `Pressay_<version>_x64-setup.exe` et `Pressay_<version>_arm64-setup.exe`, plus `Pressay-windows-x64.exe` et `Pressay-windows-arm64.exe` comme noms stables | Le site sert les noms stables, l'updater les noms versionnés                                                                                                                                                          |

---

## 2. Prérequis côté Mac, à faire en premier

Ces lots servent aux deux plateformes et débloquent le reste.

**P1. Mises à jour automatiques** (voir l'audit, C1). Aujourd'hui l'adresse répond 404.

- **Remplacement :** l'adresse dans `src-tauri/tauri.conf.json:100` devient `https://press-say.app/updates/{{target}}/{{arch}}/{{current_version}}?channel=beta`.
- **Côté site :** une route `app/updates/[target]/[arch]/[version]/route.ts` lit la dernière release du canal sur GitHub (pré-releases comprises pour le canal bêta). Elle répond **204** si l'app est à jour, sinon le JSON Tauri d'une seule plateforme.
- **Côté release :** chaque release publie `latest.json` (avec `darwin-aarch64`, `windows-x86_64` et `windows-aarch64`), les fichiers `.sig` et les artefacts de mise à jour.
- **Script :** `scripts/check-updater-manifest.ts:22` est étendu aux clés Windows.
- **Terminé quand :** une beta.4 modifiée en local voit apparaître une beta.5 de test.

**P2. Merger #110 puis #109, et publier la beta.5 Mac** avec le nouvel updater. Prévenir les testeurs qu'il faut la télécharger une dernière fois à la main.

**P3. Comptage des téléchargements** (voir l'audit, C2) : la route `POST /v1/downloads` côté cloud, avec un champ `platform` prévu d'emblée.

---

## 3. Lot W0 : liste d'attente Windows sur le site (1 jour, cette semaine)

**Objectif :** mesurer la demande et recruter les bêta-testeurs sans rien promettre de daté.

1. **Cloud :**
   - Migration `0020_platform_waitlist.sql` : table `platform_waitlist (id, email_normalized unique, platform text check (platform in ('windows')), locale, source, consent_at, created_at)`.
   - Route `POST /v1/waitlist`, validée par zod, limitée à 5 requêtes par minute et par IP, avec réponse identique que l'e-mail soit nouveau ou non, pour ne pas révéler qui est inscrit.
2. **Site :**
   - Sur `/[locale]/download` et dans le bloc héros de l'accueil, la ligne « macOS 14+ · Apple Silicon » est complétée par « Windows : bientôt. Être prévenu ».
   - Formulaire e-mail avec consentement explicite (« Je veux recevoir un seul e-mail au lancement de Windows ») et lien vers la politique de confidentialité, mise à jour en conséquence.
3. **Admin :** compteur dans `/admin`, plus export CSV derrière le step-up TOTP.
4. **Terminé quand :** une inscription apparaît dans l'admin et un doublon renvoie la même réponse.

---

## 4. Lots de l'app (dépôt `Pressay`)

Chaque lot correspond à une PR. Ordre conseillé : A1 → A2 → (A3, A4, A5 en parallèle) → A6 → A7 → A8.

### A1. Recompiler Windows dans la CI (3 à 5 j)

1. Ajouter dans `.github/workflows/test.yml` un job `windows-latest` qui lance `cargo clippy --features updater -- -D warnings` et `cargo test`.
2. Rétablir dans `build.yml` (étapes Windows déjà présentes, lignes 72, 173-190 et 279-470) les cibles `x86_64-pc-windows-msvc` et `aarch64-pc-windows-msvc` :
   - x64 sur `windows-latest`, avec le SDK Vulkan et SPIRV-Headers ;
   - ARM64 sur `windows-11-arm`, avec clang-cl et `-DGGML_NATIVE=OFF -DGGML_OPENMP=OFF`.
3. Remplacer `handy.exe` par `pressay.exe` (`build.yml:928-941`) et `usr/bin/handy` par `usr/bin/pressay` (`:768`).
4. Corriger les erreurs de compilation `cfg(windows)` accumulées depuis août. Repères : `tray.rs` (+571 lignes), `paste_tx/windows.rs`, `overlay.rs:162`.
5. **Moteur, par cible dans `Cargo.toml`** :
   - x64 : `transcribe-cpp` avec `vulkan` et des backends dynamiques ;
   - ARM64 : CPU en lien statique ;
   - Parakeet par `transcribe-rs` et ONNX Runtime CPU sur les deux.
6. **Terminé quand :** la CI est verte sur les 2 cibles Windows, et `pressay.exe --list-devices` liste les micros sur un runner.

### A2. Secrets Windows (3 à 5 j), bloquant

**Constat :** `src-tauri/src/secrets.rs:386-500` renvoie une erreur sur tout système autre que macOS. L'historique, le compte, la clé LLM, la synchro et le Pro sont donc cassés.

1. Ajouter le store `keyring-core` pour Windows Credential Manager, pour les petites valeurs : clé de chiffrement de l'historique, clé LLM.
2. **Limite :** une valeur Credential Manager ne peut pas dépasser 2 560 octets, alors que les jetons OAuth vont jusqu'à 16 384 caractères (`secrets.rs:44`). Les gros contenus vont donc dans un fichier `%LOCALAPPDATA%\Pressay\secure\<nom>.bin` chiffré par **DPAPI** (`CryptProtectData`, portée utilisateur, avec un sel propre à l'app).
3. Écrire les tests : aller-retour, valeur de 16 Ko, suppression, utilisateur différent (illisible).
4. **Terminé quand :** connexion, historique chiffré et clé LLM survivent à un redémarrage sous Windows.

### A3. Socle de dictée (5 à 8 j)

1. **Raccourci par défaut** à Ctrl+Win, en maintien, dans `settings.rs:944`.
   - Vérifier que handy-keys masque le menu Démarrer au relâchement (`platform/windows/listener.rs:568-575` dans la crate).
   - Ajouter Verr. Maj et les boutons de souris 4 et 5 aux choix possibles.
   - Interdire Alt droit sur les dispositions qui ont AltGr.
2. **Onboarding :**
   - masquer `AccessibilityOnboarding.tsx` sous Windows ;
   - afficher l'écran micro Windows (Paramètres › Confidentialité › Microphone, contrôle déjà présent dans `commands/audio.rs:11,61,79`) ;
   - ajouter une étape « Choisis ton raccourci » qui fait tester le raccourci.
3. **Diagnostic :** `commands/mod.rs:58-116` renvoie aujourd'hui « non pris en charge » hors Mac. Lire la RAM par `GlobalMemoryStatusEx`, le disque par `GetDiskFreeSpaceExW`, et la version de Windows et l'architecture.
4. **Collage :**
   - Valider `paste_tx/windows.rs` (rendu différé et accusé de lecture).
   - Ajouter l'exclusion de l'historique Win+V et de la synchro cloud du presse-papiers, avec les formats `ExcludeClipboardContentFromMonitorProcessing` et `CanIncludeInClipboardHistory = 0`.
   - Proposer une méthode par app : Ctrl+V par défaut, Ctrl+Maj+V pour les terminaux, saisie directe en secours.
5. **Apps lancées en administrateur** (remplace `secure_input.rs` sur Windows) : si la fenêtre au premier plan a un niveau d'intégrité supérieur, ne pas coller dans le vide. Laisser le texte dans le presse-papiers et afficher dans l'overlay « Texte copié : colle avec Ctrl+V (app lancée en administrateur) ».
6. **Démarrage avec Windows** (clé Run) : déjà fourni par le plugin Tauri (`autostart.rs`), à tester.
7. **Textes :** 24 « Mac », 16 « App Store » et 13 « macOS » dans les traductions sont à rendre neutres ou conditionnels. Le modèle NSIS dit encore « Handy » (`installer.nsi:1,220,591`).
8. **Terminé quand :** la grille de tests de la section 7 passe sur 3 machines.

### A4. GPU et performance (2 à 3 j, compris dans A3 et A7)

1. Choix automatique : Vulkan si un GPU dédié ou un iGPU récent est présent, CPU sinon. Sur une machine ARM, CPU toujours (déjà géré dans `utils.rs:29-60`).
2. Retour au CPU automatique si Vulkan échoue au chargement ou renvoie `ErrorDeviceLost`, avec mémorisation du choix.
3. Réglage « Accélération GPU : Auto / Désactivée ».
4. Message d'aide si le pilote graphique est trop ancien.
5. Mesures cibles sur un portable milieu de gamme, avec Parakeet sur CPU :
   - moins de 1,5 s entre le relâchement et le collage pour 10 s de parole, modèle chargé ;
   - moins de 5 s au rechargement à froid.

### A5. Compte et cloud côté client (1 à 2 j)

1. `cloud.rs:1233` : remplacer `"Pressay Mac"` par `"Pressay Windows"` ou par le nom de l'ordinateur.
2. Envoyer `platform: "windows"` au bootstrap. **Déployer d'abord le lot C1 du cloud**, sinon le serveur refuse la requête (schéma strict, erreur 422).
3. `distribution.rs` :
   - une build Windows `updater` est classée `Direct` ;
   - masquer le lien « abonnements Apple » hors Mac ;
   - ajouter le bouton « Passer Pro » qui ouvre `press-say.app/pricing` (et activer `stripe-purchases`, ou le remplacer par ce simple lien).
4. Lien profond `pressay://oauth/callback` : enregistré par l'installeur NSIS (le plugin deep-link de Tauri le fait). Le tester avec Chrome, Edge et Firefox.

### A6. Parité Pro (5 à 8 j)

1. **Profils par app** (`productivity.rs:436-463`, qui renvoie `None` hors Mac) : identifier l'app par `GetForegroundWindow`, puis `GetWindowThreadProcessId` et `QueryFullProcessImageNameW` (par exemple `winword.exe`).
   - Le modèle de données des profils et de la synchro gagne un champ `platform`, et l'identifiant n'a plus la forme d'un bundle id.
2. **Correction vocale du texte sélectionné** (`selection_context.rs`) : lire la sélection par UI Automation (`TextPattern.GetSelection`), avec un repli par Ctrl+C simulé qui sauvegarde puis restaure le presse-papiers.
3. **Apple Intelligence** : déjà exclu de la compilation. Le retirer de la matrice des tarifs pour Windows.
4. **Si le délai presse :** livrer la V1 sans la correction vocale (marquée « bientôt »), ce qui retire 4 à 6 jours.

### A7. Installation, signature et mise à jour (3 à 5 j)

1. **Fichier `src-tauri/tauri.windows.conf.json`**, à compléter :
   ```json
   {
     "bundle": {
       "targets": ["nsis"],
       "windows": {
         "signCommand": "artifact-signing-cli -e https://weu.codesigning.azure.net -a <compte> -c <profil> -d Pressay %1",
         "webviewInstallMode": { "type": "embedBootstrapper" },
         "nsis": {
           "installMode": "currentUser",
           "languages": ["French", "English"],
           "displayLanguageSelector": false
         }
       }
     }
   }
   ```
2. **Secrets GitHub** `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` et `AZURE_TENANT_ID` (environnement `release`, protégé). Installer `cargo install artifact-signing-cli` dans le job.
3. **Tout signer :** `pressay.exe`, l'installeur et les DLL chargées (backends ggml, ONNX Runtime).
4. **Updater :** avec `createUpdaterArtifacts: true` (déjà le cas), `tauri-action` fusionne les plateformes dans `latest.json`. Mettre `updaterJsonPreferNsis: true`, sinon la clé `windows-x86_64` pointe vers un MSI qui n'existe pas.
5. **Job de vérification** sur `windows-latest` après la construction :
   - `signtool verify /pa /v` sur tous les fichiers signés ;
   - installation silencieuse `/S` ;
   - lancement de `pressay.exe --list-devices`, puis désinstallation silencieuse.
6. Publier `Pressay-windows-x64.exe.sha256` et `Pressay-windows-arm64.exe.sha256`.
7. **Faux positifs Defender :** soumettre chaque release au portail Microsoft Security Intelligence (« Submit a file », catégorie « Software developer »). Handy en a eu un en août 2026.

### A8. Documentation et support (1 j)

Ajouter une section Windows à `BUILD.md`, `README.md` et `docs/RELEASES.md`, plus une page support « Pressay ne colle pas » couvrant les apps admin, les terminaux, l'antivirus et le GPU.

---

## 5. Lots du cloud (dépôt `pressay-cloud`, 2 à 3 j)

À déployer **avant** la première build Windows.

| #   | Changement                                                                                                                                                                                    | Fichiers                                                                                                                |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| C1  | Migration `0021_device_platform.sql` : remplacer `CHECK (platform='macos')` par `CHECK (platform IN ('macos','windows'))`, en gardant la valeur par défaut `'macos'` pour les anciens clients | `migrations/0002_control_plane.sql:16` (à remplacer par la nouvelle migration)                                          |
| C2  | Nouvelle version de `bootstrap_pressay_account(..., p_platform text DEFAULT 'macos')` qui enregistre la plateforme à l'insertion et à la mise à jour ; supprimer l'ancienne signature         | `migrations/0015:5-108`                                                                                                 |
| C3  | Schéma zod : `platform: z.enum(['macos','windows']).default('macos')`                                                                                                                         | `src/contracts/account.ts:6-19`                                                                                         |
| C4  | Exposer `platform` dans la liste des appareils, `/me` et l'export                                                                                                                             | `src/contracts/account.ts:30-38`, `src/services/accounts.ts:232-263`, `src/services/data-export.ts:40-51`               |
| C5  | Lire `plan_limit.cloud_devices` au lieu du 3 codé en dur ; garder 3 places partagées entre Mac et PC                                                                                          | `migrations/0015:52-58`, `src/contracts/account.ts:63`, `src/routes/accounts.ts:102`, `src/services/accounts.ts:92,261` |
| C6  | Portes de lancement Windows dans `/admin` : signature Authenticode, SmartScreen, installeur, mise à jour, téléchargement                                                                      | `migrations/0017:109,121`                                                                                               |
| C7  | Client OAuth : renommer « macOS » en « Pressay desktop » ; le redirect `pressay://oauth/callback` reste le même                                                                               | `src/env.ts:29-33`, `pressay-web/lib/auth.ts:23-24,228`                                                                 |
| C8  | `POST /v1/downloads` avec `platform` et `assetType ∈ {dmg, exe}` (prérequis P3)                                                                                                               | nouveau `src/routes/downloads.ts`                                                                                       |

Rien ne change dans Stripe : les prix, Checkout et le portail ne dépendent pas du système.

---

## 6. Lots du site (dépôt `pressay-web`, 3 à 4 j)

### S1. Releases par plateforme

`lib/release.ts:30-60` n'accepte aujourd'hui qu'une release contenant `Pressay.dmg`. Elle doit renvoyer :

```ts
type PublicRelease = {
  tag: string;
  prerelease: boolean;
  publishedAt: string;
  assets: {
    macos?: { url: string; sha256URL: string; size: number };
    windowsX64?: { url: string; sha256URL: string; size: number };
    windowsArm64?: { url: string; sha256URL: string; size: number };
  };
};
```

- Pour chaque plateforme, prendre la dernière release qui **contient** son fichier, puisqu'une release peut ne contenir qu'un seul système.
- Appeler l'API GitHub avec un jeton en lecture seule (`GITHUB_RELEASES_TOKEN`) et `revalidate: 600`.
- Mettre à jour `fallbackTag`.

### S2. Routes de téléchargement

- Nouvelle route `app/download/[platform]/route.ts`, avec `platform ∈ {macos, windows}` et un `?arch=x64|arm64` facultatif.
- **`/download/pressay` reste un alias de `macos`** pour ne casser ni les liens existants ni le JSON-LD.
- Windows sans `arch` : ARM64 si `Sec-CH-UA-Arch` vaut `arm` (en-tête demandé par `Accept-CH: Sec-CH-UA-Arch, Sec-CH-UA-Platform`), x64 sinon.
- Envoyer le comptage (C8) avec `platform` et `assetType`.
- Interdire ces routes dans `robots.ts`.

### S3. Page `/[locale]/download`

Fichier : `components/download-page.tsx`.

1. **Détection du système côté client** (la page reste statique, donc cachable plus tard) :
   - `navigator.userAgentData?.platform`, avec `navigator.userAgent` en secours ;
   - présélection de l'onglet macOS ou Windows ;
   - **jamais de téléchargement automatique.**
2. **Deux onglets.**
   - **macOS :** contenu actuel.
   - **Windows :**
     - bouton « Télécharger pour Windows (x64) » et lien secondaire « PC ARM (Snapdragon) » ;
     - prérequis « Windows 10 22H2 ou Windows 11 », taille du fichier, lien SHA-256 ;
     - 4 étapes : ouvrir `Pressay-windows-x64.exe` ; si Windows affiche « Windows a protégé votre ordinateur », cliquer « Informations complémentaires » puis « Exécuter quand même » (la section disparaîtra quand la réputation SmartScreen sera établie) ; autoriser le micro ; choisir son raccourci.
3. **Tant que Windows n'est pas publié :** l'onglet Windows affiche le formulaire de liste d'attente (W0).
4. Les textes FR et EN vont dans `lib/content.ts`, comme aujourd'hui.

### S4. Accueil, tarifs et SEO

1. **Bloc héros** (`components/landing-page.tsx:121-134`) :
   - bouton principal adapté au système détecté (« ⌘ Télécharger pour macOS » ou « Télécharger pour Windows ») ;
   - lien secondaire « Aussi sur Windows » ou « Aussi sur Mac » ;
   - mention « macOS 14+ · Windows 10/11 · Free sans compte ».
2. **En-tête et menu mobile** (`components/site-header.tsx:52-53,73-74`) : « Télécharger » mène à `/download`, qui choisit l'onglet.
3. **FAQ** (`landing-page.tsx:362-400`) : ajouter « Pressay marche-t-il sur Windows ? », et « Mon abonnement couvre-t-il Mac et PC ? » (réponse : oui, 3 appareils au total).
4. **JSON-LD** (`landing-page.tsx:74-88`) :
   - `operatingSystem: "macOS 14 or later, Windows 10, Windows 11"` ;
   - `processorRequirements: "Apple Silicon; x64 or ARM64"` ;
   - ajout de `softwareVersion` ;
   - `downloadUrl: /download`.
5. **Tarifs** (`lib/content.ts:60-69`, `components/pricing.tsx`) : matrice des fonctions avec une colonne Mac et une colonne Windows (Apple Intelligence : Mac uniquement ; correction vocale : « bientôt » si A6 est reporté).
6. **Textes « Mac » à rendre neutres** :
   - `lib/content.ts:8,11,29,32`, `app/layout.tsx:12`, `lib/page-metadata.ts:18,23` ;
   - `app/opengraph-image.tsx:3,91,102`, `components/site-footer.tsx:38` ;
   - `components/account-section.tsx:60-93,266,321`, `lib/account-view.ts:132` ;
   - `components/account-deletion.tsx:182-187`, `components/account-security.tsx:451-452`, `components/oauth-consent.tsx:50-51` ;
   - `app/admin/users/page.tsx:54` ;
   - pages légales `app/[locale]/[legal]/page.tsx:131-222` : ajouter Windows, DPAPI et Credential Manager dans la politique de confidentialité.
7. **Compte :** `/account/devices` affiche l'icône du système de chaque appareil (C4).
8. **Images de partage :** ajouter une variante Mac et Windows.

### S5. Vérifications du site

- Tests unitaires de la détection du système : Windows x64, Windows ARM, macOS, Linux (onglet Mac, avec la mention « non pris en charge »), iPhone et Android (pas de bouton, « Envoie-toi le lien »).
- Playwright : `/fr/download` sous un user-agent Windows présélectionne l'onglet Windows, et `/download/windows` répond 307 vers un fichier `.exe` signé.

---

## 7. Grille de tests avant la bêta publique

**Machines minimales :**

1. Portable Intel ou AMD récent sous Windows 11, avec iGPU.
2. PC avec GPU NVIDIA.
3. PC Snapdragon X (ARM64).
4. Windows 10 22H2.

Une machine virtuelle Windows 11 ARM sur Mac (Parallels ou UTM) couvre une partie du point 3, mais pas les performances.

| Domaine        | Cas à vérifier                                                                                                                                                                   |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Installation   | Première installation sans droits administrateur ; avertissement SmartScreen ; WebView2 absent (Windows 10) ; mise à jour par l'updater ; désinstallation propre                 |
| Raccourci      | Ctrl+Win maintenu, sans ouverture du menu Démarrer ; clavier AZERTY et AltGr intact ; méthode de saisie japonaise active ; VS Code ouvert                                        |
| Collage        | Word, Outlook, Chrome, Edge, Slack, Teams, VS Code, Windows Terminal (Ctrl+Maj+V), Notepad, Excel (cellule), champ mot de passe (refusé), app lancée en administrateur (message) |
| Presse-papiers | Contenu d'origine restauré ; dictée absente de l'historique Win+V ; Ditto ou ClipboardFusion non pollués                                                                         |
| Moteur         | Parakeet en français sur CPU ; Whisper sur Vulkan ; plantage Vulkan suivi du retour au CPU ; latence (cible de A4)                                                               |
| Compte         | Connexion OAuth avec Chrome, Edge et Firefox ; retour par `pressay://` ; droits Pro ; 4e appareil refusé avec message clair                                                      |
| Pro            | Profils par app (`winword.exe`) ; correction vocale ; synchro chiffrée Mac ↔ PC                                                                                                  |
| Sécurité       | `signtool verify` sur tous les fichiers ; aucune transcription dans les logs (`%APPDATA%\fr.yodev.pressay\logs`) ; secrets illisibles depuis une autre session Windows           |
| Antivirus      | Defender et Smart App Control (Windows 11) ; un antivirus tiers courant                                                                                                          |

---

## 8. Calendrier indicatif (1 développeur)

| Semaine | Code                                                                              | En parallèle                                                            |
| ------- | --------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| S1      | P1, P2, P3 ; W0 en production                                                     | **Demande Azure Artifact Signing** (D1, D2) ; achat d'un PC ARM de test |
| S2      | A1 (CI Windows verte)                                                             | Validation Azure en cours                                               |
| S3      | A2 (secrets) ; C1 à C8 (cloud)                                                    | —                                                                       |
| S4-S5   | A3 et A4 (socle de dictée, GPU)                                                   | Recrutement de 20 à 50 testeurs dans la liste d'attente                 |
| S6      | A5, puis A7 (installation et signature)                                           | Validation Azure obtenue (au plus tard)                                 |
| S7-S8   | A6 (parité Pro) ; S1 à S4 du site                                                 | **Bêta privée** avec la liste d'attente                                 |
| S9-S10  | Corrections, grille de tests complète, A8                                         | Soumissions à Defender                                                  |
| S11     | Bêta publique : onglet Windows actif sur le site                                  | Collecte de la réputation SmartScreen                                   |
| S12+    | Microsoft Store (même installeur, WebView2 hors ligne, Stripe conservé) et winget | —                                                                       |

---

## 9. Budget

| Poste                                        | Coût                                           |
| -------------------------------------------- | ---------------------------------------------- |
| Azure Artifact Signing (Basic)               | environ 10 $ par mois, soit 120 $ par an       |
| Certum Cloud (si Azure refuse)               | à partir de 189 €                              |
| Compte Microsoft Store « Company » (phase 2) | environ 99 $ une fois (à vérifier)             |
| PC Snapdragon X de test                      | 800 à 1 200 € (ou location)                    |
| Runners GitHub Windows                       | gratuits si le dépôt est public (c'est le cas) |

---

## 10. Risques et parades

| Risque                                            | Parade                                                                                                                                   |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Azure refuse la micro-entreprise                  | Basculer sur Certum Cloud OV la même semaine ; ne pas attendre pour coder                                                                |
| SmartScreen avertit pendant des semaines          | Étape d'installation expliquée sur le site ; bêta privée d'abord ; même identité de signature d'une version à l'autre ; Store en phase 2 |
| Faux positif Defender (hook clavier et injection) | Signature de tous les fichiers ; soumission à Microsoft à chaque release ; aucune technique d'obfuscation                                |
| Plantages Vulkan selon les pilotes                | CPU par défaut, retour automatique au CPU, réglage pour désactiver le GPU                                                                |
| Collage raté vers les apps administrateur         | Détection et message clair, sans échec silencieux                                                                                        |
| Code Windows trop dégradé depuis août             | Le lot A1 sert de test : s'il dépasse 5 jours, réestimer avant de continuer                                                              |
| Fonctions Pro incomplètes au lancement            | Matrice honnête sur la page des tarifs ; correction vocale marquée « bientôt »                                                           |

---

## Annexe : sources

- Options de signature Microsoft : https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options
- Artifact Signing, démarrage et éligibilité (mise à jour du 08/10/2026) : https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart
- Artifact Signing, FAQ : https://learn.microsoft.com/en-us/azure/artifact-signing/faq
- Réputation SmartScreen : https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation
- Tauri, signature Windows : https://v2.tauri.app/distribute/sign/windows/
- Tauri, installeur Windows : https://v2.tauri.app/distribute/windows-installer/
- Tauri, updater : https://v2.tauri.app/plugin/updater/
- tauri-action (`updaterJsonPreferNsis`) : https://github.com/tauri-apps/tauri-action
- Politiques du Microsoft Store (10.8, 10.14) : https://learn.microsoft.com/en-us/windows/apps/publish/store-policies
- Inscription gratuite pour les développeurs individuels : https://blogs.windows.com/windowsdeveloper/2025/09/10/free-developer-registration-for-individual-developers-on-microsoft-store/
- Hook clavier bas niveau : https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc
- SendInput et UIPI : https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput
- Formats du presse-papiers (exclusion de l'historique) : https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-formats
- whisper.cpp et ses backends : https://github.com/ggml-org/whisper.cpp
- Handy, faux positif Defender : https://github.com/cjpais/Handy/issues/1891
- Certum Cloud : https://shop.certum.eu/standard-code-signing-in-the-cloud.html
- Part de marché des systèmes de bureau : https://gs.statcounter.com/os-market-share/desktop/worldwide
- Raccourcis de Wispr Flow : https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts
