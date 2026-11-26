# Audit produit et préparation à la production — 6 septembre 2026

> État historique du 6 septembre. Voir le [suivi des corrections avant vente du
> 7 septembre](PRE_SALE_REMEDIATION_2026-09-07.md) pour les corrections et les
> vérifications du backend, du site et de Stripe effectuées ensuite.

## Décision

**NO-GO pour une commercialisation générale et une soumission Mac App Store.**
Le dépôt contient une application substantielle, une dictée locale opérationnelle
sur des essais ciblés et des mécanismes de sécurité utiles. Il reste des défauts
et surtout des preuves natives, commerciales et opérationnelles manquantes.
« 100 % fonctionnel » ne peut pas être déduit d'une compilation ou d'un nombre de tests.

Cet audit couvre le dépôt desktop, ses workflows, ses ressources, ses contrats
clients Cloud/BYOK, ses configurations de distribution et ses documents produit.
Il part du commit `3e755f0` (`2.0.0-beta.2`) et comprend les corrections de la branche
`codex/production-readiness-audit`. Les dépôts privés Cloud et facturation, les
comptes fournisseurs, App Store Connect et les contrats commerciaux ne sont pas
audités ici. Les affirmations des audits d'août concernant ces systèmes ne sont
pas reprises comme des preuves actuelles.

Machine disponible : Apple M2, 16 Go, macOS 26.3.1. L'app installée est une
`2.0.0-beta.3` signée Developer ID avec ticket de notarisation staplé. Elle diffère
du code audité : sa signature ne certifie ni cette branche ni la variante Store.

## Défauts confirmés et corrections

| Priorité | Problème et conséquence                                                                                                                                                                                                 | Correction / preuve                                                                                                                                                                                                                                                       |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P1       | Plusieurs requêtes compte/sync/Cloud pouvaient utiliser le même refresh token expiré : échec avec rotation à usage unique, session instable.                                                                            | Sérialisation de lecture/renouvellement/persistance, partagée avec échange OAuth et nettoyage de déconnexion. Test de huit requêtes concurrentes et test d'échec réseau dans `src-tauri/src/cloud.rs`.                                                                    |
| P1       | La lecture OAuth réimportait l'ancien trousseau lorsque le nouveau était absent, y compris après une déconnexion explicite.                                                                                             | Marqueur durable interdisant cette réimportation après déconnexion, écrit avant suppression dans `src-tauri/src/secrets.rs`. Validation native du trousseau signé encore nécessaire.                                                                                      |
| P1       | Une sync réécrivait tous les réglages chargés avant l'attente réseau ; elle pouvait annuler une modification locale, voire réintroduire un ancien compte. Deux sync pouvaient aussi concurrencer le fichier de curseur. | Relecture après chaque réponse, contrôle compte/appareil, persistance par page appliquée et sérialisation des sync dans `src-tauri/src/cloud_sync.rs`. Tests ciblés. Ce correctif ne constitue pas une preuve de transaction atomique entre tous les auteurs de réglages. |
| P1       | « Restaurer les achats » et la réconciliation dépendaient d'une liste StoreKit non vide. Une panne catalogue rendait la récupération inaccessible.                                                                      | L'écran Compte expose la restauration dans le canal Store même si le catalogue est vide ou indisponible ; réconciliation indépendante. Trois tests Playwright sur le composant de production avec IPC simulé.                                                             |
| P1       | Le manifeste `PrivacyInfo.xcprivacy` existait en source mais n'était pas copié dans le bundle macOS ; aucun manifeste trouvé dans l'app installée.                                                                      | Ajout explicite à `Contents/Resources` et contrôle de présence/validité dans le workflow du spike MAS. Le contenu de la déclaration doit encore être validé sur le bundle final et ses dépendances.                                                                       |
| P1       | La combinaison Cargo `mas,updater` réintroduisait les API privées du canal direct.                                                                                                                                      | Erreur de compilation explicite si `mas` et `direct` sont combinés ; `updater` implique déjà `direct`.                                                                                                                                                                    |
| P2       | Trois avis de sécurité JavaScript, dont deux classés élevés, dans l'outillage de développement.                                                                                                                         | `@humanfs/node` 0.16.8 et `browserslist` 4.28.9 verrouillés par overrides ; lockfile et dépendances Nix régénérés ; `bun audit --json` ne signale plus d'avis. Pas de preuve d'exploitation dans le binaire distribué.                                                    |
| P2       | Les tests Rust obligatoires tournaient sur Linux ; le job MAS était manuel. Les tests navigateur ouvraient `ProductPreview`, pas `App`.                                                                                 | Nouveau workflow macOS pour `updater` et `mas`, tests et Clippy du code de production. Ajout de tests du véritable composant Compte. Le parcours complet de `App` reste à couvrir.                                                                                        |
| P2       | Le CLI de benchmark héritait de la langue des réglages sans pouvoir la fixer pour une invocation. Un échantillon anglais a ainsi produit une sortie française avec Whisper.                                             | Ajout de `--language` à `--transcribe-file`, sans écriture des préférences ; langue effective ajoutée au JSON. Test de parsing et couverture existante de l'override éphémère.                                                                                            |

