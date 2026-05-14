import { describe, expect, it } from "vitest";

describe("official feed API contract", () => {
  it("does not expose OPENAI_API_KEY in client-visible env example", async () => {
    const text = await import("node:fs/promises").then((fs) => fs.readFile(".env.example", "utf8"));
    expect(text).toContain("OPENAI_API_KEY=");
    expect(text).toContain("OPENAI_API_KEY=your-openai-api-key");
  });
});
