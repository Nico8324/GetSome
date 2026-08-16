//
// The cases VideoMatcher is checked against. Run them with Tools/MatcherCheck/run.sh.
//
// Every case states an answer a person would agree with on sight. The "should not
// match" half is the important half: a missed duplicate leaves a feed as it was,
// while a wrong match hides a video and says nothing.
//

import Foundation

func v(_ site: String, _ title: String, _ seconds: Int, id: String = UUID().uuidString) -> Video {
    Video(id: VideoID(sourceID: site, itemID: id), rawTitle: title, duration: seconds)
}

struct Case { let name: String; let a: Video; let b: Video; let expected: Bool }

let cases: [Case] = [
    // --- should match -------------------------------------------------------
    Case(name: "same scene, punctuation and case differ",
         a: v("mat6tube", "Brunette with big ass takes anal in pov", 1630),
         b: v("xvideos", "BRUNETTE with big ass, takes anal in POV!", 1632), expected: true),
    Case(name: "same scene, one site pads with junk words",
         a: v("mat6tube", "My stepmother with a huge ass wakes me up", 720),
         b: v("xvideos", "HD PORN - stepmother with huge ass wakes me up (full video)", 722), expected: true),
    Case(name: "studio code, written differently",
         a: v("missav", "MXGS-1440 Ma tante Maki", 7439),
         b: v("xvideos", "mxgs1440 japanese aunt", 7440), expected: true),
    Case(name: "long film, rounding compounds",
         a: v("missav", "ROE-542 Dans la maison de mon enfance", 9834),
         b: v("mat6tube", "ROE 542 in the house of my childhood", 9870), expected: true),

    // --- should NOT match ---------------------------------------------------
    Case(name: "same site is never deduplicated",
         a: v("mat6tube", "Brunette with big ass takes anal in pov", 1630),
         b: v("mat6tube", "Brunette with big ass takes anal in pov", 1630), expected: false),
    Case(name: "generic titles that collide on duration",
         a: v("mat6tube", "Porn", 1877),
         b: v("xvideos", "Porn", 1877), expected: false),
    Case(name: "unrelated titles, identical duration",
         a: v("mat6tube", "Redhead nurse night shift surprise", 1500),
         b: v("xvideos", "Blonde teacher detention after class", 1500), expected: false),
    Case(name: "same title, durations far apart",
         a: v("mat6tube", "Brunette with big ass takes anal in pov", 1630),
         b: v("xvideos", "Brunette with big ass takes anal in pov", 300), expected: false),
    Case(name: "studio code shared by trailer and feature",
         a: v("missav", "MXGS-1440 Ma tante Maki", 7439),
         b: v("xvideos", "MXGS-1440 trailer", 180), expected: false),
    Case(name: "one side has no duration at all",
         a: v("mat6tube", "Brunette with big ass takes anal in pov", 0),
         b: v("xvideos", "Brunette with big ass takes anal in pov", 1630), expected: false),
    Case(name: "only junk words in common",
         a: v("mat6tube", "hot milf anal hardcore creampie", 1200),
         b: v("xvideos", "hot milf anal hardcore creampie", 1200), expected: false),
]

var failures = 0
for c in cases {
    let got = VideoMatcher.isSameVideo(c.a, c.b)
    let ok = got == c.expected
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(c.name)  (expected \(c.expected), got \(got))")
}

// Collapsing keeps the first copy and remembers the rest.
let feed = [
    v("mat6tube", "Brunette with big ass takes anal in pov", 1630, id: "a"),
    v("xvideos", "brunette with big ass takes anal in POV", 1631, id: "b"),
    v("missav", "Something else entirely here", 900, id: "c"),
]
let merged = VideoMatcher.deduplicated(feed)
print("\nmerged \(feed.count) -> \(merged.count)")
for m in merged { print("  \(m.sourceID)/\(m.itemID)  alternates: \(m.alternateIDs.map(\.sourceID))") }
let survivorOK = merged.count == 2 && merged[0].sourceID == "mat6tube"
    && merged[0].alternateIDs.map(\.sourceID) == ["xvideos"]
print(survivorOK ? "PASS  first copy survives and remembers the other" : "FAIL  survivor/alternates wrong")
if !survivorOK { failures += 1 }

print("\n\(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")")
