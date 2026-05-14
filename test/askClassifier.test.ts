import { describe, expect, it } from "vitest";
import { classifyAskQuestion } from "@/lib/askClassifier";

describe("ask classifier", () => {
  it("keeps general Iceland tour questions on the fast trip-context path", () => {
    expect(classifyAskQuestion("tell me about Iceland waterfalls")).toMatchObject({
      route: "fast_trip_context",
      useWebSearch: false
    });
  });

  it("uses live weather context for weather and wind questions", () => {
    expect(classifyAskQuestion("check the current wind near us")).toMatchObject({
      route: "live_weather",
      useWeather: true,
      useWebSearch: true
    });
  });

  it("uses safety feeds for road, eruption, and closure questions", () => {
    expect(classifyAskQuestion("are there any road closures or eruption alerts?")).toMatchObject({
      route: "live_safety",
      useSafety: true,
      useWebSearch: true
    });
  });
});
