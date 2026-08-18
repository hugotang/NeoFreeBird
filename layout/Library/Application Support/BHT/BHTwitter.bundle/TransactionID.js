// Module ids change per build, so the generator is found by source signature.
(function () {
  if (window.__twTransactionID) return;

  var CHUNK = "webpackChunk_twitter_responsive_web";
  var SIGNATURE = ["x-client-transaction-id", "rweb_client_transaction_id_enabled"];

  // Webpack's bootstrap replays whatever is already in the chunk array, so an entry
  // pushed before the runtime installs still has its callback run.
  function requireFn() {
    if (window.__twRequire) return Promise.resolve(window.__twRequire);

    window[CHUNK] = window[CHUNK] || [];
    return new Promise(function (resolve, reject) {
      var settled = false;
      var timer = setTimeout(function () {
        if (!settled) {
          settled = true;
          reject(new Error("webpack runtime did not install"));
        }
      }, 15000);

      window[CHUNK].push([
        ["__tw"],
        {},
        function (req) {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          window.__twRequire = req;
          resolve(req);
        },
      ]);
    });
  }

  function valid(token) {
    if (typeof token !== "string" || token.length < 64) return false;
    if (!/^[A-Za-z0-9+/=_-]+$/.test(token)) return false;
    // The client encodes its own failures as btoa("e:" + message).
    try {
      return atob(token).slice(0, 2) !== "e:";
    } catch (e) {
      return true;
    }
  }

  async function generate(host, path, method) {
    if (window.__twGenerator) return await window.__twGenerator(host, path, method);

    var req = await requireFn();
    if (!req || !req.m) throw new Error("no module registry");

    var modules = Object.keys(req.m).filter(function (id) {
      var source;
      try {
        source = req.m[id].toString();
      } catch (e) {
        return false;
      }
      return SIGNATURE.every(function (mark) {
        return source.indexOf(mark) !== -1;
      });
    });
    if (!modules.length) throw new Error("transaction module not found");

    for (var i = 0; i < modules.length; i++) {
      var exports;
      try {
        exports = req(modules[i]);
      } catch (e) {
        continue;
      }

      for (var name in exports) {
        var candidate;
        try {
          candidate = exports[name];
        } catch (e) {
          continue;
        }
        if (typeof candidate !== "function") continue;

        try {
          var token = await candidate(host, path, method);
          if (valid(token)) {
            window.__twGenerator = candidate;
            return token;
          }
        } catch (e) {
          /* not this export */
        }
      }
    }

    throw new Error("generator export not found");
  }

  window.__twTransactionID = async function (path, method) {
    try {
      var token = await generate("https://x.com", path, method);
      return valid(token) ? token : "";
    } catch (e) {
      return "";
    }
  };
})();
