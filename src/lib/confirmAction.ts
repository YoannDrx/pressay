import { ask } from "@tauri-apps/plugin-dialog";

export type ConfirmActionOptions = {
  title: string;
  message: string;
  confirmLabel: string;
  cancelLabel: string;
};

type AskDialog = typeof ask;

/**
 * Ask the user to confirm a destructive action through the native dialog.
 *
 * `window.confirm` must never be used: tauri-plugin-dialog replaces it with an
 * async function, so `if (!window.confirm(...))` tests a Promise and always
 * proceeds. This helper awaits the real answer and fails closed: only an
 * explicit `true` from the dialog allows the action.
 */
export async function confirmDestructiveAction(
  { title, message, confirmLabel, cancelLabel }: ConfirmActionOptions,
  dialog: AskDialog = ask,
): Promise<boolean> {
  try {
    const answer: unknown = await dialog(message, {
      title,
      kind: "warning",
      okLabel: confirmLabel,
      cancelLabel,
    });
    return answer === true;
  } catch (error) {
    console.error("Confirmation dialog failed:", error);
    return false;
  }
}
