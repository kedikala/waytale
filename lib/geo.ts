import { driveLegs, itineraryStops, tripDays } from "@/data/itinerary";
import { curatedPois } from "@/data/pois";
import { richPoiNarration, richStopNarration, routeNarration } from "@/lib/narration";
import type { Callout, DriveLeg, GuidePoi, ItineraryStop, LatLng, LiveAlert } from "@/lib/types";

const EARTH_RADIUS_M = 6371000;

export function toRad(value: number) {
  return (value * Math.PI) / 180;
}

export function distanceMeters(a: LatLng, b: LatLng) {
  const dLat = toRad(b.lat - a.lat);
  const dLon = toRad(b.lon - a.lon);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

function projectMeters(point: LatLng, origin: LatLng) {
  const x = toRad(point.lon - origin.lon) * EARTH_RADIUS_M * Math.cos(toRad(origin.lat));
  const y = toRad(point.lat - origin.lat) * EARTH_RADIUS_M;
  return { x, y };
}

export function distanceToSegmentMeters(point: LatLng, start: LatLng, end: LatLng) {
  const p = projectMeters(point, start);
  const e = projectMeters(end, start);
  const len2 = e.x * e.x + e.y * e.y;
  if (len2 === 0) return distanceMeters(point, start);
  const t = Math.max(0, Math.min(1, (p.x * e.x + p.y * e.y) / len2));
  const closest = { x: e.x * t, y: e.y * t };
  return Math.hypot(p.x - closest.x, p.y - closest.y);
}

export function distanceToPolylineMeters(point: LatLng, line: LatLng[]) {
  if (line.length === 0) return Number.POSITIVE_INFINITY;
  if (line.length === 1) return distanceMeters(point, line[0]);
  return Math.min(
    ...line.slice(0, -1).map((segmentStart, index) =>
      distanceToSegmentMeters(point, segmentStart, line[index + 1])
    )
  );
}

export function getDefaultDayId(now = new Date()) {
  const iso = now.toISOString().slice(0, 10);
  return tripDays.some((day) => day.id === iso) ? iso : "2026-06-29";
}

export function stopsForDay(dayId: string) {
  return itineraryStops.filter((stop) => stop.date === dayId);
}

export function findNearestStop(position?: LatLng, dayId?: string) {
  if (!position) return undefined;
  const candidates = dayId ? stopsForDay(dayId) : itineraryStops;
  return candidates
    .filter((stop) => stop.coordinates)
    .map((stop) => ({ stop, distanceM: distanceMeters(position, stop.coordinates!) }))
    .sort((a, b) => a.distanceM - b.distanceM)[0];
}

export function findNextStop(dayId: string, now = new Date()) {
  const todayStops = stopsForDay(dayId);
  if (dayId !== now.toISOString().slice(0, 10)) return todayStops[0];
  const minutes = now.getHours() * 60 + now.getMinutes();
  return todayStops.find((stop) => parseStopMinutes(stop.time) >= minutes) ?? todayStops.at(-1);
}

export function parseStopMinutes(time: string) {
  const match = time.match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
  if (!match) return Number.POSITIVE_INFINITY;
  let hours = Number(match[1]);
  const minutes = Number(match[2]);
  const meridiem = match[3].toUpperCase();
  if (meridiem === "PM" && hours !== 12) hours += 12;
  if (meridiem === "AM" && hours === 12) hours = 0;
  return hours * 60 + minutes;
}

export function findActiveLeg(position?: LatLng, dayId?: string) {
  if (!position) return undefined;
  const candidates = dayId ? driveLegs.filter((leg) => leg.dayId === dayId) : driveLegs;
  const nearest = candidates
    .map((leg) => ({ leg, distanceM: distanceToPolylineMeters(position, leg.corridor) }))
    .sort((a, b) => a.distanceM - b.distanceM)[0];
  return nearest && nearest.distanceM <= 7000 ? nearest.leg : undefined;
}

export function getNearbyPois(position?: LatLng, activeLeg?: DriveLeg, limit = 5) {
  if (!position) return [];
  const activeRoads = new Set(activeLeg?.roadNumbers ?? []);
  const routeBoost = new Set([activeLeg?.id, activeLeg?.dayId, ...(activeLeg?.roadNumbers ?? [])].filter(Boolean));
  return curatedPois
    .map((poi) => {
      const distanceM = distanceMeters(position, poi.coordinates);
      const onRoute =
        poi.routeTags.some((tag) => routeBoost.has(tag)) ||
        poi.routeTags.some((tag) => activeRoads.has(tag));
      const within = distanceM <= poi.radiusM || (onRoute && distanceM <= poi.radiusM * 1.6);
      const score = poi.priority * 1000 + (onRoute ? 800 : 0) - distanceM / 20;
      return { poi, distanceM, within, score };
    })
    .filter((entry) => entry.within)
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map((entry) => entry.poi);
}

export function buildCallouts(args: {
  position?: LatLng;
  dayId: string;
  alerts?: LiveAlert[];
  spokenIds?: Set<string>;
  now?: Date;
}) {
  const { position, dayId, alerts = [], spokenIds = new Set<string>() } = args;
  const callouts: Callout[] = [];
  const activeLeg = findActiveLeg(position, dayId);

  for (const alert of alerts) {
    if (alert.severity === "critical" || alert.severity === "warning") {
      callouts.push({
        id: `alert:${alert.id}`,
        kind: "alert",
        priority: alert.severity === "critical" ? 100 : 90,
        title: alert.title,
        text: `${alert.source} ${alert.severity}: ${alert.summary}`,
        sourceId: alert.id
      });
    }
  }

  const nearest = findNearestStop(position, dayId);
  if (nearest?.stop.coordinates) {
    const threshold = nearest.stop.radiusM ?? (nearest.stop.category === "Drive" ? 800 : 300);
    if (nearest.distanceM <= threshold) {
      callouts.push({
        id: `stop:${nearest.stop.id}`,
        kind: "stop",
        priority: nearest.stop.category === "Critical" ? 80 : 65,
        title: nearest.stop.title,
        text: richStopNarration(nearest.stop),
        distanceM: Math.round(nearest.distanceM),
        sourceId: nearest.stop.id
      });
    }
  }

  for (const poi of getNearbyPois(position, activeLeg, 4)) {
    callouts.push({
      id: `poi:${poi.id}`,
      kind: "poi",
      priority: poi.priority * 10,
      title: poi.name,
      text: richPoiNarration(poi),
      distanceM: position ? Math.round(distanceMeters(position, poi.coordinates)) : undefined,
      sourceId: poi.id
    });
  }

  if (activeLeg) {
    callouts.push({
      id: `route:${activeLeg.id}`,
      kind: "route",
      priority: 42,
      title: activeLeg.label,
      text: routeNarration(activeLeg),
      distanceM: position ? Math.round(distanceToPolylineMeters(position, activeLeg.corridor)) : undefined,
      sourceId: activeLeg.id
    });
  }

  return callouts
    .filter((callout) => !spokenIds.has(callout.id))
    .sort((a, b) => b.priority - a.priority || (a.distanceM ?? 0) - (b.distanceM ?? 0));
}

export function stopNarration(stop: ItineraryStop) {
  const tip = stop.proTip ? ` Tip: ${stop.proTip}` : "";
  return `${stop.title}. ${stop.description}${tip}`;
}

export function summarizeContext(position?: LatLng, dayId = getDefaultDayId(), alerts: LiveAlert[] = []) {
  const nearestEntry = findNearestStop(position, dayId);
  const activeLeg = findActiveLeg(position, dayId);
  return {
    position,
    activeDayId: dayId,
    nearestStop: nearestEntry?.stop,
    nearestStopDistanceM: nearestEntry ? Math.round(nearestEntry.distanceM) : undefined,
    nextStop: findNextStop(dayId),
    activeLeg,
    nearbyPois: getNearbyPois(position, activeLeg),
    alerts
  };
}
