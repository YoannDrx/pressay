# Étude de compatibilité : anciens Mac et Intel

État au 16 septembre 2026, source native `22d14b9`. Étude de faisabilité et de charge,
aucun élargissement du support annoncé. La cible commercialisable reste macOS 14+
sur Apple Silicon. Les fourchettes sont des estimations d'ingénierie, pas un devis.

## Décision proposée

Terminer la recette et le lancement de la cible actuelle, puis prototyper macOS 13+
sur Apple Silicon et Intel. Garder Monterey comme option conditionnelle aux mesures.
Le coût principal est la compilation et la maintenance des dépendances natives,
puis la recette sur plusieurs générations de matériel. Une baisse du minimum Tauri
ne suffit pas.

## Contraintes observées

| Couche                    | Source du dépôt                                                                                          | Conséquence                                                                                                                                                                          |
| ------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Distribution              | `docs/RELEASES.md`, `src-tauri/tauri.conf.json`, `src-tauri/tauri.appstore.conf.json`                    | DMG et Mac App Store séparés ; signature, notarisation, mises à jour et achats à qualifier par architecture.                                                                         |
| ONNX                      | `src-tauri/Cargo.lock` : `ort` et `ort-sys` 2.0.0-rc.12 ; `src-tauri/Cargo.toml` : `transcribe-rs` 0.3.8 | ONNX Runtime 1.24 relève son minimum à macOS 14 et ne fournit plus de binaires x86_64 macOS. Ne pas remplacer une dylib par une version antérieure sans aligner l'ABI et les crates. |
| CI Intel                  | `.github/workflows/build.yml`, étape « Install ONNX Runtime (x86_64 macOS) »                             | La branche héritée télécharge `onnxruntime-osx-x86_64-1.24.2.tgz` ; contrôle HTTP du 16 septembre : **404**. Elle ne prouve pas une distribution Intel fonctionnelle.                |
| Inférence et VAD          | `transcribe-rs`, `transcribe-cpp` 0.1.3, `audio_toolkit/vad`                                             | La détection de parole utilise aussi ONNX. Se limiter à Whisper ne supprime donc pas automatiquement cette dépendance.                                                               |
| StoreKit                  | `src-tauri/swift/storekit.swift`, `storekit_bridge.h`                                                    | Le contrôle de types réussit pour macOS 12 ARM et Intel avec le SDK local. Cela ne valide ni l'édition de liens complète, ni les transactions sur un ancien système.                 |
| Interface                 | `package.json` : Tailwind 4.3.3, WebView Tauri                                                           | Tailwind 4 vise Safari 16.4+. Vérifier le WebKit livré et mis à jour sur chaque système, particulièrement Monterey.                                                                  |
| Capacités conditionnelles | pont Apple Intelligence et sélection des routes                                                          | Apple Intelligence ne fait pas partie du périmètre Intel ; afficher son indisponibilité et conserver le local, sans basculement Cloud implicite.                                     |

