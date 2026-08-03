# Pressay — Master Roadmap produit, technique et go-to-market

État de référence : 3 août 2026

Ce document pilote l’ordre de livraison. `AUDIT.md` décrit les preuves et
écarts actuels ; `ROADMAP.md` conserve l’historique fonctionnel ;
`RELEASE_READINESS.md` définit les gates de distribution.

## 1. État vérifié

- La stable publique est `v1.2.3` (12102), signée et notarialisée.
- L’appcast canonique GitHub Pages a été restauré et répond `200` avec l’URL
  immuable et la signature EdDSA de 1.2.3, tout en conservant 1.2.2.
- La stable Direct `v1.2.3` restaure tous les items
  et formats du presse-papiers après une insertion réussie, sans écraser une
  copie concurrente de l’utilisateur.
- Le canal App Store reste 1.2.0 (12005), sandboxé et volontairement copy-only.
- Le binaire actuel ne propose que OpenAI et WhisperKit. Groq, Deepgram,
  Anthropic, le client compte et l’abonnement ne sont pas livrés dans l’app.
- L’API Hono locale couvre comptes, appareils, entitlements, Founding claim,
  Stripe BYOK/Lifetime, suppression, rate limiting et snapshots Ed25519. Elle
  n’est pas encore déployée avec une configuration production validée.
- Les migrations 0001–0003 ont été validées sur la branche Neon temporaire
  `preview/pressay-commercial-foundation` (`br-snowy-math-asgixypw`). Neon
  `main` n’a pas été modifiée.
- Le site Next.js 16 autonome est versionné dans `YoannDrx/pressay-web` et
  déployé sur `press-say.app`, avec redirection permanente de `www`.
- Clerk, les produits Stripe, les emails et les secrets de signature ne sont
  pas encore configurés. Les parcours commerciaux échouent donc fermés.

## 2. Promesse et principes

> Maintiens Fn. Parle. C’est écrit.

Pressay est une barre de commande vocale macOS contrôlable : la cible est
prouvée, le contexte transmis est visible et toute transformation reste
réversible.

- Free local/BYOK fonctionne sans compte et sans quota de dictée Fidèle.
- Cible, récupération, export et suppression ne sont jamais paywallés.
- L’app ne se connecte jamais directement à Postgres.
- Audio, dictée, sélection, contexte et clés BYOK ne sont jamais stockés par le
  backend Pressay.
- Une fonctionnalité n’est vendue que si son parcours nominal, ses erreurs,
  permissions, suppression et tests sont prêts.
- App Store et Direct restent deux chaînes de distribution distinctes.
- Pro Cloud, synchronisation hébergée et Teams restent invisibles jusqu’à
  preuve technique et économique.

## 3. Plans retenus

| Plan | Prix | Périmètre réel |
| --- | --- | --- |
| Free | 0 € | Dictée locale/BYOK illimitée, Fidèle/Propre/Message, historique chiffré 24 h, vocabulaire et protections |
| Pro BYOK | 7,99 €/mois ou 69 €/an | Tous modes livrés, modes personnalisés, profils par app, historique 30 jours, recherche/tags/favoris/retraitement, Inbox et outils développeur effectivement disponibles, 3 Mac |
| Lifetime BYOK | 149 € TTC au lancement | Même périmètre local/BYOK que Pro, paiement unique, sans cloud géré/sync hébergée/Teams |

L’essai Pro dure 14 jours sans carte et est limité par compte et appareil. Les
installations éligibles à 1.2.3 créent une preuve locale unique dans le
Trousseau, réclamable une fois et convertie en droit Lifetime/legacy.

## 4. Tracks et gates

### Track A — Stabiliser Direct 1.2.3

- [x] restaurer l’appcast public 1.2.2 ;
- [x] implémenter le contrat transactionnel du presse-papiers ;
- [x] ajouter les tests texte riche, multi-item, vide et modification concurrente ;
- [x] passer version/build à 1.2.3 (12102) ;
- [x] durcir le workflow pour recréer `gh-pages` et vérifier l’appcast public ;
- [x] créer la preuve Founding locale, sans activer le paywall ;
- [ ] rejouer la matrice Tier A/B dans les applications cibles ;
- [ ] tester micro interne, AirPods et micro USB ;
- [x] valider installation propre, Gatekeeper, notarisation et checksum sur Apple Silicon ;
- [ ] valider la mise à jour signée 1.2.2 → 1.2.3 ;
- [ ] tester sur Intel réel et Apple Silicon ;
- [ ] achever sept jours de dogfood avec zéro P0/P1.

La stable a été publiée le 3 août 2026 sur autorisation explicite du propriétaire
du produit. La matrice, Intel réel, les périphériques audio et sept jours de
dogfood restent ouverts et ne doivent pas être présentés comme validés.

### Track B — Backend commercial staging

