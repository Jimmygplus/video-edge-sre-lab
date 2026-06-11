"""Locust load profile for video-origin.

Simulates viewer behaviour against the origin API:
- browse the catalogue (hot path)
- open a specific video + fetch its manifest
- a small fraction of requests hit the slow endpoint (tail-latency source)

Run headless, e.g.:
    python3 -m locust -f loadtest/locustfile.py --headless \
        -u 30 -r 5 -t 5m --host http://localhost:8080
"""

import random

from locust import HttpUser, between, task


class Viewer(HttpUser):
    wait_time = between(0.5, 2.0)

    @task(10)
    def browse_catalogue(self):
        self.client.get("/api/videos")

    @task(4)
    def open_video(self):
        vid = random.randint(1, 5)
        self.client.get(f"/api/videos/{vid}", name="/api/videos/{id}")

    @task(3)
    def fetch_manifest(self):
        vid = random.randint(1, 5)
        self.client.get(f"/api/video/manifest/{vid}", name="/api/video/manifest/{id}")

    @task(1)
    def slow_request(self):
        # tail-latency generator: 300-800ms server-side sleep
        ms = random.choice([300, 500, 800])
        self.client.get(f"/api/slow?ms={ms}", name="/api/slow")
