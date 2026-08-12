# Pressay API

Backend minimal et portable devant Neon Postgres. L’application macOS ne se
connecte jamais directement à la base.

## Responsabilités

- comptes et appareils ;
- droits actifs `free`, `pro_byok` et `lifetime_byok` ; les codes Cloud/Teams
  restent réservés mais ne sont ni achetables ni annoncés ;
- compteurs d’usage idempotents ;
- synchronisation future de réglages chiffrés de bout en bout ;
- projection de facturation Stripe / App Store.

Hors périmètre de stockage : audio, dictées, texte sélectionné, contenu des
transformations et clés API BYOK.

## Démarrage local

1. Copier `.env.example` vers `.env` et renseigner une chaîne Neon poolée.
2. Exécuter les migrations `db/migrations/0001` à `0010` dans l’ordre sur une branche Neon de développement.
3. Lancer `pnpm install`, puis `pnpm dev`.

Les routes métier sous `/v1/*` exigent un JWT OIDC signé. Les endpoints
`/v1/health`, `/v1/ready` et le webhook Stripe vérifié sont publics. Le choix
du fournisseur d’identité est découplé du schéma commercial. Better Auth est
auto-hébergé sur `press-say.app`; l’API sélectionne explicitement la source de
confiance selon l’issuer, puis valide audience et signature. Clerk peut rester
accepté temporairement pendant le rollback sans être requis après la bascule.

Le client macOS utilise Authorization Code + PKCE et le callback public
`pressay://oauth/callback`. Le client OAuth historique
`w9ckUgrcFp7H7wNV` est conservé pour éviter de casser les builds installés ;
ses tokens Better Auth ciblent la ressource/audience
`https://api.press-say.app`. Les jetons internes émis par le proxy web gardent
l’audience privée `pressay-api` et ne sont pas exposés au client macOS.

## Facturation

Stripe est désactivé tant que les variables BYOK, Lifetime, webhook et URLs de
retour ne sont pas fournies. Les Price IDs Pro Cloud ne sont pas requis. Le
client n’envoie jamais de Price ID : il envoie
un plan et une périodicité, puis l’API sélectionne un Price ID allowlisté.

Endpoints :

- `POST /v1/accounts/bootstrap` : provisionne le compte et le droit Free ;
- `GET /v1/entitlements` : renvoie le contrat complet et sa signature Ed25519 ;
- `GET /v1/devices` / `DELETE /v1/devices/:id` : liste et révoque les Mac ;
- `POST /v1/founding/claim` : consomme une preuve locale 1.2.3 une seule fois ;
- `DELETE /v1/me` : supprime le compte produit et son client Stripe ;
- `POST /v1/billing/checkout` : crée une Checkout Session ;
- `POST /v1/billing/portal` : ouvre le Customer Portal ;
- `POST /v1/webhooks/stripe` : vérifie le corps brut et la signature Stripe.
- `GET /v1/internal/reconcile` : cron protégé qui réconcilie les abonnements et
  purge les anciennes fenêtres de rate limit.

Les événements sont dédupliqués avec l’ID Stripe et projetés selon leur date
fournisseur afin qu’un événement ancien ne puisse pas écraser un état récent.
Appliquer toutes les migrations dans l’ordre. La migration `0004`
autorise un essai lié au compte depuis le site lorsque aucun identifiant de Mac
n'est encore disponible ; les checkouts natifs continuent d'associer l'essai à
un appareil enregistré.

La migration `0009` ajoute les tables Better Auth et le client OAuth macOS sans
modifier `accounts.auth_subject`. `DELETE /v1/me` supprime l’identité Better
Auth locale et supprime aussi Clerk pendant la coexistence lorsque
`CLERK_SECRET_KEY` est encore configuré. `PRESSAY_ENTITLEMENT_SIGNING_PRIVATE_KEY` signe les
octets exacts exposés dans `snapshot.payload`, et `CRON_SECRET` protège la
réconciliation quotidienne déclarée dans `vercel.json`.

## Vérification

```sh
pnpm typecheck
pnpm test
TEST_DATABASE_URL='postgresql://…' pnpm test
```

## Environnements Neon

Projet actuel : `snowy-meadow-52007899`, région `aws-eu-central-1`.
La migration initiale est appliquée uniquement sur `development`
(`br-summer-flower-as8fzs30`). La branche `main` reste volontairement vide
jusqu'à la validation de l'authentification et du déploiement API.

- une branche `development` pour le travail quotidien ;
- une branche éphémère par pull request ;
- une branche `staging` avant migration de production ;
- la branche de production protégée, avec autoscaling, pooling et sauvegardes configurés.

Ne jamais exposer `DATABASE_URL` dans l’application macOS ni dans une variable
préfixée comme publique côté frontend.

## Déploiement

Le dossier est lié au projet Vercel `yoanndrxs-projects/pressay-api`. Le point
d’entrée `src/index.ts` exporte directement l’application Hono pour Vercel ;
`src/local.ts` conserve le serveur Node local. Aucun déploiement ne doit être
effectué avant d’avoir configuré `DATABASE_URL`, l’issuer OIDC, le JWKS et les
variables Stripe dans les environnements Preview et Production.
