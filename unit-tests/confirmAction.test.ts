import { describe, expect, test } from "bun:test";
import { confirmDestructiveAction } from "../src/lib/confirmAction";

const options = {
  title: "Delete",
  message: "Delete everything?",
  confirmLabel: "Delete",
  cancelLabel: "Cancel",
};

type Dialog = NonNullable<Parameters<typeof confirmDestructiveAction>[1]>;

describe("destructive confirmations", () => {
  test("only an explicit yes allows the action", async () => {
    const yes = (async () => true) as Dialog;
    const no = (async () => false) as Dialog;
    expect(await confirmDestructiveAction(options, yes)).toBe(true);
    expect(await confirmDestructiveAction(options, no)).toBe(false);
  });

  test("a dialog failure or a non-boolean answer fails closed", async () => {
    const failing = (async () => {
      throw new Error("dialog unavailable");
    }) as Dialog;
    const truthy = (async () => "yes") as unknown as Dialog;
    expect(await confirmDestructiveAction(options, failing)).toBe(false);
    expect(await confirmDestructiveAction(options, truthy)).toBe(false);
  });

  test("passes a warning dialog with translated labels", async () => {
    let received: unknown;
    const spy = (async (_message: string, dialogOptions: unknown) => {
      received = dialogOptions;
      return false;
    }) as Dialog;
    await confirmDestructiveAction(options, spy);
    expect(received).toEqual({
      title: "Delete",
      kind: "warning",
      okLabel: "Delete",
      cancelLabel: "Cancel",
    });
  });
});
