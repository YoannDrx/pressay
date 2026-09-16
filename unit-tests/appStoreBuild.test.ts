import { describe, expect, test } from "bun:test";
import { checkAppStoreBuild } from "../scripts/check-app-store-build";

describe("Mac App Store build numbering", () => {
  test("the first CI run cannot regress behind uploads from older versions", () => {
    expect(() => checkAppStoreBuild("1.1", "12001")).toThrow();
    expect(() => checkAppStoreBuild("2.0.4", "12001")).toThrow();
    expect(() => checkAppStoreBuild("2.0.5", "2.0.3")).toThrow();
    expect(() => checkAppStoreBuild("12002", "12001")).not.toThrow();
  });

  test("a rerun must receive a new build number after an upload", () => {
    expect(() => checkAppStoreBuild("12002", "12002")).toThrow();
    expect(() => checkAppStoreBuild("12003", "12002")).not.toThrow();
  });

  test("compares components numerically and across public versions", () => {
    expect(() => checkAppStoreBuild("12002.0.10", "12002.0.9")).not.toThrow();
    expect(() => checkAppStoreBuild("12002.0.9", "12002.0.10")).toThrow();
    expect(() => checkAppStoreBuild("12003", "12002.99.99")).not.toThrow();
    expect(() => checkAppStoreBuild("12002.1", "12003.0.0")).toThrow();
    expect(() => checkAppStoreBuild("12003.0.0", "12003")).toThrow();
    expect(() => checkAppStoreBuild("12003.1.0", "12003.1")).toThrow();
    expect(() => checkAppStoreBuild("12003.100.0", "12003.99.0")).not.toThrow();
  });

  test("does not round large integer components during comparison", () => {
    expect(() =>
      checkAppStoreBuild("12002.9007199254740993", "12002.9007199254740992"),
    ).not.toThrow();
  });

  test("rejects missing, development, ambiguous and unsafe input", () => {
    for (const value of [
      "",
      "0",
      "12002-beta.1",
      "12002.0.0.1",
      "012002",
      "12002.00.5",
      "-1",
      "12003\n",
      "12003; exit 0",
      "$(id)",
    ]) {
      expect(() => checkAppStoreBuild(value, "12001")).toThrow();
      expect(() => checkAppStoreBuild("12003", value)).toThrow();
    }
    expect(() => checkAppStoreBuild("12002", "12000")).toThrow();
  });
});
