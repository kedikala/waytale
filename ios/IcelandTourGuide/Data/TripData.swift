import Foundation

enum TripData {
    static let defaultDayId = "2026-06-29"

    static let demoLocations: [DemoLocation] = [
        .init(id: "demo-seljalandsfoss", label: "Seljalandsfoss", dayId: "2026-06-29", latitude: 63.6156, longitude: -19.9886),
        .init(id: "demo-skogafoss", label: "Skógafoss", dayId: "2026-06-29", latitude: 63.5321, longitude: -19.5114),
        .init(id: "demo-reynisfjara", label: "Reynisfjara", dayId: "2026-06-29", latitude: 63.4044, longitude: -19.0450),
        .init(id: "demo-eldhraun", label: "Eldhraun", dayId: "2026-06-30", latitude: 63.7500, longitude: -18.2500),
        .init(id: "demo-jokulsarlon", label: "Jökulsárlón", dayId: "2026-06-30", latitude: 64.0473, longitude: -16.1791),
        .init(id: "demo-reykjanes", label: "Reykjanes Lava", dayId: "2026-07-02", latitude: 63.8890, longitude: -22.2730)
    ]

    static let itineraryStops: [ItineraryStop] = [
        .init(id: "thingvellir", dayId: "2026-06-28", time: "9:30 AM", title: "Þingvellir Rift Walk", description: "UNESCO rift valley and old parliament site.", latitude: 64.2559, longitude: -21.1295),
        .init(id: "reynisfjara", dayId: "2026-06-29", time: "6:00 PM", title: "Reynisfjara Black Sand Beach", description: "Basalt columns, black sand, and dangerous sneaker waves.", latitude: 63.4044, longitude: -19.0450),
        .init(id: "jokulsarlon", dayId: "2026-06-30", time: "4:00 PM", title: "Jökulsárlón + Diamond Beach", description: "Glacier lagoon and icebergs from Vatnajökull.", latitude: 64.0473, longitude: -16.1791),
        .init(id: "mulagljufur", dayId: "2026-07-01", time: "9:30 AM", title: "Múlagljúfur Canyon", description: "Hidden canyon hike with waterfalls and glacier views.", latitude: 63.9888, longitude: -16.3975),
        .init(id: "fagradalsfjall", dayId: "2026-07-02", time: "5:00 PM", title: "Fagradalsfjall / Sundhnúkur Lava Fields", description: "Recent Reykjanes lava fields with access dependent on official warnings.", latitude: 63.8890, longitude: -22.2730)
    ]

    static let driveLegs: [DriveLeg] = [
        .init(
            id: "d2-golden-circle",
            dayId: "2026-06-28",
            label: "Golden Circle",
            roadNumbers: ["36", "365", "37", "35"],
            corridor: [
                .init(latitude: 64.2559, longitude: -21.1295),
                .init(latitude: 64.2101, longitude: -20.7006),
                .init(latitude: 64.3138, longitude: -20.2995),
                .init(latitude: 64.3145, longitude: -20.1496),
                .init(latitude: 64.0418, longitude: -20.8865)
            ],
            summary: "Rift valleys, hot springs, major waterfalls, lake country, and volcanic craters."
        ),
        .init(
            id: "d3-south-coast",
            dayId: "2026-06-29",
            label: "Hella to Vík",
            roadNumbers: ["1", "218", "215"],
            corridor: [
                .init(latitude: 63.8354, longitude: -20.4002),
                .init(latitude: 63.6156, longitude: -19.9886),
                .init(latitude: 63.5321, longitude: -19.5114),
                .init(latitude: 63.3994, longitude: -19.1264),
                .init(latitude: 63.4044, longitude: -19.0450),
                .init(latitude: 63.4186, longitude: -19.0060)
            ],
            summary: "Waterfalls under glacier volcanoes, puffin cliffs, and the black-sand coast."
        ),
        .init(
            id: "d4-vik-smyrlabjorg",
            dayId: "2026-06-30",
            label: "Vík to Smyrlabjörg",
            roadNumbers: ["1", "206", "998"],
            corridor: [
                .init(latitude: 63.4186, longitude: -19.0060),
                .init(latitude: 63.7713, longitude: -18.1728),
                .init(latitude: 64.0275, longitude: -16.9752),
                .init(latitude: 64.0473, longitude: -16.1791),
                .init(latitude: 64.2166, longitude: -15.7196)
            ],
            summary: "Eldhraun lava, glacier outwash plains, Skaftafell, and Vatnajökull lagoons."
        ),
        .init(
            id: "d6-reykjanes",
            dayId: "2026-07-02",
            label: "Reykjanes Peninsula",
            roadNumbers: ["41", "42", "425", "427", "43"],
            corridor: [
                .init(latitude: 64.1466, longitude: -21.9426),
                .init(latitude: 63.9266, longitude: -21.9699),
                .init(latitude: 63.8958, longitude: -22.0518),
                .init(latitude: 63.8190, longitude: -22.6877),
                .init(latitude: 63.8890, longitude: -22.2730),
                .init(latitude: 63.9746, longitude: -22.5986)
            ],
            summary: "Volcanic peninsula with steam fields, rift zones, and recent eruption landscapes."
        )
    ]

