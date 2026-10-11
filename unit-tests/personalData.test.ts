import { describe, expect, test } from "bun:test";
import { findPersonalData } from "../scripts/check-personal-data";

// Synthetic values are assembled at runtime so this file passes the scan.
const at = "@";

describe("personal data scan", () => {
  test("flags a webmail address, a mobile number and a home directory", () => {
    const text = [
      `contact: someone${at}gmail.com`,
      `phone: +33${"6"}12345678`,
      `phone: 0${"7"} 12 34 56 78`,
      `archive: /Users/${"owner"}/Projects/app.xcarchive`,
    ].join("\n");
    expect(findPersonalData("doc.md", text).map((entry) => entry.kind)).toEqual(
      [
        "personal webmail address",
        "French mobile phone number",
        "French mobile phone number",
        "personal home directory",
      ],
    );
  });

  test("accepts placeholders, product addresses and test fixtures", () => {
    const text = [
      "contact: <owner email>",
      `support: support${at}press-say.app`,
      'verifier = "synthetic-pkce-verifier-0123456789"',
      'Path::new("/Users/someone/Library/LaunchAgents")',
    ].join("\n");
    expect(findPersonalData("doc.md", text)).toEqual([]);
  });
});
