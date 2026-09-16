import { expect, test } from "@playwright/test";

test("history retries a recoverable storage failure", async ({ page }) => {
  await page.goto("/tests/fixtures/history.html?scenario=recovery");
  await expect(
    page.getByText("initial transcript", { exact: true }),
  ).toHaveCount(0);
  await page.getByRole("button", { name: "Retry", exact: true }).click();
  await expect(
    page.getByText("initial transcript", { exact: true }),
  ).toBeVisible();
});

test("history searches past an empty bounded page", async ({ page }) => {
  await page.goto("/tests/fixtures/history.html");
  await expect(
    page.getByText("initial transcript", { exact: true }),
  ).toBeVisible();
  await page.getByRole("textbox").fill("needle");
  await expect(
    page.getByText("needle transcript", { exact: true }),
  ).toBeVisible();
  const calls = await page.evaluate(() =>
    Reflect.get(window, "historyTestCalls"),
  );
  expect(calls).toContainEqual({
    command: "search_history_entries",
    args: { cursor: 100, query: "needle", filter: "all" },
  });
  expect(
    calls
      .filter(
        (call: { command: string; args: { limit?: number } }) =>
          call.command === "get_history_entries",
      )
      .every((call: { args: { limit: number } }) => call.args.limit === 30),
  ).toBe(true);
});

test("history discards a slow response for a previous search", async ({
  page,
}) => {
  await page.goto("/tests/fixtures/history.html");
  await expect(
    page.getByText("initial transcript", { exact: true }),
  ).toBeVisible();
  await page.getByRole("textbox").fill("old");
  await expect
    .poll(() =>
      page.evaluate(() =>
        Reflect.get(window, "historyTestCalls").some(
          (call: { command: string; args: { query?: string } }) =>
            call.command === "search_history_entries" &&
            call.args.query === "old",
        ),
      ),
    )
    .toBe(true);
  await page.getByRole("textbox").fill("new");
  await expect(page.getByText("new result", { exact: true })).toBeVisible();
  await page.waitForTimeout(800);
  await expect(page.getByText("new result", { exact: true })).toBeVisible();
  await expect(page.getByText("old result", { exact: true })).toHaveCount(0);
});
