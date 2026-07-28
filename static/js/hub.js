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

  var confirmForms = document.querySelectorAll("form[data-confirm]");
  for (var i = 0; i < confirmForms.length; i += 1) {
    confirmForms[i].addEventListener("submit", function (event) {
      var message = this.getAttribute("data-confirm") || "Continue?";
      if (!window.confirm(message)) event.preventDefault();
    });
  }
})();
