(function () {
  function tick() {
    var el = document.getElementById("clock");
    if (!el) return;
    var now = new Date();
    el.textContent = now.toLocaleString(undefined, {
      weekday: "short",
      hour: "numeric",
      minute: "2-digit",
    });
  }
  tick();
  setInterval(tick, 15000);

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("/static/sw.js").catch(function () {});
  }
})();
