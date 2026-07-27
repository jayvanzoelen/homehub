(function () {
  var video = document.getElementById("scan-video");
  var canvas = document.getElementById("scan-canvas");
  var statusEl = document.getElementById("camera-status");
  var captureBtn = document.getElementById("capture-btn");
  var flipBtn = document.getElementById("flip-btn");
  var form = document.getElementById("scan-form");
  var preview = document.getElementById("preview");
  var nameInput = document.getElementById("item-name");
  var saveBtn = document.getElementById("save-btn");
  var msg = document.getElementById("scan-msg");

  var stream = null;
  var facingMode = "user";
  var blob = null;
  var pendingPhotoPath = null;

  function setStatus(text) {
    if (statusEl) statusEl.textContent = text;
  }

  function setMsg(text) {
    if (msg) msg.textContent = text || "";
  }

  async function startCamera() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      setStatus("Camera API not available in this browser.");
      return;
    }
    if (stream) {
      stream.getTracks().forEach(function (t) { t.stop(); });
    }
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        audio: false,
        video: {
          facingMode: facingMode,
          width: { ideal: 1280 },
          height: { ideal: 720 },
        },
      });
      video.srcObject = stream;
      captureBtn.disabled = false;
      flipBtn.disabled = false;
      setStatus(facingMode === "user" ? "Front camera ready" : "Rear camera ready");
    } catch (err) {
      setStatus("Could not open camera. Allow camera access in Safari settings.");
      captureBtn.disabled = true;
    }
  }

  captureBtn.addEventListener("click", function () {
    if (!video.videoWidth) return;
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    var ctx = canvas.getContext("2d");
    // Mirror to match preview for front camera.
    if (facingMode === "user") {
      ctx.translate(canvas.width, 0);
      ctx.scale(-1, 1);
    }
    ctx.drawImage(video, 0, 0);
    canvas.toBlob(function (b) {
      if (!b) return;
      blob = b;
      pendingPhotoPath = null;
      preview.src = URL.createObjectURL(b);
      preview.classList.remove("hidden");
      saveBtn.disabled = false;
      setMsg("Looks good — name it and save.");
    }, "image/jpeg", 0.85);
  });

  flipBtn.addEventListener("click", function () {
    facingMode = facingMode === "user" ? "environment" : "user";
    startCamera();
  });

  form.addEventListener("submit", async function (ev) {
    ev.preventDefault();
    saveBtn.disabled = true;
    setMsg("Saving…");

    try {
      if (pendingPhotoPath) {
        var confirmData = new FormData();
        confirmData.append("name", nameInput.value.trim());
        confirmData.append("photo_path", pendingPhotoPath);
        confirmData.append("quantity", document.getElementById("item-qty").value);
        confirmData.append("unit", document.getElementById("item-unit").value);
        confirmData.append("location", document.getElementById("item-location").value);
        var exp = document.getElementById("item-expires").value;
        if (exp) confirmData.append("expires_on", exp);
        var confirmRes = await fetch("/api/scan/confirm", { method: "POST", body: confirmData });
        var confirmJson = await confirmRes.json();
        if (!confirmRes.ok || !confirmJson.ok) throw new Error("Confirm failed");
        setMsg("Saved “" + confirmJson.name + "”.");
        pendingPhotoPath = null;
        blob = null;
        nameInput.value = "";
        preview.classList.add("hidden");
        return;
      }

      if (!blob) {
        setMsg("Capture a photo first.");
        return;
      }

      var data = new FormData();
      data.append("photo", blob, "capture.jpg");
      data.append("name", nameInput.value.trim());
      data.append("quantity", document.getElementById("item-qty").value);
      data.append("unit", document.getElementById("item-unit").value);
      data.append("location", document.getElementById("item-location").value);
      var expires = document.getElementById("item-expires").value;
      if (expires) data.append("expires_on", expires);
      data.append("suggest", document.getElementById("suggest").checked ? "true" : "false");

      var res = await fetch("/api/scan", { method: "POST", body: data });
      var json = await res.json();
      if (json.needs_name) {
        pendingPhotoPath = json.photo_path;
        if (json.suggested_name) nameInput.value = json.suggested_name;
        setMsg("Name this item, then save again.");
        nameInput.focus();
        return;
      }
      if (!res.ok || !json.ok) throw new Error("Save failed");
      setMsg("Saved “" + json.name + "” to pantry.");
      blob = null;
      nameInput.value = "";
      preview.classList.add("hidden");
    } catch (err) {
      setMsg("Could not save. Check the hub connection and try again.");
    } finally {
      saveBtn.disabled = false;
    }
  });

  startCamera();
})();
