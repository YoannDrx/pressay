# Pressay translations

French and English are the reviewed product locales. The inherited additional
locales remain available as beta translations until they receive human review.

Translation files live in `src/i18n/locales/<locale>/translation.json` and must
keep exactly the same key structure as the English source.

After editing a locale, run:

```bash
bun run check:translations
bun run format:check
```

Do not translate the product name `Pressay`, provider names, model names, URL
schemes, bundle identifiers, or command-line examples. Privacy notices must not
be softened: local, BYOK, and Pressay Cloud are distinct processing routes.
