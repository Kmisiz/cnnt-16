(function () {
  "use strict";

  var ROLE_NAME = { customer: "Khách hàng", teller: "Giao dịch viên", admin: "Quản trị viên" };
  var me = null;

  function $(id) { return document.getElementById(id); }
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
  function setMsg(el, msg) {
    if (msg) { el.textContent = msg; el.classList.remove("hidden"); } else { el.textContent = ""; el.classList.add("hidden"); }
  }

  function api(path, method, body) {
    var opt = { method: method || "GET", credentials: "same-origin", headers: {} };
    if (body !== undefined) { opt.headers["Content-Type"] = "application/json"; opt.body = JSON.stringify(body); }
    return fetch(path, opt).then(function (res) {
      return res.json().catch(function () { return {}; }).then(function (data) {
        if (res.status === 401) { location.replace("/"); }
        return { ok: res.ok, status: res.status, data: data };
      });
    }, function () { return { ok: false, status: 0, data: { detail: "Mất kết nối tới máy chủ." } }; });
  }
  function errText(r) {
    var d = r.data && r.data.detail;
    if (typeof d === "string") return d;
    if (Array.isArray(d)) return "Dữ liệu nhập không hợp lệ: " + d.map(function (x) { return x.loc[x.loc.length - 1]; }).join(", ");
    return "Lỗi " + r.status;
  }

  function statusTag(s) {
    var cls = s === "SUCCESS" ? "tag-ok" : (s === "FAILED" ? "tag-warn" : "tag-bad");
    return '<span class="tag ' + cls + '">' + esc(s) + "</span>";
  }
  function activeTag(a) {
    return a ? '<span class="tag tag-ok">Hoạt động</span>' : '<span class="tag tag-bad">Đã khóa</span>';
  }

  // ---------- tabs ----------
  var TABS = ["accounts", "users", "create", "logs"];
  function isAdmin() { return me && me.role === "admin"; }

  function openTab(name) {
    if (TABS.indexOf(name) === -1) name = "accounts";
    var link = document.querySelector('.side-nav a[data-tab="' + name + '"]');
    if (link && link.hasAttribute("data-admin") && !isAdmin()) name = "accounts";
    TABS.forEach(function (t) { $("tab-" + t).classList.toggle("hidden", t !== name); });
    document.querySelectorAll(".side-nav a").forEach(function (a) {
      a.classList.toggle("active", a.getAttribute("data-tab") === name);
    });
    if (name === "accounts") loadAccounts();
    if (name === "users") loadUsers();
    if (name === "logs") loadLogs();
  }

  document.addEventListener("click", function (e) {
    var a = e.target.closest("a[data-tab]");
    if (!a) return;
    e.preventDefault();
    history.replaceState(null, "", "#" + a.getAttribute("data-tab"));
    openTab(a.getAttribute("data-tab"));
  });

  // ---------- accounts ----------
  function loadAccounts() {
    api("/api/accounts").then(function (r) {
      var items = (r.ok && r.data.items) || [];
      $("accounts-body").innerHTML = items.length ? items.map(function (a) {
        return "<tr><td>" + esc(a.account_no) + "</td><td>" + esc(a.full_name) + "</td><td>" + esc(a.username) +
          "</td><td>" + activeTag(a.is_active) + "</td><td>" + dt(a.updated_at) +
          '</td><td class="num">' + money(a.balance) + "</td></tr>";
      }).join("") : '<tr><td colspan="6" class="empty">Không có dữ liệu.</td></tr>';
    });
  }

  // ---------- users ----------
  function loadUsers() {
    setMsg($("users-error"), "");
    api("/api/admin/users").then(function (r) {
      var items = (r.ok && r.data.items) || [];
      $("users-body").innerHTML = items.map(function (u) {
        var action = "";
        if (u.username !== me.username) {
          action = u.is_active
            ? '<button class="btn btn-danger btn-sm" data-lock="' + esc(u.username) + '" data-active="0">Khóa</button>'
            : '<button class="btn btn-light btn-sm" data-lock="' + esc(u.username) + '" data-active="1">Mở khóa</button>';
        }
        return "<tr><td>" + u.id + "</td><td>" + esc(u.username) + "</td><td>" + esc(u.full_name) + "</td><td>" +
          esc(ROLE_NAME[u.role] || u.role) + "</td><td>" + esc(u.account_no || "-") + "</td><td>" + esc(u.created_by || "-") +
          "</td><td>" + activeTag(u.is_active) + "</td><td>" + action + "</td></tr>";
      }).join("");
    });
  }

  $("users-body").addEventListener("click", function (e) {
    var b = e.target.closest("button[data-lock]");
    if (!b) return;
    var username = b.getAttribute("data-lock");
    var active = b.getAttribute("data-active") === "1";
    if (!confirm((active ? "Mở khóa" : "Khóa") + " tài khoản " + username + "?")) return;
    api("/api/admin/users/" + encodeURIComponent(username) + "/status", "PATCH", { is_active: active }).then(function (r) {
      if (!r.ok) { setMsg($("users-error"), errText(r)); return; }
      loadUsers();
    });
  });

  // ---------- create ----------
  $("c-role").addEventListener("change", function () {
    $("c-balance-wrap").classList.toggle("hidden", this.value !== "customer");
  });
  $("c-balance").addEventListener("input", function () {
    var d = this.value.replace(/\D/g, "").replace(/^0+/, "");
    this.value = d ? nf.format(Number(d)) : "0";
  });

  $("create-form").addEventListener("submit", function (e) {
    e.preventDefault();
    setMsg($("create-error"), ""); setMsg($("create-ok"), "");
    var body = {
      username: $("c-username").value.trim(),
      full_name: $("c-fullname").value.trim(),
      password: $("c-password").value,
      role: $("c-role").value,
      initial_balance: Number($("c-balance").value.replace(/\D/g, "") || 0)
    };
    api("/api/admin/users", "POST", body).then(function (r) {
      if (!r.ok) { setMsg($("create-error"), errText(r)); return; }
      var msg = "Đã tạo tài khoản " + r.data.username + " (" + (ROLE_NAME[r.data.role] || r.data.role) + ")";
      if (r.data.account_no) msg += ", số tài khoản " + r.data.account_no;
      setMsg($("create-ok"), msg + ".");
      $("create-form").reset();
      $("c-balance-wrap").classList.remove("hidden");
    });
  });

  // ---------- logs ----------
  function loadLogs() {
    var f = $("log-filter").value;
    api("/api/admin/audit-logs?limit=100" + (f ? "&result=" + f : "")).then(function (r) {
      var items = (r.ok && r.data.items) || [];
      $("logs-body").innerHTML = items.length ? items.map(function (l) {
        return "<tr><td class=\"nowrap\">" + dt(l.event_time) + "</td><td>" + esc(l.username || "-") +
          "</td><td>" + esc(l.action) + "</td><td>" + statusTag(l.status) + "</td><td>" + esc(l.client_ip) +
          "</td><td>" + esc(l.details) + "</td></tr>";
      }).join("") : '<tr><td colspan="6" class="empty">Không có bản ghi.</td></tr>';
    });
  }
  $("log-filter").addEventListener("change", loadLogs);
  $("btn-log-refresh").addEventListener("click", loadLogs);

  // ---------- logout ----------
  $("btn-logout").addEventListener("click", function () {
    api("/api/logout", "POST").then(function () { location.replace("/"); });
  });

  // ---------- khởi động ----------
  api("/api/me").then(function (r) {
    if (!r.ok || (r.data.role !== "admin" && r.data.role !== "teller")) { location.replace("/"); return; }
    me = r.data;
    $("staff-name").textContent = me.full_name;
    $("staff-role").textContent = ROLE_NAME[me.role];
    if (!isAdmin()) {
      document.querySelectorAll(".side-nav a[data-admin]").forEach(function (a) { a.classList.add("hidden"); });
    }
    openTab(location.hash.replace("#", ""));
  });
})();
