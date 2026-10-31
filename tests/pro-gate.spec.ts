import { test, expect, type Page } from "@playwright/test";

const read = (page: Page, key: string) =>
  page.evaluate((name) => Reflect.get(window, name) as unknown[], key);

test.describe("Pro gate upgrade path", () => {
  test("a Direct build opens the web pricing and unlocks on return", async ({
    page,
  }) => {
    await page.goto("/tests/fixtures/pro-gate.html?build=direct&paid=yes");
    const gate = page.getByRole("note");
    await expect(gate).toContainText("Upgrade on press-say.app");
    await gate.getByRole("button", { name: "Upgrade to Pro" }).click();
    await expect
      .poll(() => read(page, "gateTestPayloads"))
      .toEqual([{ command: "open_external_page", page: "direct_checkout" }]);
    await expect(page.getByTestId("pro-upgrade-status")).toBeVisible();
    // Coming back to the window re-reads the entitlement: no restart needed.
    await page.evaluate(() => window.dispatchEvent(new Event("focus")));
    await expect(page.getByRole("note")).toHaveCount(0);
  });

  test("the explicit check re-reads the entitlement", async ({ page }) => {
    await page.goto("/tests/fixtures/pro-gate.html?build=direct&paid=yes");
    await page.getByRole("button", { name: "Upgrade to Pro" }).click();
    await page
      .getByRole("button", { name: "I’ve finished my purchase" })
      .click();
    await expect(page.getByRole("note")).toHaveCount(0);
  });

  test("a Direct build without an account signs in first", async ({ page }) => {
    await page.goto(
      "/tests/fixtures/pro-gate.html?build=direct&account=signed-out",
    );
    await page.getByRole("button", { name: "Upgrade to Pro" }).click();
    await expect
      .poll(() => read(page, "gateTestNavigations"))
      .toEqual(["account"]);
    expect(await read(page, "gateTestPayloads")).toEqual([]);
  });

  test("the App Store build never offers the web purchase", async ({
    page,
  }) => {
    await page.goto("/tests/fixtures/pro-gate.html?build=store");
    const gate = page.getByRole("note");
    await expect(gate).toContainText("This feature is part of Pressay Pro.");
    await expect(gate).not.toContainText("press-say.app");
    await expect(
      page.getByRole("button", { name: "Upgrade to Pro" }),
    ).toHaveCount(0);
    await page.getByRole("button", { name: "See Pro" }).click();
    await expect
      .poll(() => read(page, "gateTestNavigations"))
      .toEqual(["account"]);
    expect(await read(page, "gateTestPayloads")).toEqual([]);
    await expect(page.getByTestId("pro-upgrade-status")).toHaveCount(0);
  });
});
