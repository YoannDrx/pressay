# Runbook des release gates Voice OS

Ce runbook transforme les validations externes restantes en commandes reproductibles. Une gate ne passe que si le rapport identifie la version de l’app, la machine, macOS, le canal (`direct` ou `mas`), la date et l’opérateur, sans audio, transcription, clé ou identifiant personnel.

## 1. Préflight automatisé

```bash
bun run check:translations
bun run lint
bun run build
bun run test:playwright
PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH" cargo test --manifest-path src-tauri/Cargo.toml --lib
bun run voice-os:native-baseline > native-baseline.json
bun run voice-os:probe-models > model-routes.jsonl
```

Le baseline ne collecte ni numéro de série, ni nom d’utilisateur, ni micro, ni contenu. Le probe modèles ne télécharge qu’un en-tête HTTP ou un octet et compare la taille annoncée à la taille du catalogue signé.

État observé le 17 août 2026 : les trois fallbacks Hugging Face répondent et annoncent la taille attendue ; les trois routes primaires `models.press-say.app` échouent. `MODEL-CDN` reste donc rouge jusqu’au rétablissement du DNS/CDN puis à la vérification des SHA-256 complets.

## 2. Matrice native macOS

Machines obligatoires : M1 8 Go/macOS 14, Mac médian, Mac Apple Intelligence/macOS 26+. Exécuter d’abord le DMG signé, puis le build MAS signé pour les lignes applicables.

Pour Mail, Messages, Notes, Safari, Chrome, Slack, Notion, Word, Cursor et Terminal :

1. maintenir, parler, relâcher ;
2. toggle démarrage/arrêt ;
3. annuler pendant écoute, transcription et transformation ;
4. dicter 10 secondes, 2 minutes puis 10 minutes ;
5. changer le focus avant insertion ;
6. préserver un presse-papiers texte puis riche ;
7. tester français, anglais et alternance de langue ;
8. débrancher le micro, produire du silence et retirer chaque permission ;
9. tester un champ sécurisé : aucune sélection sensible ni insertion non autorisée ;
10. couper le réseau : la dictée locale reste utilisable.

Conserver par ligne : `pass/fail`, code d’erreur public, temps touche→arming, arming→waveform, release→insert, pic mémoire, route affichée, état menu bar, état Voice Bar et lien vers une capture redacted.

## 3. Modèles et performance

Le binaire possède déjà un chemin headless pour les WAV :

```bash
./Pressay --list-models --json
./Pressay --transcribe-file fixture-fr-10s.wav --model '<catalog-id>' --json
```

Pour Fast, Polyglot et Precise : téléchargement primaire, fallback, pause/reprise, annulation, reprise après relance, checksum invalide, disque insuffisant, suppression active et rechargement. Mesurer cinq cold runs et vingt warm runs. Publier médiane/p95, RAM maximum et facteur temps réel ; ne jamais publier un chiffre provenant d’une autre machine ou d’un autre corpus.

## 4. BYOK

Le probe ne transmet aucun texte ; il valide uniquement l’authentification et le contrat JSON de `/models` :

```bash
PRESSAY_BYOK_OPENAI_KEY='…' bun run voice-os:probe-byok
```

Variables prises en charge : `OPENAI`, `ZAI`, `OPENROUTER`, `ANTHROPIC`, `GROQ`, `CEREBRAS`, `BEDROCK_MANTLE`, préfixées par `PRESSAY_BYOK_` et suffixées par `_KEY`. Pour un endpoint compatible : `PRESSAY_BYOK_CUSTOM_URL` et `PRESSAY_BYOK_CUSTOM_KEY`.

Après le probe, exécuter dans l’app une transformation synthétique sans donnée utilisateur : clé valide, invalide, remplacée et supprimée ; 401, 403, 408, 429, 5xx, DNS, timeout, réponse non JSON, modèle manuel, structured output et refus du paramètre de raisonnement. Inspecter les logs pour prouver l’absence de clé, URL sensible, prompt, texte et réponse.

## 5. Staging compte et sync

Dans `pressay-cloud` :

```bash
bun run verify
bun run validate:staging
```

Le probe vérifie health, readiness, config desktop auth et le refus sans session des entitlements et de la sync. Le 17 août 2026, ces cinq contrôles passent sur `pressay-cloud-staging.vercel.app`.

La gate complète exige ensuite deux comptes de test et deux Macs : magic link valide/expiré/rejoué, Google, Apple, premier appareil, second pending, approbation, refus, révocation, conflit, récupération à usage unique, réponse perdue, suppression et offline grace. Répéter avec le backend coupé et vérifier que la route locale ne change pas.

## 6. Stripe direct

La suite source valide les contrats et webhooks simulés. Les actions suivantes créent de l’état Stripe Test et requièrent donc un opérateur autorisé :

- mensuel et annuel ; essai avec/sans moyen de paiement ;
- upgrade/downgrade et prorata ;
- Test Clock renouvellement, past-due, récupération et expiration ;
- annulation immédiate/fin de période, remboursement partiel/complet, chargeback ;
- taxes, devise, facture et portail ;
- webhook dupliqué, retardé, hors ordre et signature invalide ;
- suppression du compte avec abonnement actif.

Pour chaque scénario, comparer abonnement Stripe, projection SQL, révision d’entitlement signée et `Capabilities` du Mac. Le redirect Checkout n’accorde jamais Pro. N’activer `commercial-entitlements` qu’après passage de toute cette matrice.

## 7. StoreKit MAS

Passer successivement StoreKit Configuration locale, Sandbox puis TestFlight : mensuel/annuel, interruption, Ask to Buy, restore nouveau Mac, expiration, billing retry/grace, remboursement/révocation, changement Apple ID, compte Pressay différent et validation serveur indisponible. Vérifier qu’aucun CTA, URL ou appel Stripe n’existe dans le binaire MAS.

## 8. Sécurité externe

Le paquet de revue comprend le threat model, `cloud_sync.rs`, `sync_crypto.rs`, protocole de récupération, allowlist sync, validation d’entitlements, Keychain, suppression de compte et redaction. La gate échoue tant qu’un finding critique ou élevé reste ouvert. Les transcripts, audio, historique, sélection, prompts et clés BYOK doivent être absents des payloads sync et diagnostics.

## 9. Landing et performance

Sur une URL Preview de production, mesurer desktop et mobile avec reduced motion activé puis désactivé. Gates : LCP < 2,5 s, CLS < 0,1, INP < 200 ms, absence d’erreur console, clavier complet et scène statique sur GPU faible. Conserver le JSON Lighthouse/Web Vitals avec le SHA du déploiement.

## 10. Format de preuve

```json
{
  "gate": "MODEL-CDN",
  "status": "pass | fail | blocked",
  "appVersion": "2.0.0-beta.3",
  "commit": "<sha>",
  "channel": "direct | mas | web | cloud",
  "machineClass": "M1-8GB-macOS14",
  "executedAt": "<ISO-8601>",
  "operator": "<internal-id>",
  "evidence": ["<artifact path or CI URL>"],
  "notes": "No user content or secrets"
}
```

Une ligne ne passe jamais sur la seule base d’un mock, d’un écran visible ou d’un type présent dans le code.