- [x] versionner Hono, migrations et tests ;
- [x] retirer Pro Cloud des offres achetables et de la configuration requise ;
- [x] appareils actifs, limite 1/3, révocation et suppression de compte ;
- [x] entitlements complets et snapshot Ed25519 avec grâce 14 jours ;
- [x] Founding claim hashé, unique et borné à l’app 1.2.3 ;
- [x] Checkout mensuel/annuel/Lifetime et essai 14 jours sans carte ;
- [x] Portal, webhooks signés, déduplication, ordre fournisseur et remboursement ;
- [x] CORS restreint, headers, rate limit et logs sans contenu ;
- [x] valider le schéma sur une branche Neon temporaire ;
- [ ] créer Clerk staging et configurer Authorization Code + PKCE S256 ;
- [ ] créer les produits/prix/webhooks Stripe en mode test ;
- [ ] générer et stocker la clé privée Ed25519 hors dépôt ;
- [ ] déployer `api-staging.press-say.app` et lancer les tests Postgres/Stripe réels ;
- [ ] tester rotation refresh, `state`, trois appareils et suppression Clerk + API ;
- [ ] ajouter réconciliation périodique Stripe et alerte webhook.

Gate staging : auth, migration, webhook, suppression et grâce hors ligne verts,
aucun secret client et aucune donnée de contenu dans les logs.

### Track C — Client compte et feature gates

- [ ] navigateur système, Authorization Code + PKCE, callbacks `pressay://` et
  `pressay-companion://` ;
- [ ] access/refresh tokens dans le Trousseau et rotation sûre ;
- [ ] bootstrap, appareils, claim Founding et déconnexion ;
- [ ] validation Ed25519 du snapshot et grâce hors ligne 14 jours ;
- [ ] retour Free sans effacement des modes, historique ou Inbox ;
- [ ] écran Compte/Abonnement Direct ;
- [ ] feature gates Free/Pro couverts par tests ;
- [ ] parcours StoreKit 2 séparé pour Companion.

Le paywall ne doit pas être activé dans 1.2.3 : cette version prépare
l’éligibilité des utilisateurs existants.

### Track D — Site et domaine

- [x] dépôt Next.js 16 distinct et design sombre/ivoire/cobalt ;
- [x] FR/EN, pricing, sécurité, téléchargement, légales et support ;
- [x] compte/Checkout/Portal conditionnels et fail-closed ;
- [x] sitemap, Open Graph, JSON-LD, CSP/HSTS et reduced motion ;
- [x] Playwright desktop/mobile et Lighthouse ≥ 95 ;
- [x] déploiement technique Vercel ;
- [ ] connecter `press-say.app` et rediriger `www` ;
- [ ] connecter les sous-domaines API staging/production ;
- [ ] configurer Clerk, Stripe et emails SPF/DKIM/DMARC ;
- [ ] valider TLS, CORS, Checkout et Portal sur staging ;
- [ ] promouvoir le domaine canonique après validation commerciale.

### Track E — Portfolio temporaire

- [ ] attendre le DMG et l’appcast publics 1.2.3 ;
- [ ] passer la fiche FR/EN à 1.2.3 avec le nombre XCTest réellement exécuté ;
- [ ] ajouter la preuve « Pressay restitue votre presse-papiers » ;
- [ ] conserver `/download/pressay` vers `releases/latest` ;
- [ ] ajouter `press-say.app` uniquement après publication du domaine ;
- [ ] vérifier OG, JSON-LD, checksum, mobile et desktop en production.

Les images locales non suivies du portfolio doivent rester intactes.

## 5. Roadmap produit après monétisation

1. Localisation complète FR/EN et onboarding local-first.
2. Mémoire explicite et justifiée : remplacements, prononciations, noms,
   projets et règles supprimables.
3. Pack développeur : Prompt code, Bug, Rubber Duck, Commit, PR, Ticket, Logs.
4. Contexte projet opt-in, respect `.gitignore`, exclusion des secrets et
   manifeste visible.
5. Provider contract v2, puis Groq/Deepgram/Anthropic après corpus FR/EN et
   tests de non-fuite.
6. Snippets, App Intents et intégrations locales avec confirmation.
7. Synchronisation E2EE facultative des modes et préférences uniquement.
8. Réunions, diarisation et Teams après preuve de rétention D30.

## 6. Definition of Done

Une capacité est « fonctionnelle et validée » uniquement si :

1. le parcours nominal et les erreurs sont couverts ;
2. annulation, permissions et absence de perte de données sont prouvées ;
3. rétention, export et suppression sont documentés ;
4. tests automatisés et matrice manuelle correspondante sont verts ;
5. les deux canaux de distribution ont un comportement explicite ;
6. la documentation et le marketing décrivent le code réellement livré ;
7. aucun P0/P1 n’est ouvert.

## 7. Prochaine séquence exécutable

1. Relecture du correctif 1.2.3 et gate locale complète.
2. Matrice Tier A/B, microphones, Intel et installation propre.
3. Dogfood sept jours, puis tag/release Direct 1.2.3.
4. Mise à jour du portfolio après vérification des artefacts publics.
5. Configuration Clerk/Stripe/Ed25519 sur staging.
6. Déploiement API staging et tests de bout en bout.
7. Implémentation du client compte/entitlements dans une version ultérieure.
8. DNS `press-say.app`, bêta commerciale 30–50 utilisateurs, puis ouverture
   de Pro BYOK si les gates sont vertes.
