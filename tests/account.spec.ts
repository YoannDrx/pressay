import { test, expect } from "@playwright/test";

test.describe("Account production component with mocked native IPC", () => {
  for (const scenario of ["empty", "offline"]) {
    test(`restores purchases when the StoreKit catalogue is ${scenario}`, async ({
      page,
    }) => {
      const errors: string[] = [];
      page.on("pageerror", (error) => errors.push(error.message));
      await page.goto(`/tests/fixtures/account.html?scenario=${scenario}`);
      const restore = page.getByRole("button", { name: "Restore purchases" });
      await expect(restore).toBeVisible();
      await restore.click();
      await expect
        .poll(() =>
          page.evaluate(
            () => Reflect.get(window, "accountTestCalls") as string[],
          ),
        )
        .toContain("restore_app_store_purchases");
      await expect
        .poll(() =>
          page.evaluate(
            () => Reflect.get(window, "accountTestCalls") as string[],
          ),
        )
        .toContain("reconcile_app_store_purchases");
      await expect(restore).toBeEnabled();
      expect(errors).toEqual([]);
    });
  }

  test("keeps StoreKit controls out of the direct distribution", async ({
    page,
  }) => {
    await page.goto("/tests/fixtures/account.html?scenario=direct");
    await expect(page.getByText("synthetic@example.invalid")).toBeVisible();
    await expect
      .poll(() =>
        page.evaluate(
          () => Reflect.get(window, "accountTestCalls") as string[],
        ),
      )
      .toContain("get_app_store_products");
    await expect(
      page.getByRole("button", { name: "Restore purchases" }),
    ).toHaveCount(0);
  });
});

for (const enabled of [false, true]) {
  test(`StoreKit purchase follows the backend release gate (${enabled})`, async ({
    page,
  }) => {
    await page.goto(
      `/tests/fixtures/account.html?scenario=purchases-${enabled ? "enabled" : "gated"}`,
    );
    const subscribe = page.getByRole("button", {
      name: "Subscribe",
      exact: true,
    });
    if (enabled) await expect(subscribe).toBeEnabled();
    else await expect(subscribe).toBeDisabled();
    await expect(
      page.getByRole("button", { name: "Restore purchases" }),
    ).toBeEnabled();
  });
}
