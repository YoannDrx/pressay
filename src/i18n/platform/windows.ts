/**
 * Windows wording for strings whose shared catalogue says "Mac", "macOS" or
 * "Keychain". Merged over the reviewed catalogues (English and French) only
 * when the app runs on Windows, so the macOS copy keeps its native voice.
 * macOS-only surfaces (App Store, Accessibility, Secure Input, Apple
 * Intelligence) never render on Windows and are not overridden.
 */
type Overrides = Record<string, unknown>;

const en: Overrides = {
  cloud: {
    sync: {
      pending: "Waiting for approval from another device",
      current: "this PC",
      approved: "The device was approved.",
      recovery: {
        description:
          "Create a one-time backup code for adding a device when no approved device is available. A new code invalidates the previous one.",
        useDescription:
          "If you cannot approve this PC from another device, enter the recovery code you saved earlier.",
        recovered: "Encrypted sync was recovered on this PC.",
      },
    },
    usage: {
      byok: {
        description:
          "Token counts are read from provider responses and stored only on this PC. No prompt or transcription is retained here.",
      },
    },
    signIn: {
      whyAccount:
        "An account keeps Pressay Pro on all your computers, Mac and PC, and syncs your settings. Local dictation works without one.",
    },
  },
  onboarding: {
    models: {
      "pressay/whisper-large": {
        description:
          "The most accurate Pressay preset, for PCs with plenty of memory or a recent graphics card.",
      },
    },
    permissions: {
      description:
        "Pressay only needs the microphone. Windows asks once; you can change it later in Settings › Privacy & security › Microphone.",
    },
  },
  settings: {
    general: {
      description:
        "Tune the gesture, microphone and feedback that make Pressay feel native on this PC.",
    },
    advanced: {
      description:
        "Control how Pressay starts, processes audio, inserts text and stores local data on this PC.",
    },
    postProcessing: {
      description:
        "Choose the intelligence used by transformation modes and see exactly when text can leave your PC.",
      privacy:
        "Keys stay encrypted for your Windows account. A remote route is used only by a mode that displays BYOK or Cloud.",
      api: { connection: { stored: "Key saved in Windows secure storage" } },
    },
    history: {
      description:
        "Search, revisit and export the text Pressay keeps encrypted on this PC.",
      loadError:
        "History is unavailable. Your files are preserved and dictation remains available. Sign in to the same Windows account, then retry. If the problem persists, contact support before modifying the database.",
    },
  },
  accessibility: {
    copiedDescription: "Press Ctrl+V to paste.",
  },
  errors: {
    codes: {
      keychain:
        "Pressay could not read its encrypted data for this Windows account. Sign in to the same Windows account and try again.",
      accountMismatch:
        "This PC is linked to another account. Sign out, then sign in again.",
    },
  },
  pressay: {
    sidebar: { searchShortcut: "Ctrl K" },
    routes: { local: { detail: "Nothing leaves this PC" } },
    profiles: {
      description:
        "Automatically apply a mode and output behavior for a specific Windows app.",
    },
  },
  signalOs: {
    onboarding: {
      welcome: {
        description:
          "Start with private transcription on your PC. No account, no Internet connection, no behavioural analytics.",
      },
      diagnostic: {
        title: "Built for this PC.",
        description:
          "Pressay checks only the hardware needed for private dictation. This diagnostic stays on your PC.",
        chip: "Processor",
        memory: "Memory",
        system: "Windows",
        limited:
          "You can continue, but this version of Windows is older than Windows 10 22H2, the supported minimum.",
      },
      firstDictation: {
        description:
          "Keep this field focused, hold your shortcut, speak, then release. The audio and text stay on this PC.",
      },
    },
    dashboard: {
      subtitle: "Your voice is transcribed on this PC by default.",
      privacyTitle: "Nothing leaves your PC",
      correctionDisclosure:
        "Your configured text provider processes the original and instruction. If it is remote, both leave this PC.",
    },
  },
};

