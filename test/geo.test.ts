import { describe, expect, it } from "vitest";
import { buildCallouts, distanceMeters, findActiveLeg, findNearestStop, getNearbyPois } from "@/lib/geo";

describe("GPS tour guide logic", () => {
  it("matches Reynisfjara as the nearest critical itinerary stop", () => {
    const result = findNearestStop({ lat: 63.4042, lon: -19.046 }, "2026-06-29");
    expect(result?.stop.id).toBe("reynisfjara");
    expect(result?.distanceM ?? 9999).toBeLessThan(250);
  });

  it("matches the south coast drive corridor near Route 1", () => {
    const leg = findActiveLeg({ lat: 63.53, lon: -19.51 }, "2026-06-29");
    expect(leg?.id).toBe("d3-south-coast");
  });

  it("prioritizes critical alerts over POIs and stops", () => {
    const callouts = buildCallouts({
      position: { lat: 63.4042, lon: -19.046 },
      dayId: "2026-06-29",
      alerts: [
        {
          id: "red-beach",
          source: "SafeTravel",
          severity: "critical",
          title: "Reynisfjara closed",
          summary: "Red light active. Do not enter the beach."
        }
      ]
    });
    expect(callouts[0].kind).toBe("alert");
    expect(callouts[0].title).toBe("Reynisfjara closed");
  });

  it("suppresses already spoken callouts", () => {
    const first = buildCallouts({
      position: { lat: 64.2559, lon: -21.1295 },
      dayId: "2026-06-28"
    });
    const spokenIds = new Set(first.slice(0, 2).map((callout) => callout.id));
    const second = buildCallouts({
      position: { lat: 64.2559, lon: -21.1295 },
      dayId: "2026-06-28",
      spokenIds
    });
    expect(second.some((callout) => spokenIds.has(callout.id))).toBe(false);
  });

  it("finds high-priority curated POIs near Jökulsárlón", () => {
    const pois = getNearbyPois({ lat: 64.0473, lon: -16.1791 }, undefined, 5);
    expect(pois.some((poi) => poi.id === "jokulsarlon-lagoon")).toBe(true);
  });

  it("calculates realistic distances", () => {
    expect(distanceMeters({ lat: 64.1466, lon: -21.9426 }, { lat: 64.1466, lon: -21.9426 })).toBe(0);
    expect(distanceMeters({ lat: 64.1466, lon: -21.9426 }, { lat: 63.985, lon: -22.6056 })).toBeGreaterThan(30000);
  });
});