Avis JavaScript : [humanfs](https://github.com/advisories/GHSA-p498-v437-472g),
[Browserslist mémoire](https://github.com/advisories/GHSA-c83g-rgw3-j3cx),
[Browserslist statistiques](https://github.com/advisories/GHSA-73wf-gq98-2v4g).

## Risques encore ouverts

### Dépendances Rust et disponibilité des services

L'audit Rust a détecté `rtrb` 0.3.4 (`RUSTSEC-2026-0274`) ainsi que des avis
de sûreté mémoire sur `anyhow`, `event-listener`, `memmap2` et `rand` 0.8.
Corrections ponctuelles dans le lockfile : 0.3.5, 1.0.103, 5.4.2, 0.9.11 et
0.8.6 respectivement. Aucun chemin d'exploitation de ces avis dans Pressay
n'a été démontré ; les mises à jour évitent de conserver les versions concernées.

L'audit avec l'exception CI existante `RUSTSEC-2026-0235` passe. Cette exception
concerne `rkyv` 0.7 optionnel dans le lockfile : son absence du graphe activé doit
être contrôlée pour chaque canal. Il reste des avis de maintenance et des avis
`unsound` sur `glib` 0.18 et `rand` 0.7 hérités ; ne pas présenter cela comme
« aucune dette de sécurité ». Le registre de preuves conserve les identifiants.

Les probes publics de cette session établissent seulement ceci :

- `api.press-say.app` et le staging répondent 200 sur `/v1/desktop-auth/config`,
  et 401 sans session sur `/v1/me` et `/v1/entitlements`.
- Les anciennes routes `/health` et `/ready` répondent 404 sur les deux hôtes.
  Cela signale un runbook périmé ou une route absente, pas une preuve que le Cloud
  entier est arrêté. Retrouver des probes santé/readiness correspondant au backend.
- `updates.press-say.app` échoue en résolution DNS depuis le Mac audité, avec
  `curl` comme avec `fetch`. **La mise à jour automatique directe n'est pas
  validable tant que le service n'est pas rétabli ou la configuration corrigée.**
- Les liens web `/privacy`, `/terms` et `/support` répondent 200 après redirection
  vers `/en/...`. Aucun audit juridique ou de traitement d'un ticket n'en découle.

### P1 — soumission Store et fonctionnement natif

- La configuration MAS active App Sandbox et exclut NSPanel privé. Cela ne prouve
  pas que les raccourcis Fn, la capture de sélection AX, l'injection clavier,
  le presse-papiers différé et l'overlay fonctionnent dans un bundle signé Store.
  Sources : `src-tauri/src/selection_context.rs`, `paste_tx/macos.rs`,
  `shortcut/handy_keys.rs`, `overlay.rs`, `Entitlements.AppStore.plist`.
- Le workflow présent produit un spike ad hoc. Il ne remplace pas une archive
  provisionnée, la validation Apple et un test TestFlight. Les captures, notes de
  review et déclarations sous `docs/app-store/` contiennent encore des travaux à
  finaliser. Leur exactitude doit suivre les fonctions réellement validées.
- La version MAS est forcée à `2.0.0` dans `tauri.appstore.conf.json`, mais la
  version Cargo reste bêta. `default_pressay_cloud_api_url()` utilise la version
  Cargo et choisit donc staging sans `PRESSAY_CLOUD_API_URL` explicite. Les builds
  Store destinés à la production doivent sélectionner et vérifier leur backend.
- Le manifeste de configurations `config/build-environments.json` n'est pas un
  mécanisme d'injection de configuration à lui seul. Il faut relier le canal, la
  version, les identifiants OAuth/entitlements et les URL au build publié.

Apple exige un sandbox approprié, des API publiques et des mises à jour par le
Store pour la distribution MAS. L'acceptation de cette application dépendra de
ses comportements réellement observés ; aucune garantie de review n'est donnée.
[Règles Apple, sections 2.4.5 et 2.5.1](https://developer.apple.com/app-store/review/guidelines/).

### P1 — achats et droits commerciaux

- `Capabilities::for_tier()` annonce `app_store_purchase = ReleaseGate`, alors que
  `purchase_app_store_product()` vérifie seulement `mas`, l'identifiant produit
  et le compte. L'UI peut afficher le bouton d'abonnement lorsque StoreKit renvoie
  des produits. **Le verrou documenté n'est donc pas un verrou d'achat backend.**
  Aligner une politique explicite Sandbox/production, le backend et l'UI avant
  de configurer ou promouvoir des produits réels. Aucun achat déclenché ici.
- Les droits Pro ne sont imposés que si `commercial-entitlements` est compilé.
  Le workflow DMG actuel utilise `updater` seulement. La bêta fournit volontairement
  un aperçu Pro ; changer uniquement le numéro de version ne crée pas une offre
  payante protégée. Ne pas activer ce flag avant la matrice achat/récupération.
- Le pont Swift utilise `Transaction.currentEntitlements` et une réconciliation
  toutes les quinze minutes, sans écoute de `Transaction.updates`. Une validation
  différée ou externe peut donc attendre une actualisation. Ajouter un observateur
  au lancement et vérifier pending, renouvellement, révocation et reprise après
  erreur serveur. [Documentation StoreKit](https://developer.apple.com/documentation/storekit/transaction/updates).
- Le serveur de validation JWS, les notifications Apple, les webhooks Stripe,
  les remboursements et la projection signée des droits sont hors de ce dépôt.
  Il manque leurs preuves intégrées actuelles avec l'app candidate.

### P1 — compte, sync et données

- OAuth, vérification Ed25519, Keychain, X25519/HKDF et XChaCha20-Poly1305 sont
  présents. Leur présence et les tests unitaires ne constituent pas un audit
  cryptographique indépendant ni un test à deux appareils.
- La correction de sync réduit une fenêtre de perte de réglages. Les réglages
  reposent encore sur des lectures/modifications/écritures de structures complètes
  (`settings.rs::write_settings`) : plusieurs auteurs restent à tester ensemble.
  Exiger annulation de session et absence de restauration par réponse tardive
  pour bootstrap, refresh compte, sync, achat et suppression de compte.
- Une corruption de base, une erreur de migration ou un refus du Keychain pendant
  une migration d'historique peut faire échouer `HistoryManager::new` ; le démarrage
  principal utilise `expect`. Il manque une récupération utilisateur qui laisse
  la dictée locale accessible sans effacer la base (`lib.rs::initialize_core_logic`).

### P2 — performances, robustesse et langues

- Historique : la recherche appelle `getHistoryEntries(null, null)` après chaque
  modification avec debounce. Le backend charge/déchiffre alors tout l'historique.
  Les 30 éléments de la page initiale ne bornent donc pas la recherche. Mesurer
  1 000/10 000 entrées et implémenter recherche bornée/cancelable ou index local
  adapté au chiffrement avant de promettre un historique volumineux performant.
- Capture : `processed_samples` croît pendant tout l'enregistrement ; aucun
  plafond de durée trouvé dans ce chemin. À 16 kHz/f32, le seul buffer de sortie
  représente environ 230 Mo/heure, avant clones et moteur. Définir une limite
  produit et une sortie récupérable, puis tester pression mémoire et micro bloqué.
- Les tests macOS ne remplacent pas la matrice macOS 14/M1 8 Go, les micros USB et
  Bluetooth, le multi-écran, la veille/reprise et les onze contextes cibles du runbook.
- Le catalogue signé et le registre des trois modèles installés annoncent tous
  `supports_streaming = false`. `actions.rs` utilise alors la barre compacte et
  ne démarre pas le streaming. Les capacités peuvent être réconciliées au chargement
  du moteur, mais l'aperçu mot à mot ne doit pas être promis pour ces presets sans
  preuve d'exécution. Les scores vitesse/précision du catalogue sont également
  des valeurs éditoriales ; cet audit ne les valide pas comme des mesures.
- Le contrôle de traductions prouve 802 clés communes dans 23 langues hors anglais,
  pas leur traduction : 379 à 398 chaînes sont identiques à l'anglais dans les
  22 langues hors FR/EN ; français : 77. Des noms propres peuvent légitimement
  coïncider, mais de larges sections produit restent en anglais. Prévoir une revue
  humaine et limiter les promesses de localisation à ce qui est vérifié.
- `cargo clippy --all-targets -- -D warnings` a relevé sept avertissements promus
  en erreurs dans les tests existants (position des modules, initialisation,
  `repeat().take()`). Clippy sur `--lib --bins` est la vérification stricte retenue
  pour le nouveau workflow ; ce n'est pas une correction de ces sept avertissements.

### Notices et éléments commerciaux

`LICENSE` conserve la licence MIT du code Handy et `NOTICE` identifie cette origine
ainsi que les sons CC0. `docs/MODELS.md` documente les licences des poids de base
et exige les révisions et recettes de conversion des GGUF. Ces documents sont
présents ; cette session n'a pas reconstitué les preuves privées de conversion
ni produit la notice exhaustive des dépendances du binaire final. La présence
des pages web et des fichiers de licence ne ferme donc pas la revue des notices,
attributions, conditions de vente et déclarations de confidentialité de la release.

## Inventaire des fonctionnalités

« Partiel » signifie implémenté avec preuves ciblées ; « natif à valider » signifie
code présent sans preuve complète sur le binaire signé. Aucune ligne ci-dessous
n'est une promesse universelle de fonctionnement.

| Fonction                                                    | État actuel            | Preuves / validation restante                                                                 |
| ----------------------------------------------------------- | ---------------------- | --------------------------------------------------------------------------------------------- |
| Dictée locale sans compte                                   | Partiel                | Pipeline réel + essais WAV/Metal ; permissions, capture et insertion complètes à valider.     |
| Maintenir/parler/relâcher, toggle, annulation               | Natif à valider        | Coordinateur et tests de transitions ; stress clavier et conflits de raccourcis.              |
| Capture micro, canaux, VAD, resampling                      | Natif à valider        | Audio toolkit et tests ciblés ; périphériques, silence, retrait et reprise.                   |
| Fast, Polyglot, Precise                                     | Partiel                | Trois modèles installés ; réseau et intégrité vérifiables ; corpus FR/EN et matériel minimal. |
| Téléchargement, reprise, annulation, hash                   | Partiel                | Catalogue signé, transport HTTP testé ; disque plein et package neuf à tester.                |
| Modèles personnalisés, sélection, suppression, déchargement | Natif à valider        | ModelManager/commandes ; concurrence avec inférence et pression mémoire.                      |
| Traduction et langue de reconnaissance                      | Partiel                | Réglages et moteur ; compatibilité dépend du modèle et de la langue.                          |
| Aperçu en direct                                            | Natif à valider        | Worker streaming ; dépend des capacités du modèle et des performances.                        |
| Insertion, copie, frappe, conservation presse-papiers       | Natif à valider        | Reçus de collage et suivi de cible ; applications tierces et champs sécurisés.                |
| Correction vocale du dernier résultat                       | Natif à valider        | Vérification AX de la cible et copie de secours ; modification du texte/focus.                |
| Modes intégrés et personnalisés                             | Partiel                | Validation et résolution backend ; transformations réellement exécutées par route.            |
| Profils par application                                     | Partiel                | Priorités, langue, modèle, micro et sortie ; focus/permissions natives.                       |
| Dictionnaire exact/fuzzy et snippets                        | Partiel                | Validation et tests déterministes ; collisions, multilingue et faux positifs.                 |
| Commandes vocales déterministes                             | Partiel                | Parseur et tests ; corpus vocal et taux de déclenchement involontaire.                        |
| Résumé, email, liste, réécriture/sélection                  | Route dépendante       | Certaines étapes locales, d'autres Apple/BYOK/Cloud ; consentement et récupération.           |
| Historique texte/audio chiffré, rétention, favoris          | Partiel                | Crypto et schéma présents, défaut désactivé ; migration, purge et Keychain signé.             |
| Recherche, tags, export, retraitement historique            | Partiel                | UI et commandes présentes ; recherche non bornée et erreurs natives à tester.                 |
| BYOK et gestion des clés                                    | Partiel                | Keychain, clients et redaction ; aucun appel fournisseur payant effectué ici.                 |
| Apple Intelligence                                          | Natif à valider        | Pont FoundationModels et détection disponibilité ; macOS 26+, modèle/langue/compte OS.        |
| Auth Google, Apple, magic link, déconnexion                 | Partiel                | PKCE, callback et compte ; disponibilité fournisseurs réelle et matrice erreurs.              |
| Suppression compte                                          | Intégration à valider  | Commande cliente ; abonnement actif, effacement serveur et réponse perdue.                    |
| Pressay Cloud explicite                                     | Intégration à valider  | STT de secours et transformation sans fallback silencieux ; quotas et pannes réelles.         |
| Sync E2EE, appareils, code de récupération                  | Intégration à valider  | Crypto/merge/recovery présents ; deux appareils, perte de réponse, révocation.                |
| Free/Pro                                                    | Bêta                   | Matrice et guards présents ; enforcement compile-time désactivé par défaut.                   |
| Achats/restauration StoreKit                                | Intégration à valider  | Swift + validation serveur + UI ; incohérence du verrou et TestFlight ouverts.                |
| Facturation Stripe directe                                  | Hors périmètre serveur | Contrats clients/documentation ; pas de preuve live dans ce dépôt.                            |
| Onboarding, diagnostic, première dictée                     | Natif à valider        | UI production présente ; test novices et refus/récupération permissions.                      |
| Voice Bar Minimal/Live et menu bar                          | Natif à valider        | État partagé ; focus, transparence MAS, écrans et animation.                                  |
| Dix thèmes sonores                                          | Partiel                | Fichiers et tests catalogue ; écoute/périphérique/volume/accessibilité.                       |
| Thème, RTL, reduced motion, localisation                    | Partiel                | Tests preview ; VoiceOver/clavier et traduction humaine manquants.                            |
| Lancement au login, instance unique, CLI                    | Partiel                | SMAppService et dispatch ; relance, installation neuve et sandbox.                            |
| Mises à jour directes                                       | Canal direct           | Plugin/signatures configurés ; mise à jour depuis version précédente et rollback.             |
| Support et diagnostics locaux                               | Partiel                | Surfaces présentes ; parcours réel sans contenu utilisateur et liens finaux.                  |

Le détail des identifiants fonctionnels historiques reste dans le
[feature ledger](voice-os/FEATURE_LEDGER.md). Ce document ajoute une preuve datée,
sans transformer les validations ouvertes d'août en réussites supposées.

## Vérifications de cette session

Les commandes, résultats agrégés et limites sont enregistrés dans
[`audit-evidence/2026-09-06.json`](audit-evidence/2026-09-06.json).
Les logs de travail sont sous `/tmp/pressay-audit-20260906` ; ils ne sont pas
committés. Les seules fixtures vocales utilisées sont synthétiques, sans micro.

Résultats finaux : lint frontend, build TypeScript/Vite, formatage et contrôle
des clés de traduction réussis ; **322 tests Rust réussis dans chacun des canaux
`updater` et `mas`** ; Clippy strict réussi sur les bibliothèques et exécutables
des deux canaux ; build natif debug réussi. Le nouveau workflow CI n'a pas encore
été exécuté sur GitHub. Un build MAS a été interrompu faute d'espace disque, puis
repris avec succès après nettoyage du cache incrémental, sans incrémental et avec
un seul travail Cargo. Cela ne constitue pas un test « disque plein » de l'app.

Les résultats navigateur distinguent les huit scénarios de prévisualisation des
trois scénarios du vrai composant Compte avec IPC simulé. Aucun de ces onze tests
ne valide un paiement réel ni l'interaction inter-applications de macOS.

Le profil natif utilisé pour les essais STT est un build **debug**, avec Metal.
Le corpus comprend une phrase synthétique anglaise de 7,812 secondes et une phrase
française de 8,239 secondes, cinq répétitions par modèle et par langue.
Des compilations concurrentes peuvent perturber les temps. Ces mesures servent
à détecter une panne ou un ordre de grandeur, pas à publier un p95 produit.
Les valeurs finales contrôlées et la langue sont dans le registre de preuves.
Le « rtf » du CLI est un multiplicateur de vitesse `durée audio / durée calcul`,
pas le facteur temps réel classique inverse. Ne pas comparer ces deux conventions.

| Modèle   | Médiane d'inférence EN | Médiane d'inférence FR | Empreinte mémoire maximale du processus |
| -------- | ---------------------- | ---------------------- | --------------------------------------- |
| Fast     | 1,086 s                | 0,595 s                | 949 Mio                                 |
| Polyglot | 0,805 s                | 0,661 s                | 436 Mio                                 |
| Precise  | 3,501 s                | 3,413 s                | 1 560 Mio                               |

Les **30 exécutions ont abouti**, mais cela ne signifie pas 30 textes parfaits.
Le CLI conserve uniquement la dernière sortie de chaque série. Les trois sorties
finales anglaises conservent le sens attendu ; en français, la sortie Polyglot
remplace « test » par « Tesla », tandis que Fast et Precise conservent le sens.
Il ne s'agit pas d'un taux d'erreur représentatif. L'empreinte ci-dessus ne couvre
pas toute la mémoire système/GPU et les temps excluent chargement, micro et collage.

Le nouveau harness `scripts/voice-os/benchmark-local.ts` produit du JSONL sans
transcription ni chemin local, distingue la première inférence des suivantes,
mesure la mémoire du processus et ne calcule un p95 qu'à partir de 20 répétitions.
Le profil est déclaré par l'opérateur : fournir le binaire release correspondant.
Les autres réglages moteur persistés restent applicables : stabiliser aussi ces
réglages et la charge système pour comparer des versions. La charge moyenne a
atteint environ 40 sur les 8 cœurs logiques de ce Mac pendant la reconstruction.
Exemple après compilation de ce binaire et préparation d'une fixture synthétique :

```bash
bun run voice-os:benchmark-local \
  --binary ./src-tauri/target/release/pressay \
  --wav ./synthetic.wav --language fr --profile release --repeat 20 \
  > benchmark-fr.jsonl
```

## Fonctionnalités manquantes : ordre recommandé

| Priorité        | Ajout ou finition                                                              | Valeur, confidentialité et distribution                                                                           |
| --------------- | ------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| Avant vente     | Récupération native des erreurs de démarrage, historique/Keychain et insertion | Sauver le texte récupérable, expliquer l'action ; tout local. DMG et MAS. Lié à VO-002/208/223.                   |
| Avant vente     | Observateur StoreKit et état pending/restore fiable                            | Éviter « payé mais pas Pro » ; aucun audio nécessaire. MAS, VO-207.                                               |
| Avant vente     | Harness reproductible et budgets de performance                                | FR/EN, 20 répétitions, M1 8 Go, capture→insertion, mémoire et énergie ; fixtures synthétiques. VO-007.            |
| Avant vente     | Validation account/sync/quotas à deux appareils et support d'achat             | Fiabilité de récupération ; exclure audio, textes et clés des diagnostics. VO-201/202/203/206.                    |
| Avant vente     | Recherche historique bornée et plafond d'enregistrement                        | Éviter saturation et gels ; index local compatible chiffrement. VO-208/223.                                       |
| Après lancement | Import de fichiers audio, progression, annulation et export SRT/VTT            | Valeur professionnelle ; pipeline local réutilisable. CLI WAV déjà présent, parcours produit absent. VO-302.      |
| Après lancement | Petit modèle de reformulation entièrement local                                | Autonomie hors ligne ; n'engager qu'après benchmark mémoire sur M1 8 Go. VO-301.                                  |
| Plus tard       | Actions macOS par commandes vocales                                            | Demande modèle de menace, liste fermée et confirmation des actions sensibles ; faisabilité MAS distincte. VO-304. |

Il n'est pas nécessaire d'ajouter réunions, synchronisation audio, agent système
généraliste ou nouveau moteur avant le lancement. Cela augmenterait les données
sensibles, la charge mémoire et la surface de validation sans résoudre le chemin
critique actuel.

## Conditions mesurables de GO

1. **Source candidate** : version/canal/backend cohérents, CI verte sur le commit,
   audit dépendances, build reproductible, diff revu par un humain.
2. **Dictée** : matrice native du runbook réussie sur macOS 14/M1 8 Go et Mac récent,
   y compris offline, annulation, champs sécurisés, micro retiré et presse-papiers.
3. **Performance** : capture/affichage sans gels ; cible initiale Fast/M1 pour texte
   court médiane release→insert < 1,5 s, p95 < 3 s ; aucune croissance mémoire
   persistante sur 20 dictées. Mesurer aussi démarrage froid et précision FR/EN.
4. **Données** : migration/rétention/historique défectueux récupérables ; sync à deux
   appareils et révocation prouvées ; revue sécurité indépendante sans risque élevé ouvert.
5. **Commerce** : achat, pending, annulation, renouvellement, grace, expiration,
   remboursement, restore, changement d'appareil/compte et panne serveur prouvés.
   Rapprocher systématiquement fournisseur, serveur et droits visibles dans l'app.
6. **Canal direct** : nouveau bundle signé/notarisé/staplé, téléchargement neuf,
   mise à jour depuis bêta et retour arrière testés.
7. **MAS** : bundle sandbox signé/provisionné, inspection API/entitlements/manifestes,
   TestFlight, matrice native et achat Sandbox ; métadonnées exactes et soumission.
8. **Exploitation** : backend production et sauvegarde/restauration vérifiés,
   alertes sans contenu sensible, support opérationnel, contrats et déclarations
   administratives complétés par leur responsable.

Les appareils, Apple/TestFlight, comptes Sandbox/fournisseurs, backend privé et
attestations personnelles sont des dépendances réelles. Les modifier ou les
déclarer conformes à partir du code local ne fermerait pas ces conditions.
