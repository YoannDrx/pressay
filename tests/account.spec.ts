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

for (const answer of ["no", "yes"] as const) {
  test(`account deletion follows the dialog answer (${answer})`, async ({
    page,
  }) => {
    await page.goto(
      `/tests/fixtures/account.html?scenario=direct&dialog=${answer}`,
    );
    await page.getByRole("button", { name: "Delete account" }).click();
    const calls = () =>
      page.evaluate(() => Reflect.get(window, "accountTestCalls") as string[]);
    await expect.poll(calls).toContain("plugin:dialog|ask");
    if (answer === "yes")
      await expect.poll(calls).toContain("delete_cloud_account");
    else expect(await calls()).not.toContain("delete_cloud_account");
  });
}

const payloads = (page: import("@playwright/test").Page) =>
  page.evaluate(
    () =>
      Reflect.get(window, "accountTestPayloads") as Record<string, unknown>[],
  );

test("the paywall shows period, renewal terms and legal links", async ({
  page,
}) => {
  await page.goto("/tests/fixtures/account.html?scenario=purchases-enabled");
  await expect(page.getByTestId("subscription-price")).toHaveText("€5 / month");
  await expect(page.getByTestId("auto-renew-disclosure")).toContainText(
    "renews automatically",
  );
  await page.getByRole("button", { name: "Terms of Use (EULA)" }).click();
  await page.getByRole("button", { name: "Privacy Policy" }).click();
  await page.getByRole("button", { name: "Manage subscription" }).click();
  await expect
    .poll(async () => (await payloads(page)).map((entry) => entry.page))
    .toEqual(["terms", "privacy", "manage_subscription"]);
});

test("a pending purchase is shown as pending, not as an error", async ({
  page,
}) => {
  await page.goto("/tests/fixtures/account.html?scenario=purchases-enabled");
  await page.getByRole("button", { name: "Subscribe", exact: true }).click();
  await expect(
    page.getByRole("status").filter({ hasText: "awaiting approval" }),
  ).toBeVisible();
  await expect(page.getByRole("alert")).toHaveCount(0);
  await expect(page.getByText("storekit_pending")).toHaveCount(0);
});

test("sign-in offers Apple and Google equally plus other options", async ({
  page,
}) => {
  await page.goto("/tests/fixtures/account.html?scenario=signed-out");
  const apple = page.getByRole("button", { name: "Continue with Apple" });
  const google = page.getByRole("button", { name: "Continue with Google" });
  await expect(apple).toBeVisible();
  await expect(google).toBeVisible();
  await page.getByRole("button", { name: "Other options" }).click();
  await expect
    .poll(async () => (await payloads(page)).at(-1))
    .toEqual({ command: "begin_cloud_social_login", provider: null });
});

test("deleting with an active App Store subscription warns first", async ({
  page,
}) => {
  await page.goto(
    "/tests/fixtures/account.html?scenario=apple-subscription&dialog=yes",
  );
  await page.getByRole("button", { name: "Delete account" }).click();
  const warning = page.getByTestId("apple-subscription-warning");
  await expect(warning).toBeVisible();
  await warning
    .getByRole("button", { name: "Manage App Store subscriptions" })
    .click();
  await warning.getByRole("button", { name: "Delete anyway" }).click();
  await expect
    .poll(() => payloads(page))
    .toEqual([
      { command: "delete_cloud_account", acknowledgeAppleSubscription: false },
      { command: "open_external_page", page: "apple_subscriptions" },
      { command: "delete_cloud_account", acknowledgeAppleSubscription: true },
    ]);
  await expect(warning).toHaveCount(0);
});

test("the direct checkout opens the web pricing behind its gate", async ({
  page,
}) => {
  await page.goto("/tests/fixtures/account.html?scenario=direct-checkout");
  await page.getByRole("button", { name: "Upgrade to Pro" }).click();
  await expect
    .poll(async () => (await payloads(page)).at(-1))
    .toEqual({ command: "open_external_page", page: "direct_checkout" });
  const status = page.getByTestId("pro-upgrade-status");
  await expect(status).toContainText("Finish your purchase on press-say.app");
  // Still Free after the explicit check: explain instead of failing silently.
  await status
    .getByRole("button", { name: "I’ve finished my purchase" })
    .click();
  await expect(status).toContainText("Pro is not active yet");
});

test("finishing the web purchase unlocks Pro without a restart", async ({
  page,
}) => {
  await page.goto("/tests/fixtures/account.html?scenario=direct-checkout-paid");
  await expect(page.getByText("Free plan")).toBeVisible();
  await page.getByRole("button", { name: "Upgrade to Pro" }).click();
  const status = page.getByTestId("pro-upgrade-status");
  await status
    .getByRole("button", { name: "I’ve finished my purchase" })
    .click();
  await expect(status).toHaveCount(0);
  await expect(page.getByText("Pro plan")).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Upgrade to Pro" }),
  ).toHaveCount(0);
  await expect(
    page.getByRole("button", { name: "Manage billing" }),
  ).toBeVisible();
});

test("the direct checkout stays hidden while its release gate is closed", async ({
  page,
}) => {
  await page.goto("/tests/fixtures/account.html?scenario=direct");
  await expect(page.getByText("synthetic@example.invalid")).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Upgrade to Pro" }),
  ).toHaveCount(0);
});

for (const answer of ["no", "yes"] as const) {
  test(`a purchase from another Apple ID is linked only on confirmation (${answer})`, async ({
    page,
  }) => {
    await page.goto(
      `/tests/fixtures/account.html?scenario=purchases-link&dialog=${answer}`,
    );
    await page.getByRole("button", { name: "Restore purchases" }).click();
    const restores = async () =>
      (await payloads(page)).filter(
        (entry) => entry.command === "restore_app_store_purchases",
      );
    if (answer === "yes") {
      await expect.poll(restores).toEqual([
        { command: "restore_app_store_purchases", linkToCurrentAccount: false },
        { command: "restore_app_store_purchases", linkToCurrentAccount: true },
      ]);
      await expect(page.getByRole("alert")).toHaveCount(0);
    } else {
      await expect(page.getByRole("alert")).toContainText(
        "not linked to this Pressay account",
      );
      expect(await restores()).toEqual([
        { command: "restore_app_store_purchases", linkToCurrentAccount: false },
      ]);
    }
  });
}