Sources primaires : [annonce ONNX Runtime 1.24.1](https://github.com/microsoft/onnxruntime/releases/tag/v1.24.1),
[compatibilité Tailwind](https://tailwindcss.com/docs/compatibility),
[choix d'API StoreKit](https://developer.apple.com/documentation/storekit/choosing-a-storekit-api-for-in-app-purchases).

## Contrôles exécutés

```sh
xcrun swiftc -typecheck -target arm64-apple-macosx12.0 \
  -import-objc-header src-tauri/swift/storekit_bridge.h src-tauri/swift/storekit.swift
xcrun swiftc -typecheck -target x86_64-apple-macosx12.0 \
  -import-objc-header src-tauri/swift/storekit_bridge.h src-tauri/swift/storekit.swift
curl -s -o /dev/null -w '%{http_code}\n' --max-time 20 \
  https://models.press-say.app/onnxruntime-osx-x86_64-1.24.2.tgz
```

Résultats : les deux contrôles Swift réussissent ; le miroir répond 404.
Aucun binaire complet Intel/macOS 12–13 n'a été exécuté. Aucune latence, consommation
mémoire ou stabilité sur ancien matériel n'est présentée comme mesurée.

## Prototype de 2 à 4 jours, inclus dans les estimations

1. Comparer une compilation ONNX maintenue avec minimum compatible à une adaptation
   coordonnée des versions `ort`, `ort-sys`, VAD et `transcribe-rs`. Documenter les
   correctifs de sécurité perdus si une ancienne branche est retenue.
2. Construire un binaire complet ARM et Intel. Inspecter toutes les dylibs avec
   `file`, `otool -L` et `vtool -show-build`, vérifier leurs minima et les chemins
   `@rpath`, tester CPU et Metal séparément. Interdire les optimisations CPU propres
   à la machine de compilation dans les livrables Intel.
3. Exécuter le corpus FR/EN de `docs/app-store/fixtures/dictation-corpus.json` sur
   Apple Silicon et sur un Intel réel de référence, avec 8 et 16 Go si disponibles.
   Mesurer démarrage à froid, p50/p95, temps réel/durée audio, pic mémoire et erreurs.
4. Décider : matrice viable, modèles recommandés, minimum mémoire, ancien WebKit
   acceptable ou travail CSS nécessaire. Arrêter l'extension si le moteur n'est
   pas stable ou si la maintenance ONNX dépasse le budget convenu.

## Charge et coût illustratif

Les lignes décrivent des scénarios alternatifs et ne s'additionnent pas. Base de
calcul : 600 € par jour, hors matériel, infrastructure et attente de validation Apple.

| Scénario                          | Charge initiale | Budget illustratif |
| --------------------------------- | --------------: | -----------------: |
| macOS 13, Apple Silicon           |      6–12 jours |      3 600–7 200 € |
| Intel, macOS 14+                  |     10–18 jours |     6 000–10 800 € |
| macOS 13+, Intel et Apple Silicon |     12–22 jours |     7 200–13 200 € |
| macOS 12+, Intel et Apple Silicon |     18–30 jours |    10 800–18 000 € |

Ces charges comprennent prototype, intégration, distribution et recette. Elles
supposent l'accès aux machines de test et un moteur ONNX compatible maintenable.
Prévoir ensuite 1 à 3 jours supplémentaires par version significative, davantage
si Pressay doit maintenir et sécuriser sa propre distribution ONNX.

Coûts récurrents : machines et maintenance OS, minutes CI natives, stockage/CDN de
binaires supplémentaires et support utilisateur. Un bundle Universal augmente le
téléchargement ; deux binaires exigent une sélection de téléchargement et des flux
updater corrects par architecture. La dictée locale n'entraîne pas mécaniquement
un coût Cloud supplémentaire. Aucun matériel ni service n'a été acheté ici.

## Matrice d'acceptation avant toute annonce

- Installation, signature Developer ID, notarisation, Gatekeeper, première ouverture.
- Modèles : téléchargement interrompu, reprise, corruption, stockage insuffisant.
- Permissions microphone/Accessibilité, champ sécurisé, raccourcis maintien/bascule.
- Enregistrement, transcription, insertion dans Notes/navigateur/éditeur, presse-papiers.
- Veille/reprise, changement de microphone, relance, autostart et seconde instance.
- UI WebKit : onglets, dialogues, clavier, VoiceOver, contraste et zoom.
- DMG : mise à jour signée depuis la version précédente, architecture inchangée.
- Mac App Store : installation TestFlight, achat, restauration, remboursement,
  renouvellement, expiration ; aucun appel à la mise à jour directe.
- Compte et droits signés : Free hors ligne, accès offert, Stripe/Apple, révocation.
- Précision FR/EN, temps réel, mémoire et stabilité comparés à la cible actuelle.

Réutiliser `docs/app-store/native-release-matrix.fr.md` pour le registre de preuves,
avec OS, architecture, RAM, modèle, commit, build, date et résultat de chaque essai.
