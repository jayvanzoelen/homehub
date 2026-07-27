(function () {
  var cfg = window.HOMEHUB_SECURITY || {};
  var video = document.getElementById("guard-video");
  var canvas = document.getElementById("guard-canvas");
  var diffCanvas = document.getElementById("diff-canvas");
  var statusEl = document.getElementById("guard-status");
  var armBtn = document.getElementById("arm-btn");
  var pinInput = document.getElementById("security-pin");

  var armed = !!cfg.armed;
  var stream = null;
  var previous = null;
  var lastSent = 0;
  var threshold = Number(cfg.motionThreshold || 28);
  var cooldownMs = Number(cfg.cooldownSeconds || 8) * 1000;
  var sampleW = 160;
  var sampleH = 90;

  function setStatus(text) {
    if (statusEl) statusEl.textContent = text;
  }

  async function startCamera() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      setStatus("Camera API not available.");
      return;
    }
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        audio: false,
        video: { facingMode: "user", width: { ideal: 1280 }, height: { ideal: 720 } },
      });
      video.srcObject = stream;
      requestAnimationFrame(loop);
      setStatus(armed ? "Armed — watching for motion" : "Disarmed — preview only");
    } catch (err) {
      setStatus("Could not open front camera.");
    }
  }

  function scoreMotion(frame) {
    if (!previous) {
      previous = frame;
      return 0;
    }
    var changed = 0;
    var total = frame.length / 4;
    for (var i = 0; i < frame.length; i += 4) {
      var d =
        Math.abs(frame[i] - previous[i]) +
        Math.abs(frame[i + 1] - previous[i + 1]) +
        Math.abs(frame[i + 2] - previous[i + 2]);
      if (d > 40) changed += 1;
    }
    previous = frame;
    return (changed / total) * 100;
  }

  async function maybeSendSnapshot() {
    var now = Date.now();
    if (now - lastSent < cooldownMs) return;
    lastSent = now;
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    var ctx = canvas.getContext("2d");
    ctx.drawImage(video, 0, 0);
    canvas.toBlob(async function (blob) {
      if (!blob) return;
      var data = new FormData();
      data.append("photo", blob, "motion.jpg");
      data.append("note", "Motion detected");
      try {
        var res = await fetch("/api/security/motion", { method: "POST", body: data });
        var json = await res.json();
        if (json.ok) {
          setStatus("Motion saved " + new Date().toLocaleTimeString());
        }
      } catch (err) {
        setStatus("Motion upload failed — check LAN connection");
      }
    }, "image/jpeg", 0.7);
  }

  function loop() {
    if (video.readyState >= 2) {
      diffCanvas.width = sampleW;
      diffCanvas.height = sampleH;
      var ctx = diffCanvas.getContext("2d", { willReadFrequently: true });
      ctx.drawImage(video, 0, 0, sampleW, sampleH);
      var frame = ctx.getImageData(0, 0, sampleW, sampleH).data;
      var score = scoreMotion(new Uint8ClampedArray(frame));
      if (armed && score >= threshold) {
        maybeSendSnapshot();
      }
    }
    requestAnimationFrame(loop);
  }

  armBtn.addEventListener("click", async function () {
    var data = new FormData();
    data.append("armed", armed ? "false" : "true");
    if (pinInput && pinInput.value) data.append("pin", pinInput.value);
    try {
      var res = await fetch("/api/security/arm", { method: "POST", body: data });
      if (res.status === 403) {
        setStatus("Wrong PIN");
        return;
      }
      var json = await res.json();
      armed = !!json.armed;
      armBtn.textContent = armed ? "Disarm" : "Arm guard";
      armBtn.classList.toggle("danger", armed);
      setStatus(armed ? "Armed — watching for motion" : "Disarmed — preview only");
      previous = null;
    } catch (err) {
      setStatus("Could not change arm state");
    }
  });

  startCamera();
})();
