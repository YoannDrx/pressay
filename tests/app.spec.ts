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
    expect(errors).toEqual([]);
  });

  test("exposes an accessible, local-first navigation shell", async ({
    page,
  }) => {
    await page.goto("/");

    const navigation = page.getByRole("navigation", { name: "Primary" });
    await expect(navigation).toBeVisible();
    await expect(navigation.getByRole("button")).toHaveCount(6);
    await expect(
      navigation.getByRole("button", { name: "Home" }),
    ).toHaveAttribute("aria-current", "page");
    await expect(page.getByText("Local", { exact: true })).toHaveCount(2);
    await expect(page.getByText("Private by default")).toBeVisible();
  });
});
