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
    await expect(navigation.getByRole("button")).toHaveCount(10);
    await expect(
      navigation.getByRole("button", { name: "Home" }),
    ).toHaveAttribute("aria-current", "page");
    await expect(page.getByText("Local", { exact: true })).toHaveCount(3);
    await expect(page.getByText("Private by default")).toBeVisible();
    await expect(page.getByText("Beta · Pro preview")).toBeVisible();
  });

  test("exposes explicit modes and application profiles", async ({ page }) => {
    await page.goto("/");

    await page.getByRole("button", { name: "Modes" }).click();
    await expect(page.getByRole("heading", { name: "Modes" })).toBeVisible();
    await expect(
      page.getByText("Nothing leaves this Mac").first(),
    ).toBeVisible();
    await expect(page.getByText("Application profiles")).toBeVisible();
    await expect(
      page.getByRole("heading", { name: "Translation" }),
    ).toBeVisible();
    const translationCard = page
      .getByRole("article")
      .filter({ has: page.getByRole("heading", { name: "Translation" }) });
    await expect(
      translationCard.getByRole("button", { name: "Set up" }),
    ).toBeVisible();
    await expect(page.locator(".mode-card")).toHaveCount(12);
    await expect(page.getByRole("button", { name: "Import" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Export" })).toBeVisible();

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

    await translationCard.getByRole("button", { name: "Set up" }).click();
    await expect(
      page.getByRole("button", { name: /Providers/ }),
    ).toHaveAttribute("aria-current", "page");
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
    await expect(page.getByText("Offline", { exact: true })).toBeVisible();
    await expect(page.getByText("No account · No network")).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Continue locally" }),
    ).toBeVisible();
    await expect(
      page.getByRole("list", { name: "Onboarding progress" }),
    ).toBeVisible();
    await expect(
      page
        .getByRole("list", { name: "Onboarding progress" })
        .getByRole("listitem"),
    ).toHaveCount(3);
  });

  test("loads French on demand without bundling every catalogue at startup", async ({
    page,
  }) => {
    await page.goto("/?screen=welcome&lang=fr");

    await expect(page.locator("html")).toHaveAttribute("lang", "fr");
    await expect(
      page.getByRole("heading", { name: "Votre voix, sans compromis." }),
    ).toBeVisible();
    await expect(
      page.getByRole("list", { name: "Progression de l’onboarding" }),
    ).toBeVisible();
  });

  test("keeps onboarding readable in RTL and reduced-motion environments", async ({
    page,
  }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto("/?screen=welcome&lang=ar");

    await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
    await expect(page.locator("html")).toHaveAttribute("lang", "ar");
    await expect(page.locator(".onboarding-trust-card")).toBeVisible();
    const overflow = await page.evaluate(
      () =>
        document.documentElement.scrollWidth >
        document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);
    const motion = await page
      .locator(".onboarding-panel")
      .evaluate((element) => {
        const style = getComputedStyle(element);
        return {
          animation: style.animationDuration,
          transition: style.transitionDuration,
        };
      });
    expect(motion.animation).toBe("1e-05s");
    expect(motion.transition).toBe("1e-05s");
  });

  test("keeps every webview layer around the HUD transparent", async ({
    page,
  }) => {
    await page.goto("/src/overlay/index.html");

    const backgrounds = await page.evaluate(() =>
      [document.documentElement, document.body, document.getElementById("root")]
        .filter(
          (element): element is HTMLElement => element instanceof HTMLElement,
        )
        .map((element) => getComputedStyle(element).backgroundColor),
    );

    expect(backgrounds).toEqual([
      "rgba(0, 0, 0, 0)",
      "rgba(0, 0, 0, 0)",
      "rgba(0, 0, 0, 0)",
    ]);
  });
});
