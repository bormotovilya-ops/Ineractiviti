/**
 * Отправка письма с приглашением в проект (Resend).
 *
 * Секреты в Supabase Dashboard → Edge Functions → send-project-invite:
 *   RESEND_API_KEY — API key Resend
 *   INVITE_FROM_EMAIL — отправитель, например onboarding@resend.dev или ваш домен
 *
 * Деплой: supabase functions deploy send-project-invite
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.0";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const resendKey = Deno.env.get("RESEND_API_KEY") ?? "";
  const fromEmail =
    Deno.env.get("INVITE_FROM_EMAIL") ?? "onboarding@resend.dev";

  const authHeader = req.headers.get("Authorization") ?? "";

  let body: { invite_id?: string; invite_token?: string; accept_url?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const inviteId = typeof body.invite_id === "string" ? body.invite_id.trim() : "";
  const inviteToken =
    typeof body.invite_token === "string" ? body.invite_token.trim() : "";
  const acceptUrl =
    typeof body.accept_url === "string" ? body.accept_url.trim() : "";
  if ((!inviteId && !inviteToken) || !acceptUrl) {
    return new Response(
      JSON.stringify({ error: "invite_token_or_id_and_accept_url_required" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  if (!supabaseUrl || !serviceKey || !anonKey) {
    return new Response(JSON.stringify({ error: "server_misconfigured" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const {
    data: { user },
    error: userErr,
  } = await userClient.auth.getUser();
  if (userErr || !user) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let invQuery = admin
    .from("project_invites")
    .select("id, project_id, email, role, invited_by, status")
    .eq("status", "pending");
  if (inviteToken) {
    invQuery = invQuery.eq("invite_token", inviteToken);
  } else {
    invQuery = invQuery.eq("id", inviteId);
  }
  const { data: invite, error: invErr } = await invQuery.maybeSingle();

  if (invErr || !invite || invite.status !== "pending") {
    return new Response(JSON.stringify({ error: "invite_not_found" }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let allowed = invite.invited_by === user.id;
  if (!allowed) {
    const { data: mem, error: memErr } = await admin
      .from("project_members")
      .select("role")
      .eq("project_id", invite.project_id)
      .eq("user_id", user.id)
      .maybeSingle();
    allowed = !memErr && mem?.role === "admin";
  }
  if (!allowed) {
    return new Response(JSON.stringify({ error: "forbidden" }), {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const { data: project, error: projErr } = await admin
    .from("projects")
    .select("title")
    .eq("id", invite.project_id)
    .maybeSingle();

  const projectTitle =
    (!projErr && project && project.title) ? String(project.title) : "проект";

  const toEmail = String(invite.email || "").trim();
  if (!toEmail) {
    return new Response(JSON.stringify({ error: "no_invitee_email" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (!resendKey) {
    return new Response(
      JSON.stringify({
        sent: false,
        reason: "resend_not_configured",
        invite_url: acceptUrl,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const safeUrl = acceptUrl.replace(/"/g, "&quot;");
  const safeTitle = projectTitle.replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const roleLabel =
    invite.role === "methodologist" ? "методолога" : "слушателя";

  const html = `
<!DOCTYPE html>
<html lang="ru">
<head><meta charset="utf-8" /></head>
<body style="font-family:system-ui,sans-serif;line-height:1.5;color:#111;">
  <p>Вас пригласили в проект «<strong>${safeTitle}</strong>» на платформе Интерактивити (роль: ${roleLabel}).</p>
  <p><a href="${safeUrl}" style="display:inline-block;padding:10px 18px;background:#0ea5e9;color:#fff;text-decoration:none;border-radius:8px;">Перейти и принять приглашение</a></p>
  <p style="font-size:14px;color:#555;">Если кнопка не открывается, скопируйте ссылку в браузер:<br/><span style="word-break:break-all;">${safeUrl}</span></p>
  <p style="font-size:13px;color:#888;">Войдите в аккаунт с email <strong>${toEmail.replace(/</g, "&lt;")}</strong> — он должен совпадать с адресом приглашения.</p>
</body>
</html>`;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: fromEmail,
      to: [toEmail],
      subject: `Приглашение в проект «${projectTitle}» — Интерактивити`,
      html,
    }),
  });

  if (!res.ok) {
    const t = await res.text();
    console.error("Resend error", res.status, t);
    return new Response(
      JSON.stringify({
        sent: false,
        reason: "resend_api_error",
        detail: t.slice(0, 500),
        invite_url: acceptUrl,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  return new Response(JSON.stringify({ sent: true }), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
