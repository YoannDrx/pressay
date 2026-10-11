import i18next from "eslint-plugin-i18next";
import tsParser from "@typescript-eslint/parser";

export default [
  {
    files: ["src/**/*.{ts,tsx}"],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        ecmaFeatures: {
          jsx: true,
        },
      },
    },
    plugins: {
      i18next,
    },
    rules: {
      // tauri-plugin-dialog replaces window.confirm/alert/prompt with async
      // functions, so a synchronous check such as `if (!confirm(...))` tests a
      // Promise and never blocks. Use `confirmDestructiveAction` (src/lib) or
      // `ask`/`message` from @tauri-apps/plugin-dialog and await the result.
      "no-restricted-globals": [
        "error",
        ...["confirm", "alert", "prompt"].map((name) => ({
          name,
          message:
            "Use confirmDestructiveAction or ask/message from @tauri-apps/plugin-dialog and await the result.",
        })),
      ],
      "no-restricted-properties": [
        "error",
        ...["confirm", "alert", "prompt"].flatMap((property) =>
          ["window", "globalThis", "self"].map((object) => ({
            object,
            property,
            message:
              "Use confirmDestructiveAction or ask/message from @tauri-apps/plugin-dialog and await the result.",
          })),
        ),
      ],
      // Catch text in JSX that should be translated
      "i18next/no-literal-string": [
        "error",
        {
          markupOnly: true, // Only check JSX content, not all strings
          ignoreAttribute: [
            "className",
            "style",
            "type",
            "id",
            "name",
            "key",
            "data-*",
            "aria-*",
          ], // Ignore common non-translatable attributes
        },
      ],
    },
  },
];