const fr: Overrides = {
  cloud: {
    sync: {
      pending: "En attente de validation depuis un autre appareil",
      current: "ce PC",
      approved: "L’appareil a été autorisé.",
      recovery: {
        description:
          "Créez un code de secours à usage unique pour ajouter un appareil lorsqu’aucun appareil autorisé n’est disponible. Un nouveau code invalide le précédent.",
        useDescription:
          "Si vous ne pouvez pas autoriser ce PC depuis un autre appareil, saisissez le code de récupération enregistré auparavant.",
        recovered: "La synchronisation chiffrée a été récupérée sur ce PC.",
      },
    },
    usage: {
      byok: {
        description:
          "Les compteurs de tokens viennent des réponses du fournisseur et restent sur ce PC. Aucun prompt ni aucune transcription n’est enregistré ici.",
      },
    },
    signIn: {
      whyAccount:
        "Un compte permet de retrouver Pressay Pro sur tous vos ordinateurs, Mac et PC, et de synchroniser vos réglages. La dictée locale fonctionne sans compte.",
    },
  },
  onboarding: {
    models: {
      "pressay/whisper-large": {
        description:
          "Le preset Pressay le plus précis, pour les PC bien dotés en mémoire ou équipés d’une carte graphique récente.",
      },
    },
    permissions: {
      description:
        "Pressay n’a besoin que du micro. Windows le demande une fois ; vous pourrez le modifier dans Paramètres › Confidentialité et sécurité › Microphone.",
    },
  },
  settings: {
    general: {
      description:
        "Ajustez le geste, le microphone et les retours qui rendent Pressay naturel sur ce PC.",
    },
    advanced: {
      description:
        "Contrôlez le démarrage de Pressay, le traitement audio, l’insertion du texte et les données locales de ce PC.",
    },
    postProcessing: {
      description:
        "Choisissez l’intelligence utilisée par les modes de transformation et voyez précisément quand un texte peut quitter votre PC.",
      privacy:
        "Les clés restent chiffrées pour votre compte Windows. Une route distante n’est utilisée que par un mode affichant BYOK ou Cloud.",
      api: {
        connection: {
          stored: "Clé enregistrée dans le stockage sécurisé de Windows",
        },
      },
    },
    history: {
      description:
        "Recherchez, consultez et exportez les textes conservés chiffrés sur ce PC.",
      loadError:
        "L’historique est indisponible. Vos fichiers sont conservés et la dictée reste utilisable. Ouvrez la même session Windows, puis réessayez. Si le problème persiste, contactez le support avant de modifier la base.",
    },
  },
  accessibility: {
    copiedDescription: "Appuyez sur Ctrl+V pour coller.",
  },
  errors: {
    codes: {
      keychain:
        "Pressay n’a pas pu lire ses données chiffrées pour cette session Windows. Ouvrez la même session Windows puis réessayez.",
      accountMismatch:
        "Ce PC est lié à un autre compte. Déconnectez-vous puis reconnectez-vous.",
    },
  },
  pressay: {
    sidebar: { searchShortcut: "Ctrl K" },
    routes: { local: { detail: "Rien ne quitte ce PC" } },
    profiles: {
      description:
        "Applique automatiquement un mode et une sortie à une application Windows précise.",
    },
  },
  signalOs: {
    onboarding: {
      welcome: {
        description:
          "Commencez avec une transcription privée sur votre PC. Sans compte, sans Internet et sans analytics comportementales.",
      },
      diagnostic: {
        title: "Conçu pour ce PC.",
        description:
          "Pressay vérifie uniquement le matériel nécessaire à la dictée privée. Ce diagnostic reste sur votre PC.",
        chip: "Processeur",
        memory: "Mémoire",
        system: "Windows",
        limited:
          "Vous pouvez continuer, mais cette version de Windows est antérieure à Windows 10 22H2, le minimum pris en charge.",
      },
      firstDictation: {
        description:
          "Gardez ce champ sélectionné, maintenez votre raccourci, parlez puis relâchez. L’audio et le texte restent sur ce PC.",
      },
      personalization: { title: "Adaptez Pressay à votre PC." },
    },
    dashboard: {
      subtitle: "Votre voix est transcrite sur ce PC par défaut.",
      privacyTitle: "Rien ne quitte votre PC",
      correctionDisclosure:
        "Votre fournisseur de texte traite l’original et l’instruction. S’il est distant, les deux quittent ce PC.",
    },
  },
};

export const windowsOverrides: Record<string, Overrides> = { en, fr };
