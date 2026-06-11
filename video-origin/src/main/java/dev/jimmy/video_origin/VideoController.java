package dev.jimmy.video_origin;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.atomic.AtomicLong;

@RestController
@RequestMapping("/api")
public class VideoController {

    private final AtomicLong requestCount = new AtomicLong();

    private static final List<Map<String, Object>> VIDEOS = List.of(
            Map.of("id", 1, "title", "Sydney Harbour Drone 4K", "durationSec", 213, "codec", "h265"),
            Map.of("id", 2, "title", "Bondi Surf Cam Highlights", "durationSec", 95,  "codec", "h264"),
            Map.of("id", 3, "title", "Blue Mountains Timelapse", "durationSec", 187, "codec", "av1"),
            Map.of("id", 4, "title", "CBD Night Walk", "durationSec", 642, "codec", "h264"),
            Map.of("id", 5, "title", "Koala Cam Live Replay", "durationSec", 311, "codec", "h265")
    );

    /**
     * List all videos — the "hot path" for load testing.
     * FAILURE_RATE env (0.0-1.0) injects 5xx on this path: simulates a bad release.
     */
    @GetMapping("/videos")
    public ResponseEntity<List<Map<String, Object>>> videos() {
        requestCount.incrementAndGet();
        double failureRate = Double.parseDouble(System.getenv().getOrDefault("FAILURE_RATE", "0"));
        if (failureRate > 0 && ThreadLocalRandom.current().nextDouble() < failureRate) {
            return ResponseEntity.internalServerError().build();
        }
        return ResponseEntity.ok(VIDEOS);
    }

    /** Single video metadata, 404 on unknown id. */
    @GetMapping("/videos/{id}")
    public ResponseEntity<Map<String, Object>> video(@PathVariable int id) {
        return VIDEOS.stream()
                .filter(v -> (int) v.get("id") == id)
                .findFirst()
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    /** Simulated manifest endpoint — small CPU + payload. */
    @GetMapping("/video/manifest/{id}")
    public Map<String, Object> manifest(@PathVariable int id) {
        return Map.of(
                "videoId", id,
                "protocol", "HLS",
                "renditions", List.of("1080p", "720p", "480p"),
                "segmentSec", 6
        );
    }

    /** Incident lever 1: artificial latency (default 2000ms, override with ?ms=). */
    @GetMapping("/slow")
    public Map<String, Object> slow(@RequestParam(defaultValue = "2000") long ms) throws InterruptedException {
        Thread.sleep(ms);
        return Map.of("sleptMs", ms);
    }

    /** Incident lever 2: probabilistic 5xx (default 100%, override with ?rate=0.3). */
    @GetMapping("/error")
    public ResponseEntity<Map<String, Object>> error(@RequestParam(defaultValue = "1.0") double rate) {
        if (ThreadLocalRandom.current().nextDouble() < rate) {
            return ResponseEntity.internalServerError()
                    .body(Map.of("error", "simulated upstream failure"));
        }
        return ResponseEntity.ok(Map.of("ok", true));
    }

    /** Incident lever 3: memory hog — allocates and retains ~mb of heap per call (OOM drill). */
    private static final List<byte[]> RETAINED = new java.util.ArrayList<>();
    @GetMapping("/hog")
    public Map<String, Object> hog(@RequestParam(defaultValue = "50") int mb) {
        RETAINED.add(new byte[mb * 1024 * 1024]);
        return Map.of("retainedBlocks", RETAINED.size(), "addedMb", mb);
    }
}
