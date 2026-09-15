import { describe, expect, test } from "bun:test";
import { checkAppStoreBuild } from "../scripts/check-app-store-build";

describe("Mac App Store build numbering", () => {
  test("the first CI run cannot regress behind manual uploads", () => {
    expect(() => checkAppStoreBuild("1.1", "2.0.3")).toThrow();
    expect(() => checkAppStoreBuild("2.0.4", "2.0.3")).toThrow();
    expect(() => checkAppStoreBuild("2.0.5", "2.0.3")).not.toThrow();
  });

  test("a rerun must receive a new build number after an upload", () => {
    expect(() => checkAppStoreBuild("2.0.5", "2.0.5")).toThrow();
    expect(() => checkAppStoreBuild("2.0.6", "2.0.5")).not.toThrow();
  });

  test("compares components numerically and across public versions", () => {
    expect(() => checkAppStoreBuild("2.0.10", "2.0.9")).not.toThrow();
    expect(() => checkAppStoreBuild("2.0.9", "2.0.10")).toThrow();
    expect(() => checkAppStoreBuild("3", "2.99.99")).not.toThrow();
    expect(() => checkAppStoreBuild("2.1", "3.0.0")).toThrow();
    expect(() => checkAppStoreBuild("3.0.0", "3")).toThrow();
    expect(() => checkAppStoreBuild("3.1.0", "3.1")).toThrow();
  });

  test("rejects missing, development, ambiguous and unsafe input", () => {
    for (const value of [
      "",
      "0",
      "2.0.5-beta.1",
      "2.0.5.1",
      "02.0.5",
      "2.00.5",
      "2.100.0",
      "10000.0.0",
      "-1",
      "3\n",
      "3; exit 0",
      "$(id)",
    ]) {
      expect(() => checkAppStoreBuild(value, "2.0.3")).toThrow();
      expect(() => checkAppStoreBuild("3.0.0", value)).toThrow();
    }
    expect(() => checkAppStoreBuild("2.0.5", "1.0.0")).toThrow();
  });
});
