/* Natação é Viver. API via fetch: funciona em Shiny e em Shinylive/GitHub Pages.
 * Sessão apenas na memória desta aba. Nenhuma senha/token vai para inputs Shiny.
 */
(function (root) {
  "use strict";
  class NatacaoClient {
    constructor(config, events = {}, fetchImpl = root.fetch.bind(root)) {
      this.url = (config.supabaseUrl || "").replace(/\/+$/, "");
      this.key = config.supabasePublishableKey || "";
      this.events = events;
      this.fetch = fetchImpl;
      this.session = null;
      this.user = null;
      this.rows = [];
      this.ready = false;
      this.epoch = 0;
      this.revision = 0;
      this.pulling = false;
      this.saving = false;
      this.refreshing = null;
      this.lastSync = null;
    }
    configured() {
      if (!/^https:\/\/[^\s/]+/.test(this.url) || !this.key) return false;
      if (this.key.startsWith("sb_secret_")) return false;
      if (this.key.startsWith("sb_publishable_")) return true;
      try {
        const payload = JSON.parse(root.atob(this.key.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
        return payload.role === "anon";
      } catch (_) { return false; }
    }
    emit(name, value) { if (this.events[name]) this.events[name](value); }
    status(message = "") {
      this.emit("status", { state: !this.configured() ? "notconfigured" :
        (this.user ? "signed_in" : "signed_out"), user: this.user,
        ready: this.ready, message, lastSync: this.lastSync });
    }
    data() { this.emit("data", { rows: this.rows }); }
    message(error) {
      if (String(error.message).includes("CONFLITO_EDICAO"))
        return "Outra pessoa atualizou esta escola. Feche a edição, confira os dados atuais e abra Editar natação novamente.";
      if (error.status === 401) return "Sua sessão expirou. Entre novamente para continuar.";
      if (error.status === 403 || String(error.message).includes("SEM_PERMISSAO"))
        return "Esta conta não está autorizada a acessar os dados de natação.";
      return "Não foi possível confirmar a operação online. Confira sua conexão e tente Atualizar dados. Seus campos de edição foram mantidos.";
    }
    async http(path, body, token) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 15000);
      try {
        const response = await this.fetch(this.url + path, {
          method: body === undefined ? "GET" : "POST",
          headers: { apikey: this.key, "Content-Type": "application/json",
            ...(token ? { Authorization: "Bearer " + token } : {}) },
          ...(body === undefined ? {} : { body: JSON.stringify(body) }),
          signal: controller.signal, cache: "no-store"
        });
        const text = await response.text();
        let data = null;
        try { data = text ? JSON.parse(text) : null; } catch (_) { /* tratado abaixo */ }
        if (!response.ok) {
          const error = new Error(data?.message || data?.msg || data?.error_description || "Falha de conexão");
          error.status = response.status;
          throw error;
        }
        if (text && data === null) throw new Error("Resposta inválida da API");
        return data;
      } finally { clearTimeout(timeout); }
    }
    acceptSession(data) {
      if (!data?.access_token || !data?.refresh_token || !data?.user?.id)
        throw new Error("Sessão inválida");
      this.session = { ...data, expires_at: data.expires_at || Date.now() / 1000 + data.expires_in };
    }
    async renew() {
      if (this.refreshing) return this.refreshing;
      const epoch = this.epoch;
      this.refreshing = (async () => {
        try {
          const data = await this.http("/auth/v1/token?grant_type=refresh_token",
            { refresh_token: this.session.refresh_token });
          if (epoch !== this.epoch) throw new Error("Sessão encerrada");
          this.acceptSession(data);
        } catch (error) {
          if (epoch === this.epoch && [400, 401, 403].includes(error.status)) {
            await this.logout(false);
            error.status = 401;
          }
          throw error;
        }
      })();
      try { return await this.refreshing; } finally { this.refreshing = null; }
    }
    async request(path, body) {
      if (!this.session) throw Object.assign(new Error("Sessão encerrada"), { status: 401 });
      if (this.session.expires_at < Date.now() / 1000 + 60) await this.renew();
      try { return await this.http(path, body, this.session.access_token); }
      catch (error) {
        if (error.status !== 401 || !this.session) throw error;
        await this.renew();
        return this.http(path, body, this.session.access_token);
      }
    }
    async login(email, password) {
      if (!this.configured()) { this.status("Preencha www/config.js antes de entrar."); return; }
      const epoch = ++this.epoch;
      try {
        const data = await this.http("/auth/v1/token?grant_type=password", { email: email.trim(), password });
        if (epoch !== this.epoch) return;
        this.acceptSession(data);
        const access = await this.request("/rest/v1/nv_editores?select=nome&user_id=eq." + encodeURIComponent(data.user.id));
        if (epoch !== this.epoch) return;
        if (!Array.isArray(access) || access.length !== 1) {
          await this.logout(false);
          this.status("Esta conta não está autorizada. Confira o cadastro de editores no Supabase.");
          return;
        }
        this.user = { id: data.user.id, nome: access[0].nome };
        this.status();
        await this.pull();
      } catch (error) {
        if (epoch !== this.epoch) return;
        await this.logout(false);
        this.status(error.status === 400 ? "E-mail ou senha inválidos, ou conta ainda não confirmada." : this.message(error));
      }
    }
    async logout(remote = true) {
      const token = this.session?.access_token;
      ++this.epoch;
      ++this.revision;
      this.session = null;
      this.user = null;
      this.ready = false;
      this.rows = [];
      this.lastSync = null;
      this.data();
      this.status();
      if (remote && token) {
        try { await this.http("/auth/v1/logout?scope=local", {}, token); } catch (_) { /* sessão local encerrada */ }
      }
    }
    async pull() {
      if (!this.user || this.pulling || this.saving) return;
      const epoch = this.epoch, revision = this.revision;
      this.pulling = true;
      try {
        const access = await this.request("/rest/v1/nv_editores?select=nome&user_id=eq." + encodeURIComponent(this.user.id));
        if (epoch !== this.epoch) return;
        if (!Array.isArray(access) || !access.length) {
          await this.logout(false);
          this.status("O acesso desta conta foi removido.");
          return;
        }
        const rows = [];
        const fields = "inep,tem_piscina,estrutura,alunos_natacao,versao,atualizado_em,atualizado_por";
        for (let offset = 0; ; offset += 500) {
          const page = await this.request("/rest/v1/nv_natacao?select=" + fields +
            "&order=inep.asc&offset=" + offset + "&limit=500");
          if (epoch !== this.epoch || revision !== this.revision) return;
          if (!Array.isArray(page)) throw new Error("Resposta inválida");
          rows.push(...page);
          if (page.length < 500) break;
        }
        this.rows = rows;
        this.ready = true;
        this.lastSync = new Date().toISOString();
        this.data();
        this.status();
      } catch (error) {
        if (epoch === this.epoch) this.status(this.message(error));
      } finally { this.pulling = false; }
    }
    async save(command) {
      if (this.saving) return;
      const result = { requestId: command.requestId, inep: command.inep };
      const epoch = this.epoch;
      this.saving = true;
      ++this.revision; // Descarta leituras que começaram antes desta gravação.
      try {
        if (!this.user || !this.ready) throw Object.assign(new Error("Entre novamente"), { status: 401 });
        const { inep, tem_piscina, estrutura, alunos_natacao, versao } = command;
        if (!/^[0-9]{8}$/.test(inep) || !Number.isSafeInteger(versao) || versao < 0 ||
            ![null, true, false].includes(tem_piscina) ||
            ![null, "Própria", "Terceirizada", "Não se aplica"].includes(estrutura) ||
            (alunos_natacao !== null && (!Number.isInteger(alunos_natacao) || alunos_natacao < 0 || alunos_natacao > 2147483647)))
          throw new Error("REGISTRO_INVALIDO");
        const data = await this.request("/rest/v1/rpc/nv_salvar_natacao", {
          p_inep: inep, p_tem_piscina: tem_piscina, p_estrutura: estrutura,
          p_alunos_natacao: alunos_natacao, p_versao_esperada: versao
        });
        if (epoch !== this.epoch) return;
        if (!Array.isArray(data) || data.length !== 1 || data[0].inep !== inep) throw new Error("Resposta inválida");
        this.rows = this.rows.filter(row => row.inep !== inep).concat(data[0]);
        this.data();
        this.emit("result", { ...result, ok: true });
      } catch (error) {
        if (epoch === this.epoch) this.emit("result", {
          ...result, ok: false, conflict: String(error.message).includes("CONFLITO_EDICAO"),
          message: this.message(error)
        });
      } finally {
        this.saving = false;
        if (this.user) void this.pull();
      }
    }
  }
  if (typeof module !== "undefined" && module.exports) module.exports = { NatacaoClient };
  if (typeof window === "undefined") return;

  let started = false;
  function boot() {
    if (!window.Shiny || !window.jQuery) { setTimeout(boot, 50); return; }
    if (started) return;
    started = true;
    const send = (id, value) => Shiny.setInputValue(id, value, { priority: "event" });
    const client = new NatacaoClient(window.NV_CONFIG || {}, {
      status: value => send("nv_estado", value), data: value => send("nv_dados", value),
      result: value => send("nv_resultado", value)
    });
    Shiny.addCustomMessageHandler("nv_comando", command => {
      if (command.action === "refresh") void client.pull();
      if (command.action === "logout") void client.logout();
      if (command.action === "save") void client.save(command);
    });
    window.NatacaoOnline = {
      login: async form => {
        const button = form.querySelector("button[type=submit]");
        button.disabled = true;
        try { await client.login(form.elements.email.value, form.elements.password.value); }
        finally { form.elements.password.value = ""; button.disabled = false; }
      }
    };
    window.jQuery(document).on("shiny:connected", () => { client.status(); if (client.user) void client.pull(); });
    if (Shiny.shinyapp?.isConnected()) client.status();
    setInterval(() => { if (!document.hidden) void client.pull(); }, 20000);
    document.addEventListener("visibilitychange", () => { if (!document.hidden) void client.pull(); });
  }
  boot();
})(typeof window === "undefined" ? globalThis : window);