    static let pois: [POI] = [
        .init(id: "thingvellir-rift", name: "Þingvellir Rift Zone", category: .history, latitude: 64.2559, longitude: -21.1295, radiusMeters: 3500, priority: 5, routeTags: ["36", "golden-circle"], narrationSeed: "Þingvellir is both geology and government: a rift valley where tectonic plates separate and Iceland's parliament first met in 930.", safetyNote: nil),
        .init(id: "laugarvatn", name: "Laugarvatn Lake Village", category: .town, latitude: 64.2100527, longitude: -20.7005841, radiusMeters: 3500, priority: 3, routeTags: ["37", "golden-circle"], narrationSeed: "Laugarvatn sits between the Golden Circle's major stops, with geothermal bathing traditions, lake views, and a useful pause between Þingvellir and the geyser area.", safetyNote: nil),
        .init(id: "bruarfoss-golden-circle", name: "Brúarfoss Blue Waterfall", category: .waterfall, latitude: 64.2642354, longitude: -20.5158725, radiusMeters: 3000, priority: 4, routeTags: ["37", "golden-circle"], narrationSeed: "Brúarfoss is the blue waterfall of the Brúará river, known for vivid glacial color and a quieter Golden Circle detour.", safetyNote: "Use the official access and respect private roads."),
        .init(id: "geysir-strokkur", name: "Geysir and Strokkur Geothermal Area", category: .geology, latitude: 64.3126964, longitude: -20.3007733, radiusMeters: 3500, priority: 5, routeTags: ["35", "golden-circle"], narrationSeed: "The Geysir geothermal area gave the world the word geyser, and Strokkur still erupts every few minutes beside steaming vents and mineral terraces.", safetyNote: "Stay behind ropes because boiling water and thin crust are serious hazards."),
        .init(id: "gullfoss", name: "Gullfoss Canyon Waterfall", category: .waterfall, latitude: 64.314452, longitude: -20.1495557, radiusMeters: 3500, priority: 5, routeTags: ["35", "golden-circle"], narrationSeed: "Gullfoss drops in two dramatic stages into a narrow Hvítá river canyon and is one of the signature stops of the Golden Circle.", safetyNote: "Paths can be icy or wet, and spray can reduce visibility."),
        .init(id: "kerid-crater", name: "Kerið Volcanic Crater", category: .volcano, latitude: 64.0417879, longitude: -20.886481, radiusMeters: 2500, priority: 4, routeTags: ["35", "golden-circle"], narrationSeed: "Kerið is a colorful volcanic crater lake with red scoria slopes and green-blue water, a compact reminder that the Golden Circle is volcanic country.", safetyNote: nil),
        .init(id: "urridafoss", name: "Urriðafoss on the Þjórsá", category: .waterfall, latitude: 63.9249027, longitude: -20.6719415, radiusMeters: 3500, priority: 4, routeTags: ["1", "south"], narrationSeed: "Urriðafoss is a broad, powerful waterfall on Þjórsá, Iceland's longest river, and makes an early South Coast story about water volume rather than height.", safetyNote: nil),
        .init(id: "hella-logistics", name: "Hella Road Trip Reset", category: .fuelLogistics, latitude: 63.8355038, longitude: -20.3987009, radiusMeters: 2500, priority: 3, routeTags: ["1", "south"], narrationSeed: "Hella is a practical South Coast reset point for fuel, food, and weather awareness before the road opens toward the glacier volcanoes and waterfall country.", safetyNote: "Check wind and road conditions before continuing east."),
        .init(id: "hvolsvollur-sagas", name: "Hvolsvöllur Saga Country", category: .history, latitude: 63.7508108, longitude: -20.223842, radiusMeters: 2500, priority: 3, routeTags: ["1", "south"], narrationSeed: "Hvolsvöllur sits in Njála saga country, where farms, rivers, and volcano views connect the drive to medieval Icelandic storytelling.", safetyNote: nil),
        .init(id: "gljufrabui", name: "Gljúfrabúi Hidden Waterfall", category: .waterfall, latitude: 63.6207562, longitude: -19.9863395, radiusMeters: 1800, priority: 4, routeTags: ["1", "south"], narrationSeed: "Gljúfrabúi is the hidden neighbor of Seljalandsfoss, tucked inside a narrow cliff opening where mist and echo make the waterfall feel enclosed.", safetyNote: "Expect wet rock and slick footing if you enter the cleft."),
        .init(id: "eyjafjallajokull", name: "Eyjafjallajökull", category: .volcano, latitude: 63.6300, longitude: -19.6200, radiusMeters: 12000, priority: 5, routeTags: ["1", "south"], narrationSeed: "Eyjafjallajökull is the glacier volcano famous for the 2010 eruption that disrupted European air travel.", safetyNote: nil),
        .init(id: "eyjafjoll-foothills", name: "Eyjafjöll Foothills", category: .viewpoint, latitude: 63.6277875, longitude: -19.5572795, radiusMeters: 9000, priority: 4, routeTags: ["1", "south"], narrationSeed: "The Eyjafjöll foothills are farming country under steep mountains and glacier ice, where waterfalls spill from old sea cliffs beside Route 1.", safetyNote: nil),
        .init(id: "seljalandsfoss-pass", name: "Seljalandsfoss Cliffs", category: .waterfall, latitude: 63.6156, longitude: -19.9886, radiusMeters: 2500, priority: 5, routeTags: ["1", "south"], narrationSeed: "Seljalandsfoss drops from a former sea cliff, and the undercut rock lets visitors walk behind the waterfall.", safetyNote: "Waterproof layers matter here."),
        .init(id: "skogar-coast", name: "Skógar and Skógafoss", category: .waterfall, latitude: 63.5321, longitude: -19.5114, radiusMeters: 3000, priority: 5, routeTags: ["1", "south"], narrationSeed: "Skógafoss is a clean curtain of water, but the bigger story continues upstream along the waterfall trail.", safetyNote: nil),
        .init(id: "kvernufoss", name: "Kvernufoss Gorge Waterfall", category: .waterfall, latitude: 63.5286852, longitude: -19.4805098, radiusMeters: 1800, priority: 4, routeTags: ["1", "south"], narrationSeed: "Kvernufoss is a quieter waterfall near Skógar, reached through a green gorge where the South Coast cliff line feels close and intimate.", safetyNote: nil),
        .init(id: "solheimajokull", name: "Sólheimajökull Glacier Tongue", category: .glacier, latitude: 63.5660204, longitude: -19.2955016, radiusMeters: 5000, priority: 5, routeTags: ["1", "south"], narrationSeed: "Sólheimajökull is an accessible outlet glacier of Mýrdalsjökull, showing dark volcanic ash bands, meltwater, and the retreating edge of Iceland's ice.", safetyNote: "Never walk onto glacier ice without proper gear and a qualified guide."),
        .init(id: "myrdalsjokull-katla", name: "Mýrdalsjökull and Katla", category: .volcano, latitude: 63.6299927, longitude: -19.0499745, radiusMeters: 18000, priority: 5, routeTags: ["1", "south"], narrationSeed: "Mýrdalsjökull hides Katla, one of Iceland's most powerful volcanoes, under a broad ice cap above the Vík area.", safetyNote: "Respect closures and official warnings around glacial rivers and volcanic hazards."),
        .init(id: "dyrholaey-puffins", name: "Dyrhólaey Puffin Cliffs", category: .wildlife, latitude: 63.3994, longitude: -19.1264, radiusMeters: 2800, priority: 5, routeTags: ["218", "south"], narrationSeed: "Dyrhólaey is a classic late-June puffin stop, with nesting birds on grassy sea cliffs and a natural rock arch below.", safetyNote: "Stay behind barriers and expect strong wind."),
        .init(id: "reynisfjara-sneaker-waves", name: "Reynisfjara Sneaker Wave Zone", category: .drivingSafety, latitude: 63.4044, longitude: -19.0450, radiusMeters: 2500, priority: 5, routeTags: ["215", "south"], narrationSeed: "Reynisfjara is visually stunning and genuinely dangerous because sneaker waves surge far beyond normal wave lines.", safetyNote: "Never turn your back on the ocean."),
        .init(id: "eldhraun", name: "Eldhraun Lava Field", category: .geology, latitude: 63.7500, longitude: -18.2500, radiusMeters: 14000, priority: 5, routeTags: ["1", "eastbound"], narrationSeed: "Eldhraun is the moss-covered lava field from the Laki eruption in the 1780s, one of the largest lava flows in historical time.", safetyNote: "Do not walk on fragile moss."),
        .init(id: "eldgja-laki-context", name: "Eldgjá and Laki Volcanic Country", category: .volcano, latitude: 64.070189, longitude: -18.2363084, radiusMeters: 22000, priority: 4, routeTags: ["1", "206", "eastbound"], narrationSeed: "The road east of Kirkjubæjarklaustur passes the wider volcanic story of Eldgjá and Laki, eruption systems that reshaped lava fields, climate, and Icelandic history.", safetyNote: "Highland roads to Laki and Eldgjá require the right vehicle and seasonal road checks."),
        .init(id: "fjadrargljufur", name: "Fjaðrárgljúfur Canyon", category: .geology, latitude: 63.7711975, longitude: -18.1714427, radiusMeters: 5000, priority: 5, routeTags: ["1", "206", "eastbound"], narrationSeed: "Fjaðrárgljúfur is a winding canyon cut by the Fjaðrá river, with steep mossy walls and fragile viewpoints above the water.", safetyNote: "Stay on marked paths because vegetation and cliff edges are vulnerable."),
        .init(id: "kirkjubaejarklaustur", name: "Kirkjubæjarklaustur", category: .town, latitude: 63.793065, longitude: -18.0418591, radiusMeters: 3000, priority: 3, routeTags: ["1", "eastbound", "westbound"], narrationSeed: "Kirkjubæjarklaustur is the main service village between Vík and Skaftafell, with monastic history, lava landscapes, and nearby canyon and waterfall detours.", safetyNote: "Use it as a fuel and weather check before the long southeast stretch."),
        .init(id: "skeidararsandur", name: "Skeiðarársandur Outwash Plain", category: .glacier, latitude: 63.9400, longitude: -17.3500, radiusMeters: 16000, priority: 5, routeTags: ["1", "eastbound"], narrationSeed: "Skeiðarársandur is a wide glacial outwash plain shaped by meltwater and sudden jökulhlaups.", safetyNote: nil),
        .init(id: "vatnajokull", name: "Vatnajökull Ice Cap", category: .glacier, latitude: 64.0500, longitude: -16.8000, radiusMeters: 20000, priority: 5, routeTags: ["1", "eastbound"], narrationSeed: "Vatnajökull dominates southeast Iceland and feeds many glacier tongues, lagoons, and outwash rivers along the road.", safetyNote: nil),
        .init(id: "skaftafell-svartifoss", name: "Skaftafell and Svartifoss", category: .glacier, latitude: 64.0164548, longitude: -16.966458, radiusMeters: 6500, priority: 5, routeTags: ["1", "998", "eastbound"], narrationSeed: "Skaftafell is a major Vatnajökull National Park base with glacier views, hiking trails, and Svartifoss framed by dark basalt columns.", safetyNote: "Weather can shift quickly near glacier outlets; choose hikes conservatively."),
        .init(id: "skeidara-bridge-monument", name: "Skeiðará Bridge Monument", category: .history, latitude: 63.9846389, longitude: -16.9593889, radiusMeters: 2500, priority: 4, routeTags: ["1", "eastbound"], narrationSeed: "The twisted Skeiðará bridge beams remember the 1996 glacial flood that tore through the outwash plain after volcanic activity under Vatnajökull.", safetyNote: nil),
        .init(id: "oraefi-hvannadalshnukur", name: "Öræfi and Hvannadalshnúkur Views", category: .viewpoint, latitude: 64.0141503, longitude: -16.6769602, radiusMeters: 16000, priority: 4, routeTags: ["1", "eastbound"], narrationSeed: "Öræfi is the district under Öræfajökull, where Hvannadalshnúkur rises as Iceland's highest summit above farms, glaciers, and flood-shaped plains.", safetyNote: nil),
        .init(id: "svinafellsjokull", name: "Svínafellsjökull Glacier", category: .glacier, latitude: 64.0227007, longitude: -16.8026575, radiusMeters: 6500, priority: 4, routeTags: ["1", "eastbound"], narrationSeed: "Svínafellsjökull is a dramatic glacier tongue with fractured blue ice and mountain walls, part of the glacier scenery east of Skaftafell.", safetyNote: "Do not enter glacier terrain without a guide."),
        .init(id: "fjallsarlon", name: "Fjallsárlón Glacier Lagoon", category: .glacier, latitude: 64.0178, longitude: -16.3625, radiusMeters: 3500, priority: 5, routeTags: ["1", "eastbound", "westbound"], narrationSeed: "Fjallsárlón is a quieter glacier lagoon west of Jökulsárlón, where icebergs float below the outlet glacier and the scale feels close.", safetyNote: "Keep clear of unstable lagoon edges and floating ice."),
        .init(id: "jokulsarlon-lagoon", name: "Jökulsárlón Glacier Lagoon", category: .glacier, latitude: 64.0473, longitude: -16.1791, radiusMeters: 3000, priority: 5, routeTags: ["1", "eastbound", "westbound"], narrationSeed: "Jökulsárlón is a young glacier lagoon where icebergs calve from Breiðamerkurjökull and drift toward Diamond Beach.", safetyNote: nil),
        .init(id: "diamond-beach", name: "Diamond Beach", category: .glacier, latitude: 64.0413253, longitude: -16.182552, radiusMeters: 2500, priority: 5, routeTags: ["1", "eastbound", "westbound"], narrationSeed: "Diamond Beach is the black sand shore where ice from Jökulsárlón washes into the surf and scatters like glass against volcanic sand.", safetyNote: "Stay back from surf and never climb on ice near waves."),
        .init(id: "vik-fuel", name: "Vík Fuel and Weather Check", category: .fuelLogistics, latitude: 63.4186, longitude: -19.0060, radiusMeters: 2500, priority: 4, routeTags: ["1", "westbound", "south"], narrationSeed: "Vík is the key south-coast reset point for fuel, food, weather checks, and pacing.", safetyNote: "Fill up before the long westbound leg."),
        .init(id: "kleifarvatn", name: "Kleifarvatn Lake", category: .geology, latitude: 63.926636, longitude: -21.9699203, radiusMeters: 6000, priority: 4, routeTags: ["42", "reykjanes"], narrationSeed: "Kleifarvatn is Reykjanes' largest lake, sitting in a stark volcanic basin where faulting, geothermal systems, and lava fields shape the road.", safetyNote: nil),
        .init(id: "seltun-krysuvik", name: "Seltún Krýsuvík Geothermal Area", category: .geology, latitude: 63.89575, longitude: -22.0517778, radiusMeters: 3500, priority: 5, routeTags: ["42", "reykjanes"], narrationSeed: "Seltún is a colorful Krýsuvík geothermal area with boiling mud pots, fumaroles, sulfur smell, and mineral-stained hillsides beside the road.", safetyNote: "Stay on boardwalks and marked paths; geothermal crust can be dangerously thin."),
        .init(id: "fagradalsfjall-lava", name: "Fagradalsfjall and Sundhnúkur Lava Fields", category: .volcano, latitude: 63.8890, longitude: -22.2730, radiusMeters: 6000, priority: 5, routeTags: ["43", "reykjanes"], narrationSeed: "This Reykjanes area has been central to recent eruptions, where lava fields, gas, and closures can change quickly.", safetyNote: "Official closures and gas warnings are hard limits."),
        .init(id: "brimketill", name: "Brimketill Lava Pool", category: .geology, latitude: 63.8191478, longitude: -22.6060115, radiusMeters: 2500, priority: 4, routeTags: ["425", "427", "reykjanes"], narrationSeed: "Brimketill is a wave-cut lava pool on the Reykjanes coast, where Atlantic surf shows how quickly volcanic rock becomes shoreline sculpture.", safetyNote: "Keep well back from waves and wet rock."),
        .init(id: "gunnuhver", name: "Gunnuhver Geothermal Area", category: .geology, latitude: 63.8194447, longitude: -22.6841797, radiusMeters: 3500, priority: 5, routeTags: ["425", "reykjanes"], narrationSeed: "Gunnuhver is a powerful mud-pool and steam-vent area on Reykjanes, mixing geothermal force with a local ghost story and the smell of sulfur.", safetyNote: "Use the viewing platforms and avoid steam plumes when wind shifts."),
        .init(id: "reykjanesviti", name: "Reykjanesviti Lighthouse and Cliffs", category: .viewpoint, latitude: 63.8156125, longitude: -22.7043669, radiusMeters: 3000, priority: 4, routeTags: ["425", "reykjanes"], narrationSeed: "Reykjanesviti stands near the edge of the peninsula above sea cliffs, geothermal ground, and the Mid-Atlantic Ridge landscape.", safetyNote: "Expect strong wind near cliff edges."),
        .init(id: "bridge-between-continents", name: "Bridge Between Continents", category: .geology, latitude: 63.8682955, longitude: -22.6755411, radiusMeters: 3000, priority: 4, routeTags: ["425", "reykjanes"], narrationSeed: "The Bridge Between Continents spans a fissure between the North American and Eurasian plates, making the rift zone visible at human scale.", safetyNote: nil),
        .init(id: "hafnaberg-cliffs", name: "Hafnaberg Sea Cliffs", category: .wildlife, latitude: 63.8808886, longitude: -22.7394125, radiusMeters: 3500, priority: 4, routeTags: ["425", "reykjanes"], narrationSeed: "Hafnaberg is a sea-cliff area on Reykjanes where nesting birds, lava edges, and open Atlantic exposure define the coastal landscape.", safetyNote: "Stay away from cliff edges, especially in wind.")
    ]
}
