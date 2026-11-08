(function () {
  "use strict";

  var STAFF = ["teller", "admin"];
  var state = { account: null, hideBalance: false, pending: null };

  // ---------- helpers ----------
  function $(id) { return document.getElementById(id); }
  function show(el) { el.classList.remove("hidden"); }
  function hide(el) { el.classList.add("hidden"); }

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  var nf = new Intl.NumberFormat("vi-VN");
  function money(v) { return nf.format(Math.round(Number(v))) + " VND"; }
  function dt(v) {
    return new Date(v).toLocaleString("vi-VN", {
      day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit"
    });
  }
  function digits(s) { return String(s).replace(/\D/g, ""); }

  function api(path, method, body) {
    var opt = { method: method || "GET", credentials: "same-origin", headers: {} };
    if (body !== undefined) {
      opt.headers["Content-Type"] = "application/json";
      opt.body = JSON.stringify(body);
    }
    return fetch(path, opt).then(function (res) {
      return res.json().catch(function () { return {}; }).then(function (data) {
        if (res.status === 401 && path !== "/api/login" && path !== "/api/me") {
          sessionExpired();
        }
        return { ok: res.ok, status: res.status, data: data };
      });
    }, function () {
      return { ok: false, status: 0, data: { detail: "Không thể kết nối tới ngân hàng. Vui lòng kiểm tra mạng." } };
    });
  }

  function errText(r) {
    if (r.status === 429 || r.status === 503) return "Bạn thao tác quá nhiều lần. Vui lòng thử lại sau ít phút.";
    var d = r.data && r.data.detail;
    if (typeof d === "string") return d;
    if (Array.isArray(d)) return "Thông tin nhập vào không hợp lệ.";
    return "Có lỗi xảy ra (mã " + r.status + "). Vui lòng thử lại.";
  }

  function setError(el, msg) {
    if (msg) { el.textContent = msg; show(el); } else { el.textContent = ""; hide(el); }
  }

  // ---------- views ----------
  function showLogin() {
    hide($("view-app")); hide($("header-user"));
    show($("view-login")); show($("header-guest"));
    $("password").value = "";
    $("username").focus();
  }

  function showApp(me) {
    hide($("view-login")); hide($("header-guest"));
    show($("view-app")); show($("header-user"));
    $("user-name").textContent = me.full_name;
    $("acc-holder").textContent = me.full_name.toUpperCase();
    openTab(location.hash.replace("#", "") || "overview");
  }

  function sessionExpired() {
    alert("Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.");
    location.hash = "";
    showLogin();
  }

  // ---------- login ----------
  $("pw-toggle").addEventListener("click", function () {
    var p = $("password");
    var isPw = p.type === "password";
    p.type = isPw ? "text" : "password";
    this.textContent = isPw ? "Ẩn" : "Hiện";
  });

  $("login-form").addEventListener("submit", function (e) {
    e.preventDefault();
    var u = $("username").value.trim();
    var p = $("password").value;
    var err = $("login-error");
    if (!u || !p) { setError(err, "Vui lòng nhập tên đăng nhập và mật khẩu."); return; }

    var btn = $("btn-login");
    btn.disabled = true; btn.textContent = "Đang xử lý...";
    setError(err, "");

    api("/api/login", "POST", { username: u, password: p }).then(function (r) {
      btn.disabled = false; btn.textContent = "Đăng nhập";
      if (!r.ok) { setError(err, errText(r)); $("password").value = ""; return; }
      if (STAFF.indexOf(r.data.role) !== -1) { location.replace("/admin/"); return; }
      showApp(r.data);
    });
  });

  $("btn-logout").addEventListener("click", function () {
    api("/api/logout", "POST").then(function () {
      state.account = null;
      location.hash = "";
      showLogin();
    });
  });

  // ---------- tabs ----------
  function openTab(name) {
    if (["overview", "transfer", "history"].indexOf(name) === -1) name = "overview";
    ["overview", "transfer", "history"].forEach(function (t) {
      $("tab-" + t).classList.toggle("hidden", t !== name);
    });
    document.querySelectorAll(".side-nav a").forEach(function (a) {
      a.classList.toggle("active", a.getAttribute("data-tab") === name);
    });
    if (name === "overview") loadOverview();
    if (name === "transfer") initTransfer();
    if (name === "history") loadHistory();
  }

  document.addEventListener("click", function (e) {
    var a = e.target.closest("a[data-tab]");
    if (!a) return;
    e.preventDefault();
    var t = a.getAttribute("data-tab");
    history.replaceState(null, "", "#" + t);
    openTab(t);
  });

  // ---------- overview ----------
  function renderBalance() {
    if (!state.account) return;
    $("acc-balance").textContent = state.hideBalance ? "******** VND" : money(state.account.balance);
    $("btn-toggle-balance").textContent = state.hideBalance ? "Hiện số dư" : "Ẩn số dư";
  }

  $("btn-toggle-balance").addEventListener("click", function () {
    state.hideBalance = !state.hideBalance;
    renderBalance();
  });

  function loadAccount() {
    return api("/api/my-account").then(function (r) {
      if (!r.ok) return null;
      state.account = r.data;
      $("acc-no").textContent = r.data.account_no.replace(/(\d{4})(?=\d)/g, "$1 ");
      renderBalance();
      return r.data;
    });
  }

  function txRow(t, full) {
    var sign = t.direction === "IN" ? "+" : "-";
    var cls = t.direction === "IN" ? "amt-in" : "amt-out";
    var desc = t.note ? esc(t.note) : (t.direction === "IN" ? "Nhận tiền" : "Chuyển tiền");
    var party = esc(t.counterpart) + '<span class="sub">' + esc((t.counterpart_name || "").toUpperCase()) + "</span>";
    if (full) {
      return "<tr><td>" + dt(t.created_at) + "</td><td>" + t.id + "</td><td>" + party + "</td><td>" + desc +
        '</td><td class="num ' + cls + '">' + sign + money(t.amount) + "</td></tr>";
    }
    return "<tr><td>" + dt(t.created_at) + "</td><td>" + desc +
      '<span class="sub">' + (t.direction === "IN" ? "Từ " : "Đến ") + esc(t.counterpart) + "</span></td>" +
      '<td class="num ' + cls + '">' + sign + money(t.amount) + "</td></tr>";
  }

  function loadOverview() {
    loadAccount();
    api("/api/my-transactions?limit=5").then(function (r) {
      var items = (r.ok && r.data.items) || [];
      $("recent-tx").innerHTML = items.length
        ? items.map(function (t) { return txRow(t, false); }).join("")
        : '<tr><td colspan="3" class="empty">Chưa có giao dịch.</td></tr>';
    });
  }

  function loadHistory() {
    api("/api/my-transactions?limit=50").then(function (r) {
      var items = (r.ok && r.data.items) || [];
      $("history-tx").innerHTML = items.length
        ? items.map(function (t) { return txRow(t, true); }).join("")
        : '<tr><td colspan="5" class="empty">Chưa có giao dịch.</td></tr>';
    });
  }

  // ---------- transfer ----------
  function transferStep(step) {
    ["input", "confirm", "done"].forEach(function (s) {
      $("transfer-step-" + s).classList.toggle("hidden", s !== step);
    });
  }

  function initTransfer() {
    transferStep("input");
    setError($("tf-error"), "");
    loadAccount().then(function (acc) {
      if (!acc) return;
      $("tf-src").textContent = acc.account_no;
      $("tf-src-balance").textContent = "Số dư: " + money(acc.balance);
    });
  }

  var lookupTimer = null;
  var recipient = null;

  $("tf-to").addEventListener("input", function () {
    this.value = digits(this.value);
    recipient = null;
    var hint = $("tf-to-name");
    hint.className = "field-hint"; hint.textContent = "";
    clearTimeout(lookupTimer);
    var no = this.value;
    if (no.length < 6) return;
    lookupTimer = setTimeout(function () {
      api("/api/accounts/lookup?account_no=" + encodeURIComponent(no)).then(function (r) {
        if ($("tf-to").value !== no) return;
        if (r.ok) {
          recipient = r.data;
          hint.className = "field-hint ok"; hint.textContent = r.data.holder;
        } else {
          hint.className = "field-hint err"; hint.textContent = errText(r);
        }
      });
    }, 400);
  });

  $("tf-amount").addEventListener("input", function () {
    var d = digits(this.value).replace(/^0+/, "");
    this.value = d ? nf.format(Number(d)) : "";
    $("tf-amount-words").textContent = d ? money(d) : "";
  });

  $("transfer-form").addEventListener("submit", function (e) {
    e.preventDefault();
    var err = $("tf-error");
    var amount = Number(digits($("tf-amount").value));
    var to = $("tf-to").value;

    if (!recipient || recipient.account_no !== to) { setError(err, "Vui lòng nhập số tài khoản nhận hợp lệ."); return; }
    if (!amount || amount < 1000) { setError(err, "Số tiền chuyển tối thiểu là 1.000 VND."); return; }
    if (state.account && amount > Number(state.account.balance)) { setError(err, "Số dư không đủ để thực hiện giao dịch."); return; }
    setError(err, "");

    state.pending = { to_account: to, amount: amount, note: $("tf-note").value.trim(), holder: recipient.holder };
    $("cf-src").textContent = state.account.account_no;
    $("cf-to").textContent = to;
    $("cf-name").textContent = recipient.holder;
    $("cf-amount").textContent = money(amount);
    $("cf-note").textContent = state.pending.note || "(không có)";
    setError($("cf-error"), "");
    transferStep("confirm");
  });

  $("btn-cf-back").addEventListener("click", function () { transferStep("input"); });

  $("btn-cf-ok").addEventListener("click", function () {
    var btn = this;
    var p = state.pending;
    if (!p) return;
    btn.disabled = true; btn.textContent = "Đang xử lý...";
    api("/api/transfer", "POST", { to_account: p.to_account, amount: p.amount, note: p.note }).then(function (r) {
      btn.disabled = false; btn.textContent = "Xác nhận chuyển";
      if (!r.ok) { setError($("cf-error"), errText(r)); return; }
      $("dn-id").textContent = r.data.transaction_id;
      $("dn-time").textContent = dt(r.data.created_at);
      $("dn-amount").textContent = money(p.amount);
      $("dn-to").textContent = p.to_account + " - " + p.holder;
      $("dn-balance").textContent = money(r.data.balance);
      if (state.account) state.account.balance = r.data.balance;
      state.pending = null;
      transferStep("done");
    });
  });

  $("btn-new-transfer").addEventListener("click", function () {
    $("transfer-form").reset();
    $("tf-to-name").textContent = "";
    $("tf-amount-words").textContent = "";
    recipient = null;
    initTransfer();
  });

  // ---------- khởi động ----------
  api("/api/me").then(function (r) {
    if (r.ok) {
      if (STAFF.indexOf(r.data.role) !== -1) { location.replace("/admin/"); return; }
      showApp(r.data);
    } else {
      showLogin();
    }
  });
})();
