import { test, expect } from "@playwright/test";

test.describe("Pressay App", () => {
  test("renders the standalone product shell without runtime errors", async ({
    page,
  }) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));

    const response = await page.goto("/");

    expect(response?.status()).toBe(200);
    await expect(page).toHaveTitle("Pressay");
    await expect(
      page.getByRole("heading", { name: "Ready when you are." }),
    ).toBeVisible();
    await expect(page.getByRole("main")).toContainText(
      "Nothing leaves your Mac",
    );
    await expect(
      page.getByRole("button", { name: "Correct with voice" }),
    ).toBeVisible();
    await expect(page.getByText("If it is remote")).toBeVisible();
    expect(errors).toEqual([]);
  });

  test("exposes an accessible, local-first navigation shell", async ({
    page,
  }) => {
    await page.goto("/");

    const navigation = page.getByRole("navigation", { name: "Primary" });
    await expect(navigation).toBeVisible();
    await expect(navigation.getByRole("button")).toHaveCount(7);
    await expect(
      navigation.getByRole("button", { name: "Home" }),
    ).toHaveAttribute("aria-current", "page");
    await expect(page.getByText("Local", { exact: true })).toHaveCount(2);
    await expect(page.getByText("Private by default")).toBeVisible();
  });

  test("exposes explicit modes and application profiles", async ({ page }) => {
    await page.goto("/");

    await page.getByRole("button", { name: "Modes" }).click();
    await expect(page.getByRole("heading", { name: "Modes" })).toBeVisible();
    await expect(
      page.getByText("Nothing leaves this Mac").first(),
    ).toBeVisible();
    await expect(page.getByText("Application profiles")).toBeVisible();

    await page.getByRole("button", { name: "Add profile" }).click();
    await expect(page.getByLabel("Profile language")).toBeVisible();
    await expect(page.getByLabel("Profile model")).toBeVisible();
    await expect(page.getByLabel("Profile microphone")).toBeVisible();
    await expect(
      page.getByText("Default language", { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText("Default model", { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText("Default microphone", { exact: true }),
    ).toBeVisible();

    await page.getByRole("button", { name: "New mode" }).click();
    await expect(page.getByLabel("Custom mode editor")).toBeVisible();
    await expect(page.getByText("Transformation instruction")).toHaveCount(0);
  });

  test("shows controlled exact and fuzzy dictionary entries", async ({
    page,
  }) => {
    await page.goto("/");

    await page.getByRole("button", { name: "Dictionary" }).click();
    await expect(
      page.getByRole("heading", { name: "Dictionary" }),
    ).toBeVisible();
    const entries = page.getByLabel("Dictionary entries");
    await expect(entries.getByText("Pressay", { exact: true })).toBeVisible();
    await expect(entries.getByText("exact", { exact: true })).toBeVisible();
    await expect(entries.getByText("fuzzy", { exact: true })).toBeVisible();

    await page.getByRole("button", { name: "Add term" }).click();
    await expect(page.getByLabel("Dictionary editor")).toBeVisible();
    await expect(page.getByLabel("Spoken or written term")).toBeVisible();
  });

  test("presents local-first onboarding before permissions", async ({
    page,
  }) => {
    await page.goto("/?screen=welcome");

    await expect(
      page.getByRole("heading", { name: "Your voice, without the trade-off." }),
    ).toBeVisible();
    await expect(page.getByText("Free · Offline · No account")).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Continue locally" }),
    ).toBeVisible();
    await expect(
      page.getByRole("list", { name: "Onboarding progress" }),
    ).toBeVisible();
  });
});
